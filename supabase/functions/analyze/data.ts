// Thu thập dữ liệu cho một mã: giá + chỉ báo kỹ thuật (DNSE), số liệu tài chính (Vietcap IQ).
// Giá DNSE tính theo nghìn đồng; số liệu Vietcap tính theo đồng.

const HEADERS = { "User-Agent": "Mozilla/5.0 (vn-stock-insight)" };

type Bar = { t: number; o: number; h: number; l: number; c: number; v: number };

async function getJSON(url: string): Promise<any> {
  const resp = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(20_000) });
  if (!resp.ok) throw new Error(`${resp.status} ${url}`);
  return resp.json();
}

export async function fetchBars(symbol: string, days = 400): Promise<Bar[]> {
  const end = Math.floor(Date.now() / 1000);
  const start = end - days * 86400;
  const urls = [
    `https://services.entrade.com.vn/chart-api/v2/ohlcs/stock?from=${start}&to=${end}&symbol=${symbol}&resolution=1D`,
    `https://dchart-api.vndirect.com.vn/dchart/history?resolution=D&symbol=${symbol}&from=${start}&to=${end}`,
  ];
  for (const url of urls) {
    try {
      const d = await getJSON(url);
      const bars = (d.t ?? []).map((t: number, i: number) => ({
        t, o: d.o[i], h: d.h[i], l: d.l[i], c: d.c[i], v: d.v[i],
      }));
      if (bars.length) return bars;
    } catch (err) {
      console.warn(`Không lấy được giá từ ${url}: ${err}`);
    }
  }
  return [];
}

const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
const sma = (xs: number[], n: number) => (xs.length >= n ? avg(xs.slice(-n)) : null);
const round = (x: number | null, d = 2) => (x == null || !isFinite(x) ? null : Math.round(x * 10 ** d) / 10 ** d);
const pct = (a: number | null, b: number | null) => (a == null || !b ? null : round((a / b - 1) * 100));

function emaSeries(xs: number[], n: number): number[] {
  const k = 2 / (n + 1);
  const out = [xs[0]];
  for (const x of xs.slice(1)) out.push(x * k + out[out.length - 1] * (1 - k));
  return out;
}

function rsi(closes: number[], n = 14): number | null {
  if (closes.length <= n) return null;
  let gain = 0, loss = 0;
  for (let i = 1; i <= n; i++) {
    const d = closes[i] - closes[i - 1];
    gain += Math.max(d, 0);
    loss += Math.max(-d, 0);
  }
  gain /= n;
  loss /= n;
  for (let i = n + 1; i < closes.length; i++) {
    const d = closes[i] - closes[i - 1];
    gain = (gain * (n - 1) + Math.max(d, 0)) / n;
    loss = (loss * (n - 1) + Math.max(-d, 0)) / n;
  }
  return loss === 0 ? 100 : 100 - 100 / (1 + gain / loss);
}

function atr(bars: Bar[], n = 14): number | null {
  if (bars.length <= n) return null;
  const trs = bars.slice(1).map((b, i) =>
    Math.max(b.h - b.l, Math.abs(b.h - bars[i].c), Math.abs(b.l - bars[i].c))
  );
  return avg(trs.slice(-n));
}

export function technicals(bars: Bar[]) {
  const closes = bars.map((b) => b.c);
  const vols = bars.map((b) => b.v);
  const last = closes[closes.length - 1];
  const back = (n: number) => (closes.length > n ? closes[closes.length - 1 - n] : null);

  const ema26 = emaSeries(closes, 26);
  const macd = emaSeries(closes, 12).map((x, i) => x - ema26[i]);
  const signal = emaSeries(macd, 9);
  const ma20 = sma(closes, 20);
  const std20 = ma20 == null ? null : Math.sqrt(avg(closes.slice(-20).map((c) => (c - ma20) ** 2)));
  const recent = bars.slice(-14);
  const hh = Math.max(...recent.map((b) => b.h));
  const ll = Math.min(...recent.map((b) => b.l));
  const year = bars.slice(-250);
  const avgVol20 = sma(vols.slice(0, -1), 20);
  const atr14 = atr(bars);

  return {
    date: new Date((bars[bars.length - 1].t + 7 * 3600) * 1000).toISOString().slice(0, 10),
    close: last,
    change_1d: pct(last, back(1)),
    change_1w: pct(last, back(5)),
    change_1m: pct(last, back(20)),
    change_3m: pct(last, back(60)),
    change_1y: pct(last, back(250)),
    ma20: round(ma20),
    ma50: round(sma(closes, 50)),
    ma200: round(sma(closes, 200)),
    rsi14: round(rsi(closes), 1),
    macd: round(macd[macd.length - 1], 3),
    macd_signal: round(signal[signal.length - 1], 3),
    bollinger_upper: round(ma20 != null && std20 != null ? ma20 + 2 * std20 : null),
    bollinger_lower: round(ma20 != null && std20 != null ? ma20 - 2 * std20 : null),
    stochastic_k: round(hh === ll ? 50 : ((last - ll) / (hh - ll)) * 100, 1),
    atr14_pct: round(atr14 == null ? null : (atr14 / last) * 100),
    volume: vols[vols.length - 1],
    avg_volume_20: avgVol20 == null ? null : Math.round(avgVol20),
    vol_ratio: round(avgVol20 ? vols[vols.length - 1] / avgVol20 : null),
    high_52w: Math.max(...year.map((b) => b.h)),
    low_52w: Math.min(...year.map((b) => b.l)),
    closes_60d: closes.slice(-60),
  };
}

