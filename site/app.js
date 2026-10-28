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

// Bộ lọc và tổng quan chỉ dùng rổ cố định (VN30); dữ liệu còn có thêm các mã thành viên theo dõi
const universeStocks = () =>
  (DATA.universe || Object.keys(DATA.stocks)).map((s) => DATA.stocks[s]).filter(Boolean);

function spark(values, w = 140, h = 40) {
  if (!values || values.length < 2) return "";
  const min = Math.min(...values), max = Math.max(...values), span = max - min || 1;
  const pts = values.map((v, i) => `${(i / (values.length - 1)) * w},${h - ((v - min) / span) * (h - 4) - 2}`).join(" ");
  const color = values.at(-1) >= values[0] ? "var(--up)" : "var(--down)";
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><polyline fill="none" stroke="${color}" stroke-width="1.6" points="${pts}"/></svg>`;
}

const list = (items) => (items?.length ? `<ul class="tight">${items.map((i) => `<li>${esc(i)}</li>`).join("")}</ul>` : `<p class="muted small">–</p>`);

function renderOverview() {
  const { index: ix, brief } = DATA;
  const all = universeStocks();
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

// ---------- Danh sách theo dõi ----------
// Có Supabase: lưu riêng cho từng thành viên trong bảng watchlist.
// Chạy trên máy: lưu trong trình duyệt, mặc định lấy danh sách trong config.yml.
let WATCH = [];
let WATCH_LOADED = false;
let LATEST_DEEP = {}; // mã → thời điểm có phân tích chuyên sâu gần nhất

const LOCAL_KEY = "vn-stock-insight.watchlist";
const SYMBOL_RE = /^[A-Z0-9]{3,10}$/;

async function loadWatchlist() {
  if (sb) {
    const { data, error } = await sb.from("watchlist").select("symbol").order("created_at");
    WATCH = error ? [] : data.map((r) => r.symbol);
    if (WATCH.length) {
      const { data: rows } = await sb.from("stock_analyses").select("symbol, created_at")
        .in("symbol", WATCH).order("created_at", { ascending: false }).limit(200);
      LATEST_DEEP = {};
      (rows || []).forEach((r) => { LATEST_DEEP[r.symbol] ??= r.created_at; });
    }
  } else {
    try {
      WATCH = JSON.parse(localStorage.getItem(LOCAL_KEY)) ?? [...DATA.watchlist];
    } catch {
      WATCH = [...DATA.watchlist];
    }
  }
}

function saveLocal() {
  try { localStorage.setItem(LOCAL_KEY, JSON.stringify(WATCH)); } catch {}
}

async function addToWatch(symbol) {
  if (WATCH.includes(symbol)) return;
  if (sb) {
    const { error } = await sb.from("watchlist").insert({ symbol });
    if (error) return alert(`Không thêm được ${symbol}: ${error.message}`);
  }
  WATCH.push(symbol);
  saveLocal();
  renderWatch();
}

async function removeFromWatch(symbol) {
  if (!confirm(`Gỡ ${symbol} khỏi danh sách theo dõi?`)) return;
  if (sb) {
    const { error } = await sb.from("watchlist").delete().eq("symbol", symbol);
    if (error) return alert(`Không gỡ được ${symbol}: ${error.message}`);
  }
  WATCH = WATCH.filter((s) => s !== symbol);
  saveLocal();
  renderWatch();
}

function readSymbol() {
  const symbol = $("#lookup-input").value.trim().toUpperCase();
  if (!SYMBOL_RE.test(symbol)) {
    $("#lookup-msg").textContent = "Nhập mã cổ phiếu gồm 3 chữ cái, ví dụ FPT, HPG, VNM.";
    return null;
  }
  $("#lookup-msg").textContent = "";
  return symbol;
}

function renderWatch() {
  const lookup = `<div class="card lookup">
    <h2>Tra cứu cổ phiếu</h2>
    <p class="muted small">Nhập mã bất kỳ trên HOSE, HNX, UPCoM để AI phân tích chuyên sâu: luận điểm đầu tư, kết quả kinh doanh, định giá, kỹ thuật, lịch sự kiện và bảng chấm điểm 8 tiêu chí.</p>
    <form id="lookup-form" class="lookup-row">
      <input id="lookup-input" placeholder="Mã cổ phiếu, ví dụ FPT" maxlength="10" autocomplete="off" autocapitalize="characters">
      <button type="submit" class="btn">Phân tích AI</button>
      <button type="button" id="lookup-add" class="btn-ghost">+ Theo dõi</button>
    </form>
    <p id="lookup-msg" class="small err-text"></p>
  </div>`;

  const cards = WATCH.map((sym) => {
    const s = DATA.stocks[sym];
    const a = DATA.analyses?.[sym];
    const deep = LATEST_DEEP[sym];
    const actions = `<div class="card-actions">
        <button class="btn-ghost small-btn" data-deep="${esc(sym)}">${deep ? "Xem phân tích chuyên sâu" : "Phân tích chuyên sâu"}</button>
        <button class="icon-btn" data-remove="${esc(sym)}" title="Gỡ khỏi danh sách" aria-label="Gỡ ${esc(sym)}">✕</button>
      </div>`;
    if (!s) {
      return `<article class="card">
        <div class="stock-head"><h2>${esc(sym)}</h2>${actions}</div>
        <p class="muted small">Giá và chỉ báo của mã này sẽ có sau lần cập nhật dữ liệu tới. Bạn vẫn có thể chạy phân tích chuyên sâu ngay.</p>
        ${deep ? `<p class="muted small">Phân tích gần nhất: ${timeVN(Date.parse(deep) / 1000)}</p>` : ""}
      </article>`;
    }
    const related = DATA.news.filter((n) => n.tickers?.includes(sym)).slice(0, 5);
    return `<article class="card">
      <div class="stock-head">
        <div><h2>${esc(sym)}</h2>${a ? `<span class="badge ${stanceClass(a.stance)}">${esc(a.stance)}</span> <span class="muted small">độ tin cậy: ${esc(a.confidence)}</span>` : ""}</div>
        <div class="price"><div class="big">${fmt(s.close)}</div>${pct(s.change_1d)}</div>
      </div>
      ${actions}
      ${deep ? `<p class="muted small">Phân tích chuyên sâu gần nhất: ${timeVN(Date.parse(deep) / 1000)}</p>` : ""}
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
        </details>` : ""}
      ${related.length ? `<div class="section-label">Tin liên quan</div>${related.map((n) => `<div class="small"><a href="${esc(n.link)}" target="_blank" rel="noopener">${esc(n.title)}</a></div>`).join("")}` : ""}
    </article>`;
  });

  const empty = `<div class="card"><p class="muted">Danh sách theo dõi đang trống. Nhập mã ở ô tra cứu phía trên rồi bấm "+ Theo dõi".</p></div>`;
  $("#watch").innerHTML = `<div class="stack">${lookup}${WATCH.length ? `<div class="grid grid-2">${cards.join("")}</div>` : empty}</div>`;

  $("#lookup-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const symbol = readSymbol();
    if (symbol) openDeep(symbol);
  });
  $("#lookup-add").addEventListener("click", () => {
    const symbol = readSymbol();
    if (symbol) addToWatch(symbol);
  });
  document.querySelectorAll("[data-remove]").forEach((b) => b.addEventListener("click", () => removeFromWatch(b.dataset.remove)));
  document.querySelectorAll("[data-deep]").forEach((b) => b.addEventListener("click", () => openDeep(b.dataset.deep)));
}

