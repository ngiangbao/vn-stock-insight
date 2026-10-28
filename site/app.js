const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const fmt = (n, d = 2) => (n == null ? "–" : Number(n).toLocaleString("vi-VN", { maximumFractionDigits: d }));
const pct = (n) => (n == null ? "–" : `<span class="${n >= 0 ? "up" : "down"}">${n >= 0 ? "+" : ""}${fmt(n)}%</span>`);
const stanceClass = (s) => ({ "Tích cực": "b-up", "Tiêu cực": "b-down" }[s] || "b-flat");
const sentBadge = (v) =>
  v > 0 ? `<span class="badge b-up">Tích cực ${v > 1 ? "++" : "+"}</span>`
  : v < 0 ? `<span class="badge b-down">Tiêu cực ${v < -1 ? "−−" : "−"}</span>`
  : `<span class="badge b-flat">Trung lập</span>`;
const timeVN = (ts) => new Date(ts * 1000).toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh", dateStyle: "short", timeStyle: "short" });

let DATA = null;

function spark(values, w = 140, h = 40) {
  if (!values || values.length < 2) return "";
  const min = Math.min(...values), max = Math.max(...values), span = max - min || 1;
  const pts = values.map((v, i) => `${(i / (values.length - 1)) * w},${h - ((v - min) / span) * (h - 4) - 2}`).join(" ");
  const color = values.at(-1) >= values[0] ? "var(--up)" : "var(--down)";
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><polyline fill="none" stroke="${color}" stroke-width="1.6" points="${pts}"/></svg>`;
}

const list = (items) => (items?.length ? `<ul class="tight">${items.map((i) => `<li>${esc(i)}</li>`).join("")}</ul>` : `<p class="muted small">–</p>`);

function renderOverview() {
  const { index: ix, brief, stocks } = DATA;
  const all = Object.values(stocks);
  const up = all.filter((s) => s.change_1d > 0).length;
  const down = all.filter((s) => s.change_1d < 0).length;
  const byChange = [...all].filter((s) => s.change_1d != null).sort((a, b) => b.change_1d - a.change_1d);
  const moverRow = (s) => `<tr><td>${esc(s.symbol)}</td><td>${fmt(s.close)}</td><td>${pct(s.change_1d)}</td></tr>`;

  let html = `<div class="stack">
    <div class="card index-card">
      <div><div class="muted small">VN-Index · ${esc(ix.date)}</div><div class="big">${fmt(ix.close)}</div><div>${pct(ix.change_1d)} hôm nay</div></div>
      ${spark(ix.spark, 220, 56)}
      <div class="kv">
        <div>1 tuần<b>${pct(ix.change_1w)}</b></div>
        <div>1 tháng<b>${pct(ix.change_1m)}</b></div>
        <div>3 tháng<b>${pct(ix.change_3m)}</b></div>
        <div>RSI 14<b>${fmt(ix.rsi14, 1)}</b></div>
        <div>VN30 tăng/giảm<b><span class="up">${up}</span> / <span class="down">${down}</span></b></div>
      </div>
    </div>`;

  if (brief) {
    html += `<div class="card">
      <div class="stock-head"><h2>Nhận định thị trường</h2><span class="badge ${stanceClass(brief.mood)}">${esc(brief.mood)}</span></div>
      <p class="headline">${esc(brief.headline)}</p>
      <p>${esc(brief.summary)}</p>
      <div class="grid grid-2">
        <div><div class="section-label">Chủ đề nổi bật</div>
          ${(brief.themes || []).map((t) => `<p><b>${esc(t.theme)}</b> — ${esc(t.detail)}${t.tickers?.length ? `<span class="chips">${t.tickers.map((x) => `<span class="chip">${esc(x)}</span>`).join("")}</span>` : ""}</p>`).join("")}
        </div>
        <div><div class="section-label">Cần theo dõi</div>${list(brief.watch_list)}</div>
      </div>
    </div>`;
  } else if (!DATA.ai_enabled) {
    html += `<div class="notice">Chưa bật phân tích AI. Thêm secret <code>ANTHROPIC_API_KEY</code> vào repo GitHub để có nhận định thị trường và phân tích từng mã.</div>`;
  }

  html += `<div class="grid grid-2">
      <div class="card"><h2>Tăng mạnh nhất (VN30)</h2><table>${byChange.slice(0, 5).map(moverRow).join("")}</table></div>
      <div class="card"><h2>Giảm mạnh nhất (VN30)</h2><table>${byChange.slice(-5).reverse().map(moverRow).join("")}</table></div>
    </div></div>`;
  $("#overview").innerHTML = html;
}

function renderWatch() {
  const cards = DATA.watchlist.map((sym) => {
    const s = DATA.stocks[sym];
    if (!s) return "";
    const a = DATA.analyses?.[sym];
    const related = DATA.news.filter((n) => n.tickers?.includes(sym)).slice(0, 5);
    return `<article class="card">
      <div class="stock-head">
        <div><h2>${esc(sym)}</h2>${a ? `<span class="badge ${stanceClass(a.stance)}">${esc(a.stance)}</span> <span class="muted small">độ tin cậy: ${esc(a.confidence)}</span>` : ""}</div>
        <div class="price"><div class="big">${fmt(s.close)}</div>${pct(s.change_1d)}</div>
      </div>
      ${spark(s.spark, 300, 48)}
      <div class="kv">
        <div>1 tháng<b>${pct(s.change_1m)}</b></div><div>RSI<b>${fmt(s.rsi14, 1)}</b></div>
        <div>MA20<b>${fmt(s.ma20)}</b></div><div>MA50<b>${fmt(s.ma50)}</b></div>
        <div>KL/TB20<b>${s.vol_ratio ? "x" + fmt(s.vol_ratio) : "–"}</b></div>
      </div>
      ${s.signals.length ? `<div class="chips">${s.signals.map((x) => `<span class="chip">${esc(x)}</span>`).join("")}</div>` : ""}
      ${a ? `<p class="headline">${esc(a.headline)}</p>
        <div class="section-label">Kỹ thuật</div><p>${esc(a.technical_view)}</p>
        <div class="section-label">Tin tức</div><p>${esc(a.news_view)}</p>
        <details><summary>Chi tiết: vùng giá, động lực, rủi ro</summary>
          <div class="section-label">Vùng giá quan trọng</div><p>${esc(a.key_levels)}</p>
          <div class="section-label">Động lực</div>${list(a.catalysts)}
          <div class="section-label">Rủi ro</div>${list(a.risks)}
          <div class="section-label">Cần theo dõi</div>${list(a.watch_points)}
        </details>` : `<p class="muted small">Chưa có phân tích AI.</p>`}
      ${related.length ? `<div class="section-label">Tin liên quan</div>${related.map((n) => `<div class="small"><a href="${esc(n.link)}" target="_blank" rel="noopener">${esc(n.title)}</a></div>`).join("")}` : ""}
    </article>`;
  });
  $("#watch").innerHTML = `<div class="grid grid-2">${cards.join("")}</div>`;
}

const COLS = [
  ["symbol", "Mã"], ["close", "Giá"], ["change_1d", "1 ngày"], ["change_1w", "1 tuần"], ["change_1m", "1 tháng"],
  ["change_3m", "3 tháng"], ["rsi14", "RSI"], ["vol_ratio", "KL/TB20"], ["from_high_52w", "Từ đỉnh 52T"], ["tech_score", "Điểm KT"], ["signals", "Tín hiệu"],
];
let sortKey = "tech_score", sortDir = -1;

function renderScreen() {
  const rows = Object.values(DATA.stocks).sort((a, b) => {
    const x = a[sortKey], y = b[sortKey];
    if (typeof x === "string") return x.localeCompare(y) * sortDir;
    return ((x ?? -Infinity) - (y ?? -Infinity)) * sortDir;
  });
  const cell = (s, k) => {
    if (k === "symbol") return `<td><b>${esc(s.symbol)}</b></td>`;
    if (k === "signals") return `<td class="sig l">${esc(s.signals.join(" · ")) || '<span class="muted">–</span>'}</td>`;
    if (k.startsWith("change") || k === "from_high_52w") return `<td>${pct(s[k])}</td>`;
    if (k === "tech_score") return `<td><span class="badge ${s[k] > 0 ? "b-up" : s[k] < 0 ? "b-down" : "b-flat"}">${s[k] > 0 ? "+" : ""}${s[k]}</span></td>`;
    if (k === "vol_ratio") return `<td>${s[k] ? "x" + fmt(s[k]) : "–"}</td>`;
    return `<td>${fmt(s[k], k === "rsi14" ? 1 : 2)}</td>`;
  };
  $("#screen").innerHTML = `<div class="card">
    <h2>Bộ lọc kỹ thuật VN30</h2>
    <p class="muted small">Bấm vào tiêu đề cột để sắp xếp. "Điểm KT" là tổng điểm từ các tín hiệu xu hướng MA, RSI, MACD và khối lượng (càng cao càng tích cực).</p>
    <div class="table-wrap"><table>
      <thead><tr>${COLS.map(([k, l]) => `<th data-k="${k}" class="${k === "signals" ? "l" : ""}">${l}${k === sortKey ? (sortDir > 0 ? " ▲" : " ▼") : ""}</th>`).join("")}</tr></thead>
      <tbody>${rows.map((s) => `<tr>${COLS.map(([k]) => cell(s, k)).join("")}</tr>`).join("")}</tbody>
    </table></div></div>`;
  document.querySelectorAll("#screen th").forEach((th) =>
    th.addEventListener("click", () => {
      const k = th.dataset.k;
      if (k === "signals") return;
      sortDir = k === sortKey ? -sortDir : -1;
      sortKey = k;
      renderScreen();
    }));
}

function renderNews() {
  const q = $("#news-q").value.trim().toLowerCase();
  const sent = $("#news-sent").value;
  const minImp = Number($("#news-imp").value);
  const items = DATA.news.filter((n) => {
    if (sent === "pos" && !(n.sentiment > 0)) return false;
    if (sent === "neg" && !(n.sentiment < 0)) return false;
    if ((n.importance ?? 1) < minImp) return false;
    if (q && !`${n.title} ${n.ai_summary || ""} ${(n.tickers || []).join(" ")}`.toLowerCase().includes(q)) return false;
    return true;
  });
  $("#news-list").innerHTML = `<div class="card">${items.length ? items.map((n) => `<div class="news-item">
      <a href="${esc(n.link)}" target="_blank" rel="noopener"><b>${esc(n.title)}</b></a>
      ${n.ai_summary ? `<p class="news-sum">${esc(n.ai_summary)}</p>` : ""}
      <div class="news-meta">
        ${n.sentiment != null ? sentBadge(n.sentiment) : ""}
        ${n.importance ? `<span>Mức độ ${n.importance}/5</span>` : ""}
        ${n.category ? `<span>${esc(n.category)}</span>` : ""}
        ${(n.tickers || []).map((t) => `<span class="chip">${esc(t)}</span>`).join("")}
        <span>${esc(n.source)} · ${timeVN(n.published)}</span>
      </div></div>`).join("") : `<p class="muted">Không có tin phù hợp.</p>`}</div>`;
}

async function load(day) {
  const url = day ? `data/history/${day}.json` : "data/latest.json";
  const res = await fetch(`${url}?t=${Date.now()}`);
  DATA = await res.json();
  $("#updated").textContent = `Cập nhật: ${timeVN(DATA.generated_at)}${DATA.ai_enabled ? "" : " · chưa bật AI"}`;
  renderOverview();
  renderWatch();
  renderScreen();
  renderNews();
}

async function init() {
  document.querySelectorAll(".tab").forEach((btn) =>
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab, .panel").forEach((el) => el.classList.remove("active"));
      btn.classList.add("active");
      $(`#${btn.dataset.tab}`).classList.add("active");
    }));
  ["#news-q", "#news-sent", "#news-imp"].forEach((sel) => $(sel).addEventListener("input", renderNews));

  try {
    const days = await (await fetch(`data/history.json?t=${Date.now()}`)).json();
    $("#history").innerHTML = `<option value="">Mới nhất</option>` + days.map((d) => `<option value="${esc(d)}">${esc(d)}</option>`).join("");
    $("#history").addEventListener("change", (e) => load(e.target.value));
  } catch {
    $("#history").hidden = true;
  }
  try {
    await load();
  } catch (err) {
    $("#updated").textContent = "Chưa có dữ liệu. Hãy chạy workflow \"Cập nhật dữ liệu\" trên GitHub Actions.";
  }
}

init();
