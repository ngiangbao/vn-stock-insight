"""Lấy giá lịch sử và tính chỉ báo kỹ thuật.

Nguồn chính là API biểu đồ công khai của DNSE, dự phòng là VNDirect.
Giá trả về theo đơn vị nghìn đồng (56.2 = 56.200đ).
"""

import time

import requests

HEADERS = {"User-Agent": "Mozilla/5.0 (vn-stock-insight)"}
SOURCES = {
    "dnse": "https://services.entrade.com.vn/chart-api/v2/ohlcs/{kind}"
    "?from={start}&to={end}&symbol={symbol}&resolution=1D",
    "vndirect": "https://dchart-api.vndirect.com.vn/dchart/history"
    "?resolution=D&symbol={symbol}&from={start}&to={end}",
}


def fetch_ohlc(symbol: str, days: int = 400, is_index: bool = False) -> list[dict]:
    end = int(time.time())
    start = end - days * 86400
    errors = []
    for name, template in SOURCES.items():
        url = template.format(
            kind="index" if is_index else "stock", start=start, end=end, symbol=symbol
        )
        try:
            resp = requests.get(url, headers=HEADERS, timeout=20)
            resp.raise_for_status()
            data = resp.json()
            bars = [
                {"t": t, "o": o, "h": h, "l": l, "c": c, "v": v}
                for t, o, h, l, c, v in zip(
                    data["t"], data["o"], data["h"], data["l"], data["c"], data["v"]
                )
            ]
            if bars:
                return bars
            errors.append(f"{name}: không có dữ liệu")
        except (requests.RequestException, ValueError, KeyError) as exc:
            errors.append(f"{name}: {exc}")
    raise RuntimeError(f"Không lấy được giá {symbol}: {'; '.join(errors)}")


def sma(values: list[float], n: int) -> float | None:
    return sum(values[-n:]) / n if len(values) >= n else None


def ema_series(values: list[float], n: int) -> list[float]:
    k = 2 / (n + 1)
    out = [values[0]]
    for v in values[1:]:
        out.append(v * k + out[-1] * (1 - k))
    return out


def rsi(closes: list[float], n: int = 14) -> float | None:
    if len(closes) <= n:
        return None
    gains, losses = [], []
    for prev, cur in zip(closes[:-1], closes[1:]):
        diff = cur - prev
        gains.append(max(diff, 0))
        losses.append(max(-diff, 0))
    avg_gain = sum(gains[:n]) / n
    avg_loss = sum(losses[:n]) / n
    for g, l in zip(gains[n:], losses[n:]):
        avg_gain = (avg_gain * (n - 1) + g) / n
        avg_loss = (avg_loss * (n - 1) + l) / n
    if avg_loss == 0:
        return 100.0
    return 100 - 100 / (1 + avg_gain / avg_loss)


def pct(a: float | None, b: float | None) -> float | None:
    if a is None or not b:
        return None
    return round((a / b - 1) * 100, 2)


def analyze(symbol: str, bars: list[dict]) -> dict:
    closes = [b["c"] for b in bars]
    vols = [b["v"] for b in bars]
    last = closes[-1]

    ma20, ma50, ma200 = sma(closes, 20), sma(closes, 50), sma(closes, 200)
    rsi14 = rsi(closes)
    macd_line = [a - b for a, b in zip(ema_series(closes, 12), ema_series(closes, 26))]
    signal = ema_series(macd_line, 9)
    macd_hist = macd_line[-1] - signal[-1]
    macd_hist_prev = macd_line[-2] - signal[-2] if len(closes) > 1 else macd_hist
    avg_vol20 = sma(vols[:-1], 20)
    vol_ratio = round(vols[-1] / avg_vol20, 2) if avg_vol20 else None
    window = bars[-250:]
    high_52w = max(b["h"] for b in window)
    low_52w = min(b["l"] for b in window)

    signals = []
    score = 0
    if ma20 and ma50:
        if last > ma20 > ma50:
            signals.append("Xu hướng tăng (giá > MA20 > MA50)")
            score += 2
        elif last < ma20 < ma50:
            signals.append("Xu hướng giảm (giá < MA20 < MA50)")
            score -= 2
    if ma200:
        score += 1 if last > ma200 else -1
    if rsi14 is not None:
        if rsi14 >= 70:
            signals.append(f"RSI quá mua ({rsi14:.0f})")
            score -= 1
        elif rsi14 <= 30:
            signals.append(f"RSI quá bán ({rsi14:.0f})")
            score += 1
    if macd_hist > 0 >= macd_hist_prev:
        signals.append("MACD cắt lên đường tín hiệu")
        score += 1
    elif macd_hist < 0 <= macd_hist_prev:
        signals.append("MACD cắt xuống đường tín hiệu")
        score -= 1
    if vol_ratio and vol_ratio >= 1.8:
        change_1d = pct(last, closes[-2]) or 0
        direction = "tăng" if change_1d >= 0 else "giảm"
        signals.append(f"Khối lượng đột biến x{vol_ratio} kèm giá {direction}")
        score += 1 if change_1d >= 0 else -1
    if last >= high_52w * 0.98:
        signals.append("Sát đỉnh 52 tuần")
    if last <= low_52w * 1.02:
        signals.append("Sát đáy 52 tuần")

    def back(n: int) -> float | None:
        return closes[-1 - n] if len(closes) > n else None

    return {
        "symbol": symbol,
        "date": time.strftime("%Y-%m-%d", time.gmtime(bars[-1]["t"] + 7 * 3600)),
        "close": last,
        "change_1d": pct(last, back(1)),
        "change_1w": pct(last, back(5)),
        "change_1m": pct(last, back(20)),
        "change_3m": pct(last, back(60)),
        "ma20": round(ma20, 2) if ma20 else None,
        "ma50": round(ma50, 2) if ma50 else None,
        "ma200": round(ma200, 2) if ma200 else None,
        "rsi14": round(rsi14, 1) if rsi14 is not None else None,
        "macd_hist": round(macd_hist, 3),
        "volume": vols[-1],
        "vol_ratio": vol_ratio,
        "high_52w": high_52w,
        "low_52w": low_52w,
        "from_high_52w": pct(last, high_52w),
        "signals": signals,
        "tech_score": score,
        "spark": closes[-60:],
    }