// ---------- Phân tích chuyên sâu (Edge Function "analyze") ----------
async function openDeep(symbol, refresh = false) {
  const dlg = $("#deep");
  const body = $("#deep-body");
  $("#deep-title").textContent = `Phân tích chuyên sâu · ${symbol}`;
  if (!dlg.open) dlg.showModal();

  if (!sb) {
    body.innerHTML = `<p class="notice">Phân tích chuyên sâu cần đăng nhập và Supabase. Chức năng này chạy trên trang web đã triển khai, không chạy ở chế độ thử trên máy.</p>`;
    return;
  }
  body.innerHTML = `<div class="loading"><div class="spinner"></div><p>AI đang thu thập dữ liệu và phân tích ${esc(symbol)}…<br><span class="muted small">Thường mất 30–90 giây.</span></p></div>`;

  const { data, error } = await sb.functions.invoke("analyze", { body: { symbol, refresh } });
  if (error) {
    let msg = error.message;
    try { msg = (await error.context.json()).error || msg; } catch {}
    body.innerHTML = `<p class="notice">${esc(msg)}</p>`;
    return;
  }
  LATEST_DEEP[symbol] = data.created_at;
  body.innerHTML = renderDeep(symbol, data);
  $("#deep-add")?.addEventListener("click", async () => {
    await addToWatch(symbol);
    $("#deep-add").replaceWith(Object.assign(document.createElement("span"), { className: "muted small", textContent: "Đã có trong danh sách theo dõi" }));
  });
  $("#deep-refresh")?.addEventListener("click", () => openDeep(symbol, true));
}

const scoreBar = (score) =>
  `<span class="score">${[1, 2, 3, 4, 5].map((i) => `<i class="${i <= score ? (score >= 4 ? "on-up" : score <= 2 ? "on-down" : "on-flat") : ""}"></i>`).join("")}</span>`;

const IMPACT_CLASS = { Cao: "b-down", "Trung bình": "b-flat", Thấp: "b-up" };