const IQ = "https://iq.vietcap.com.vn/api/iq-insight-service/v1/company";
const QUARTER = (r: any) => `Q${r.quarter ?? r.lengthReport}/${r.yearReport ?? r.year}`;

// Mã khoản mục báo cáo kết quả kinh doanh (doanh nghiệp phi tài chính, chuẩn VAS) của Vietcap
const INCOME_ITEMS: Record<string, string> = {
  isa3: "doanh_thu_thuan",
  isa5: "loi_nhuan_gop",
  isa11: "loi_nhuan_hoat_dong",
  isa16: "loi_nhuan_truoc_thue",
  isa22: "loi_nhuan_sau_thue_cong_ty_me",
};

const RATIO_ITEMS = [
  "pe", "pb", "ps", "evToEbitda", "dividendYield", "roe", "roa", "roic", "grossMargin",
  "ebitMargin", "afterTaxProfitMargin", "debtToEquity", "currentRatio", "cashCycle",
  // Chỉ số riêng cho ngân hàng
  "netInterestMargin", "npl", "cir", "ldrLoanDepositRatio", "loansGrowth", "depositGrowth", "casaRatio",
];

export async function fundamentals(symbol: string) {
  const out: Record<string, unknown> = {};
  try {
    const c = (await getJSON(`${IQ}/${symbol}`)).data ?? {};
    out.company = {
      ten: c.viOrganName,
      nganh: c.sectorVn,
      la_ngan_hang: Boolean(c.isBank),
      von_hoa_ty_dong: c.marketCap ? Math.round(c.marketCap / 1e9) : null,
      so_huu_nuoc_ngoai: c.foreignerPercentage,
      room_nuoc_ngoai_toi_da: c.maximumForeignPercentage,
      so_huu_nha_nuoc: c.statePercentage,
      gia_tri_khop_tb_1_thang_ty_dong: c.averageMatchValue1Month ? Math.round(c.averageMatchValue1Month / 1e9) : null,
      // Khuyến nghị của bộ phận phân tích Vietcap (nguồn bên thứ ba, chỉ để tham chiếu)
      vietcap_khuyen_nghi: c.rating ?? null,
      vietcap_gia_muc_tieu: c.targetPrice ?? null,
      vietcap_ngay_khuyen_nghi: c.ratingAsOf ?? null,
    };
  } catch (err) {
    console.warn(`Không lấy được hồ sơ ${symbol}: ${err}`);
  }

  try {
    const rows = ((await getJSON(`${IQ}/${symbol}/statistics-financial`)).data ?? [])
      .filter((r: any) => r.quarter >= 1 && r.quarter <= 4)
      .sort((a: any, b: any) => a.yearReport - b.yearReport || a.quarter - b.quarter)
      .slice(-8);
    out.chi_so_ttm_theo_quy = rows.map((r: any) => {
      const row: Record<string, unknown> = { ky: QUARTER(r) };
      for (const k of RATIO_ITEMS) if (r[k]) row[k] = round(r[k], 4);
      return row;
    });
  } catch (err) {
    console.warn(`Không lấy được chỉ số tài chính ${symbol}: ${err}`);
  }

  if (!(out.company as any)?.la_ngan_hang) {
    try {
      const data = (await getJSON(`${IQ}/${symbol}/financial-statement?section=INCOME_STATEMENT`)).data ?? {};
      const quarters = (data.quarters ?? [])
        .filter((r: any) => r.lengthReport >= 1 && r.lengthReport <= 4)
        .sort((a: any, b: any) => a.yearReport - b.yearReport || a.lengthReport - b.lengthReport)
        .slice(-8);
      out.ket_qua_kinh_doanh_theo_quy_ty_dong = quarters.map((r: any) => {
        const row: Record<string, unknown> = { ky: QUARTER(r), ngay_cong_bo: r.publicDate?.slice(0, 10) };
        for (const [code, name] of Object.entries(INCOME_ITEMS)) {
          if (r[code] != null) row[name] = Math.round(r[code] / 1e9);
        }
        return row;
      });
    } catch (err) {
      console.warn(`Không lấy được báo cáo kết quả kinh doanh ${symbol}: ${err}`);
    }
  }
  return out;
}
