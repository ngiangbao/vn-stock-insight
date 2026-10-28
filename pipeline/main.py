"""Chạy toàn bộ quy trình: giá → chỉ báo → tin tức → AI → ghi JSON cho trang web.

Chạy: python -m pipeline.main [--no-ai]
"""

import argparse
import os
import time
from pathlib import Path

import yaml

from pipeline import market, news, storage

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "site" / "data"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-ai", action="store_true", help="Bỏ qua bước gọi Claude")
    args = parser.parse_args()

    config = yaml.safe_load((ROOT / "config.yml").read_text(encoding="utf-8"))
    use_ai = not args.no_ai and bool(os.environ.get("ANTHROPIC_API_KEY"))
    if not use_ai:
        print("[main] Chạy không có AI (thiếu ANTHROPIC_API_KEY hoặc có --no-ai)")
    ai_cfg = config["ai"]

    # 1. Giá và chỉ báo kỹ thuật
    members = storage.member_symbols()
    symbols = sorted(set(config["universe"]) | set(config["watchlist"]) | members)
    stocks: dict[str, dict] = {}
    for symbol in symbols:
        try:
            stocks[symbol] = market.analyze(symbol, market.fetch_ohlc(symbol))
        except RuntimeError as exc:
            print(f"[market] {exc}")
        time.sleep(0.2)
    print(f"[market] Đã có dữ liệu {len(stocks)}/{len(symbols)} mã")
    index = market.analyze("VNINDEX", market.fetch_ohlc("VNINDEX", is_index=True))

    # 2. Tin tức
    items = news.fetch_news(config["news_feeds"], config["news_max_age_hours"])

    # 3. AI
    brief = None
    analyses: dict[str, dict] = {}
    if use_ai:
        from pipeline import ai

        tags = ai.triage_news(items, ai_cfg["news_model"])
        for n in items:
            tag = tags.get(n["id"], {})
            n["tickers"] = sorted(set(tag.get("tickers", [])))
            n["sentiment"] = tag.get("sentiment", 0)
            n["importance"] = tag.get("importance", 1)
            n["category"] = tag.get("category", "Khác")
            n["ai_summary"] = tag.get("summary", "")

        for symbol in config["watchlist"]:
            if symbol not in stocks:
                continue
            related = [n for n in items if symbol in n.get("tickers", [])][:15]
            print(f"[ai] Phân tích {symbol} ({len(related)} tin liên quan)")
            result = ai.analyze_stock(
                stocks[symbol], related, ai_cfg["analysis_model"], ai_cfg["analysis_effort"]
            )
            if result:
                analyses[symbol] = result

        top_news = sorted(items, key=lambda n: n.get("importance", 1), reverse=True)[:25]
        movers = "\n".join(
            f"{s['symbol']}: {s['close']} ({s['change_1d']:+.2f}% hôm nay, "
            f"{s['change_1m']:+.2f}% 1 tháng), tín hiệu: {', '.join(s['signals']) or 'không'}"
            for s in stocks.values()
            if s["change_1d"] is not None and s["change_1m"] is not None
        )
        print("[ai] Viết nhận định thị trường")
        brief = ai.market_brief(
            index, top_news, movers, ai_cfg["analysis_model"], ai_cfg["analysis_effort"]
        )

    # 4. Ghi kết quả
    output = {
        "generated_at": int(time.time()),
        "ai_enabled": use_ai,
        "models": ai_cfg if use_ai else None,
        "watchlist": config["watchlist"],
        "universe": config["universe"],
        "index": index,
        "brief": brief,
        "stocks": stocks,
        "analyses": analyses,
        "news": items,
    }
    # Lưu thêm bản theo ngày để xem lại lịch sử nhận định
    day = time.strftime("%Y-%m-%d", time.gmtime(time.time() + 7 * 3600))
    storage.save(output, day, DATA_DIR)


if __name__ == "__main__":
    main()