function renderDeep(symbol, data) {
  const r = data.result || {};
  const t = data.inputs?.technicals || {};
  const c = data.inputs?.fundamentals?.company || {};
  const ratios = data.inputs?.fundamentals?.chi_so_ttm_theo_quy || [];
  const lastRatio = ratios.at(-1) || {};
  const pctv = (x) => (x == null ? "–" : fmt(x * 100, 1) + "%");
  const avgScore = r.scorecard?.length ? r.scorecard.reduce((s, x) => s + x.score, 0) / r.scorecard.length : null;

  return `
    <div class="deep-head">
      <div>
        <div class="muted small">${esc(c.ten || "")}${c.nganh ? " · " + esc(c.nganh) : ""}</div>
        <div class="big">${fmt(t.close)} <span class="small">${pct(t.change_1d)}</span></div>
        <div class="kv">
          <div>P/E<b>${fmt(lastRatio.pe, 1)}</b></div><div>P/B<b>${fmt(lastRatio.pb, 2)}</b></div>
          <div>ROE<b>${pctv(lastRatio.roe)}</b></div><div>Vốn hóa<b>${c.von_hoa_ty_dong ? fmt(c.von_hoa_ty_dong, 0) + " tỷ" : "–"}</b></div>
          <div>1 năm<b>${pct(t.change_1y)}</b></div>
        </div>
      </div>
      <div class="deep-verdict">
        <span class="badge ${stanceClass(r.stance)}">${esc(r.stance)}</span>
        <span class="muted small">độ tin cậy ${esc(r.confidence)}</span>
        ${avgScore != null ? `<div class="big">${fmt(avgScore, 1)}<span class="muted small">/5</span></div>` : ""}
      </div>
    </div>
    <p class="headline">${esc(r.headline)}</p>
    <p>${esc(r.summary)}</p>

    <div class="section-label">Bảng chấm điểm</div>
    <table class="scorecard">${(r.scorecard || []).map((x) => `<tr><td class="l">${esc(x.dimension)}</td><td>${scoreBar(x.score)}</td><td class="l sig">${esc(x.reason)}</td></tr>`).join("")}</table>

    <div class="grid grid-2">
      <div>
        <div class="section-label">Luận điểm đầu tư</div>
        <p><b>${esc(r.thesis?.statement)}</b></p>
        ${list(r.thesis?.pillars)}
        <div class="section-label">Luận điểm sai nếu…</div>
        ${list(r.thesis?.invalidation)}
      </div>
      <div>
        <div class="section-label">Kết quả kinh doanh</div>
        <p>${esc(r.earnings?.summary)}</p>
        ${list(r.earnings?.highlights)}
      </div>
    </div>

    <div class="grid grid-2">
      <div><div class="section-label">Định giá</div><p>${esc(r.valuation)}</p></div>
      <div><div class="section-label">Vị thế cạnh tranh</div><p>${esc(r.competition)}</p></div>
    </div>

    <div class="section-label">Kỹ thuật</div>
    <p>${esc(r.technical?.summary)}</p>
    <p class="small"><b>Vùng giá:</b> ${esc(r.technical?.key_levels)}</p>

    <div class="section-label">Lịch sự kiện</div>
    <div class="table-wrap"><table>
      ${(r.catalysts || []).map((x) => `<tr><td class="l">${esc(x.timing)}</td><td class="l sig"><b>${esc(x.event)}</b><br><span class="muted">${esc(x.why)}</span></td><td><span class="badge ${IMPACT_CLASS[x.impact] || "b-flat"}">${esc(x.impact)}</span></td></tr>`).join("")}
    </table></div>

    <div class="section-label">Kịch bản</div>
    <div class="grid grid-3">
      <div class="scenario up-border"><b>Tích cực</b><p class="small">${esc(r.scenarios?.bull)}</p></div>
      <div class="scenario flat-border"><b>Cơ sở</b><p class="small">${esc(r.scenarios?.base)}</p></div>
      <div class="scenario down-border"><b>Tiêu cực</b><p class="small">${esc(r.scenarios?.bear)}</p></div>
    </div>

    <div class="grid grid-2">
      <div><div class="section-label">Rủi ro</div>${list(r.risks)}</div>
      <div><div class="section-label">Cần theo dõi</div>${list(r.watch_points)}</div>
    </div>
    ${r.data_gaps?.length ? `<div class="section-label">Hạn chế dữ liệu</div>${list(r.data_gaps)}` : ""}

    <div class="deep-foot">
      <span class="muted small">${data.cached ? "Kết quả đã lưu" : "Vừa phân tích"} lúc ${timeVN(Date.parse(data.created_at) / 1000)}${data.model ? " · " + esc(data.model) : ""}.
      Số liệu: DNSE, Vietcap IQ. AI có thể sai, đây không phải khuyến nghị đầu tư.</span>
      <span class="deep-buttons">
        ${data.cached ? `<button id="deep-refresh" class="btn-ghost small-btn">Phân tích lại</button>` : ""}
        ${WATCH.includes(symbol) ? "" : `<button id="deep-add" class="btn small-btn">+ Theo dõi</button>`}
      </span>
    </div>`;
}

