// Supabase Edge Function: phân tích chuyên sâu một mã cổ phiếu theo yêu cầu của thành viên.
//
// POST { symbol: "FPT", refresh?: boolean }  (kèm header Authorization của người dùng đã đăng nhập)
// - Dùng lại kết quả gần đây (CACHE_HOURS) cho mọi thành viên để tiết kiệm chi phí.
// - Mỗi thành viên được chạy mới tối đa DAILY_LIMIT lần mỗi 24 giờ.

import Anthropic from "npm:@anthropic-ai/sdk@0.133.0";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { fetchBars, fundamentals, technicals } from "./data.ts";
import { buildPrompt, SCHEMA, SYSTEM } from "./prompt.ts";

const MODEL = Deno.env.get("ANALYSIS_MODEL") ?? "claude-opus-5-5";
const EFFORT = Deno.env.get("ANALYSIS_EFFORT") ?? "medium";
const CACHE_HOURS = Number(Deno.env.get("CACHE_HOURS") ?? 6);
const DAILY_LIMIT = Number(Deno.env.get("DAILY_LIMIT") ?? 10);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const anthropic = new Anthropic();

async function relatedNews(symbol: string) {
  const { data, error } = await admin.storage.from("data").download("latest.json");
  if (error || !data) return [];
  const latest = JSON.parse(await data.text());
  const mention = new RegExp(`\\b${symbol}\\b`);
  return (latest.news ?? [])
    .filter((n: any) => n.tickers?.includes(symbol) || mention.test(n.title))
    .slice(0, 15)
    .map((n: any) => ({
      title: n.title,
      summary: n.ai_summary || n.summary,
      sentiment: n.sentiment,
      importance: n.importance,
      category: n.category,
      source: n.source,
      published: new Date(n.published * 1000).toISOString().slice(0, 16),
    }));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return reply("ok");
  if (req.method !== "POST") return reply({ error: "Chỉ hỗ trợ POST" }, 405);

  const token = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const { data: auth } = await admin.auth.getUser(token);
  const user = auth?.user;
  if (!user) return reply({ error: "Bạn cần đăng nhập" }, 401);

  let body: { symbol?: string; refresh?: boolean };
  try {
    body = await req.json();
  } catch {
    return reply({ error: "Dữ liệu gửi lên không hợp lệ" }, 400);
  }
  const symbol = String(body.symbol ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{3,10}$/.test(symbol)) return reply({ error: "Mã cổ phiếu không hợp lệ" }, 400);

  // 1. Dùng lại kết quả gần đây nếu có
  const since = new Date(Date.now() - CACHE_HOURS * 3600 * 1000).toISOString();
  if (!body.refresh) {
    const { data: cached } = await admin
      .from("stock_analyses")
      .select("*")
      .eq("symbol", symbol)
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (cached) return reply({ ...cached, cached: true });
  }

  // 2. Giới hạn số lần chạy mới của mỗi thành viên
  const dayAgo = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await admin
    .from("stock_analyses")
    .select("id", { count: "exact", head: true })
    .eq("created_by", user.id)
    .gte("created_at", dayAgo);
  if ((count ?? 0) >= DAILY_LIMIT) {
    return reply({ error: `Bạn đã dùng hết ${DAILY_LIMIT} lượt phân tích mới trong 24 giờ. Kết quả đã có vẫn xem được.` }, 429);
  }

  // 3. Thu thập dữ liệu
  const bars = await fetchBars(symbol);
  if (bars.length < 30) return reply({ error: `Không tìm thấy dữ liệu giá cho mã ${symbol}` }, 404);
  const [fund, news] = await Promise.all([fundamentals(symbol), relatedNews(symbol)]);
  const inputs = { technicals: technicals(bars), fundamentals: fund, news };

  // 4. Gọi Claude
  let result;
  try {
    const response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      system: SYSTEM,
      messages: [{ role: "user", content: buildPrompt(symbol, inputs) }],
      output_config: { effort: EFFORT as "low" | "medium" | "high", format: { type: "json_schema", schema: SCHEMA } },
      // Nếu bộ lọc an toàn từ chối nhầm, API tự chạy lại trên model dự phòng
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    });
    if (response.stop_reason === "refusal") {
      return reply({ error: "AI từ chối phân tích yêu cầu này. Hãy thử lại sau." }, 502);
    }
    if (response.stop_reason === "max_tokens") {
      return reply({ error: "Phân tích quá dài và bị cắt. Hãy thử lại." }, 502);
    }
    const text = response.content.find((b) => b.type === "text");
    result = JSON.parse(text && "text" in text ? text.text : "{}");
  } catch (err) {
    console.error(err);
    const status = err instanceof Anthropic.RateLimitError ? 429 : 502;
    return reply({ error: "Không gọi được AI, hãy thử lại sau ít phút." }, status);
  }

  const { data: saved, error } = await admin
    .from("stock_analyses")
    .insert({ symbol, created_by: user.id, model: MODEL, inputs, result })
    .select()
    .single();
  if (error) console.error(error);
  return reply({ ...(saved ?? { symbol, inputs, result, created_at: new Date().toISOString() }), cached: false });
});