const COLS = [
  ["symbol", "Mã"], ["close", "Giá"], ["change_1d", "1 ngày"], ["change_1w", "1 tuần"], ["change_1m", "1 tháng"],
  ["change_3m", "3 tháng"], ["rsi14", "RSI"], ["vol_ratio", "KL/TB20"], ["from_high_52w", "Từ đỉnh 52T"], ["tech_score", "Điểm KT"], ["signals", "Tín hiệu"],
];
let sortKey = "tech_score", sortDir = -1;

function renderScreen() {
  const rows = universeStocks().sort((a, b) => {
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

// Có cấu hình Supabase: dữ liệu nằm trong bucket riêng tư, chỉ thành viên đã đăng nhập đọc được.
// Không có: đọc thư mục data/ trên máy (chạy thử).
const CFG = window.APP_CONFIG || {};
const sb = CFG.supabaseUrl && window.supabase ? window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey) : null;

async function getJSON(path) {
  if (!sb) return (await fetch(`data/${path}?t=${Date.now()}`)).json();
  const { data, error } = await sb.storage.from("data").download(path);
  if (error) throw error;
  return JSON.parse(await data.text());
}

async function load(day) {
  DATA = await getJSON(day ? `history/${day}.json` : "latest.json");
  if (!WATCH_LOADED) {
    await loadWatchlist();
    WATCH_LOADED = true;
  }
  $("#updated").textContent = `Cập nhật: ${timeVN(DATA.generated_at)}${DATA.ai_enabled ? "" : " · chưa bật AI"}`;
  renderOverview();
  renderWatch();
  renderScreen();
  renderNews();
}

function setLocked(locked) {
  document.body.classList.toggle("locked", locked);
  $("#login").hidden = !locked;
  $("#tabs").hidden = locked;
  $("#logout").hidden = locked || !sb;
  $("#history").hidden = locked;
}

async function showApp() {
  setLocked(false);
  try {
    const days = await getJSON("history.json");
    $("#history").innerHTML = `<option value="">Mới nhất</option>` + days.map((d) => `<option value="${esc(d)}">${esc(d)}</option>`).join("");
  } catch {
    $("#history").hidden = true;
  }
  try {
    await load();
  } catch (err) {
    console.error(err);
    $("#updated").textContent = "Chưa có dữ liệu. Hãy chạy workflow \"Cập nhật dữ liệu\" trên GitHub Actions.";
  }
}

function showLogin() {
  setLocked(true);
  WATCH_LOADED = false;
  $("#updated").textContent = "Dành cho thành viên được mời";
}

async function sendLoginLink(e) {
  e.preventDefault();
  const msg = $("#login-msg");
  const btn = $("#login-form button");
  btn.disabled = true;
  msg.className = "small";
  msg.textContent = "Đang gửi…";
  const { error } = await sb.auth.signInWithOtp({
    email: $("#login-email").value.trim(),
    // Không tạo tài khoản mới: chỉ email đã được mời mới đăng nhập được
    options: { shouldCreateUser: false, emailRedirectTo: location.origin + location.pathname },
  });
  btn.disabled = false;
  if (error) {
    msg.className = "small err";
    msg.textContent = /signups not allowed|not found/i.test(error.message)
      ? "Email này chưa được mời. Hãy liên hệ quản trị viên."
      : `Không gửi được link: ${error.message}`;
  } else {
    msg.className = "small ok";
    msg.textContent = "Đã gửi! Hãy mở email và bấm vào link để đăng nhập.";
  }
}

async function init() {
  document.querySelectorAll(".tab").forEach((btn) =>
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab, .panel").forEach((el) => el.classList.remove("active"));
      btn.classList.add("active");
      $(`#${btn.dataset.tab}`).classList.add("active");
    }));
  ["#news-q", "#news-sent", "#news-imp"].forEach((sel) => $(sel).addEventListener("input", renderNews));
  $("#history").addEventListener("change", (e) => load(e.target.value));

  if (!sb) return showApp();

  $("#login-form").addEventListener("submit", sendLoginLink);
  $("#logout").addEventListener("click", () => sb.auth.signOut());
  let signedIn = false;
  sb.auth.onAuthStateChange((_event, session) => {
    if (session && !signedIn) {
      signedIn = true;
      showApp();
    } else if (!session) {
      signedIn = false;
      showLogin();
    }
  });
}

init();
