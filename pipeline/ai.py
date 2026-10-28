"""Gọi Claude để phân loại tin tức và phân tích cổ phiếu.

- Tin tức: model rẻ (Haiku), xử lý theo lô.
- Phân tích từng mã và nhận định thị trường: model mạnh (Opus).
Mọi kết quả đều là JSON theo schema cố định (structured outputs).
"""

import json

import anthropic

client = anthropic.Anthropic()

# Opus hỗ trợ fallback phía server: nếu bộ lọc an toàn từ chối nhầm,
# API tự chạy lại yêu cầu trên model dự phòng thay vì trả về lỗi.
FALLBACK_MODELS = ("claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1")

ANALYST_SYSTEM = (
    "Bạn là chuyên viên phân tích chứng khoán Việt Nam, viết bằng tiếng Việt. "
    "Phân tích khách quan, dựa trên dữ liệu được cung cấp, nêu rõ cả mặt tích cực lẫn rủi ro. "
    "Không bịa số liệu không có trong dữ liệu. Nếu dữ liệu chưa đủ để kết luận, hãy nói rõ. "
    "Đây là tài liệu tham khảo cho nhà đầu tư cá nhân tự ra quyết định, không phải lời khuyên mua bán. "
    "Giá tính theo nghìn đồng. Thị trường thanh toán T+2, biên độ HOSE ±7%."
)


def _call(model: str, system: str, prompt: str, schema: dict, effort: str, max_tokens: int = 16000):
    kwargs = {}
    if model in FALLBACK_MODELS:
        kwargs = {"betas": ["server-side-fallback-2026-07-01"], "fallbacks": "default"}
    response = client.beta.messages.create(
        model=model,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": prompt}],
        output_config={"effort": effort, "format": {"type": "json_schema", "schema": schema}},
        **kwargs,
    )
    if response.stop_reason == "refusal":
        print(f"[ai] {model} từ chối yêu cầu: {response.stop_details}")
        return None
    if response.stop_reason == "max_tokens":
        print(f"[ai] {model} bị cắt do max_tokens")
        return None
    text = next((b.text for b in response.content if b.type == "text"), None)
    return json.loads(text) if text else None


def _obj(properties: dict) -> dict:
    return {
        "type": "object",
        "properties": properties,
        "required": list(properties),
        "additionalProperties": False,
    }


STR = {"type": "string"}
STR_LIST = {"type": "array", "items": STR}

NEWS_SCHEMA = _obj({
    "items": {
        "type": "array",
        "items": _obj({
            "id": STR,
            "tickers": STR_LIST,
            "sentiment": {"type": "integer", "enum": [-2, -1, 0, 1, 2]},
            "importance": {"type": "integer", "enum": [1, 2, 3, 4, 5]},
            "category": {
                "type": "string",
                "enum": [
                    "Kết quả kinh doanh", "Cổ tức/Phát hành", "Giao dịch nội bộ/Khối ngoại",
                    "Vĩ mô/Chính sách", "Nhận định thị trường", "Dự án/Hợp đồng",
                    "Pháp lý/Xử phạt", "Khác",
                ],
            },
            "summary": STR,
        }),
    },
})

STOCK_SCHEMA = _obj({
    "stance": {"type": "string", "enum": ["Tích cực", "Trung lập", "Tiêu cực"]},
    "confidence": {"type": "string", "enum": ["Thấp", "Trung bình", "Cao"]},
    "headline": STR,
    "technical_view": STR,
    "news_view": STR,
    "key_levels": STR,
    "catalysts": STR_LIST,
    "risks": STR_LIST,
    "watch_points": STR_LIST,
})

MARKET_SCHEMA = _obj({
    "mood": {"type": "string", "enum": ["Tích cực", "Trung lập", "Tiêu cực"]},
    "headline": STR,
    "summary": STR,
    "themes": {
        "type": "array",
        "items": _obj({"theme": STR, "detail": STR, "tickers": STR_LIST}),
    },
    "watch_list": STR_LIST,
})


def triage_news(items: list[dict], model: str, batch_size: int = 40) -> dict[str, dict]:
    """Trả về {id tin: {tickers, sentiment, importance, category, summary}}."""
    results: dict[str, dict] = {}
    system = (
        "Bạn phân loại tin tức tài chính Việt Nam cho nhà đầu tư chứng khoán. Với mỗi tin: "
        "tickers = các mã cổ phiếu niêm yết tại Việt Nam liên quan trực tiếp (3 chữ cái in hoa; "
        "để trống nếu không có); sentiment từ -2 (rất tiêu cực) đến 2 (rất tích cực) với cổ phiếu "
        "hoặc thị trường; importance từ 1 (không đáng kể) đến 5 (ảnh hưởng lớn đến giá); "
        "summary là 1 câu tiếng Việt ngắn gọn nêu ý chính và tác động. Giữ nguyên id."
    )
    for i in range(0, len(items), batch_size):
        batch = items[i : i + batch_size]
        prompt = "\n\n".join(
            f"id: {n['id']}\nNguồn: {n['source']}\nTiêu đề: {n['title']}\nMô tả: {n['summary']}"
            for n in batch
        )
        try:
            data = _call(model, system, prompt, NEWS_SCHEMA, effort="low")
        except anthropic.APIError as exc:
            print(f"[ai] Lỗi phân loại tin (lô {i // batch_size + 1}): {exc}")
            continue
        for row in (data or {}).get("items", []):
            results[row["id"]] = row
        print(f"[ai] Đã phân loại {len(results)}/{len(items)} tin")
    return results


def _fmt_tech(t: dict) -> str:
    keys = [
        "date", "close", "change_1d", "change_1w", "change_1m", "change_3m", "ma20", "ma50",
        "ma200", "rsi14", "macd_hist", "volume", "vol_ratio", "high_52w", "low_52w",
        "from_high_52w", "signals", "tech_score",
    ]
    return json.dumps({k: t.get(k) for k in keys}, ensure_ascii=False)


def _fmt_news(news: list[dict]) -> str:
    if not news:
        return "(không có tin liên quan trong 48 giờ qua)"
    return "\n".join(
        f"- [{n.get('category', '')}] (cảm xúc {n.get('sentiment', 0):+d}, mức độ "
        f"{n.get('importance', 1)}/5) {n['title']} — {n.get('ai_summary') or n['summary']}"
        for n in news
    )


def analyze_stock(tech: dict, news: list[dict], model: str, effort: str) -> dict | None:
    closes = ", ".join(str(c) for c in tech["spark"][-30:])
    prompt = (
        f"Phân tích cổ phiếu {tech['symbol']}.\n\n"
        f"## Chỉ báo kỹ thuật (phiên gần nhất)\n{_fmt_tech(tech)}\n\n"
        f"## Giá đóng cửa 30 phiên gần nhất (cũ → mới)\n{closes}\n\n"
        f"## Tin tức liên quan\n{_fmt_news(news)}\n\n"
        "Yêu cầu: headline là 1 câu kết luận; technical_view và news_view mỗi phần 2–4 câu; "
        "key_levels nêu vùng hỗ trợ/kháng cự ước tính từ dữ liệu; catalysts, risks, "
        "watch_points mỗi mục 2–4 ý ngắn."
    )
    try:
        return _call(model, ANALYST_SYSTEM, prompt, STOCK_SCHEMA, effort)
    except anthropic.APIError as exc:
        print(f"[ai] Lỗi phân tích {tech['symbol']}: {exc}")
        return None


def market_brief(index_tech: dict, news: list[dict], movers: str, model: str, effort: str) -> dict | None:
    prompt = (
        f"Viết nhận định thị trường chứng khoán Việt Nam hôm nay.\n\n"
        f"## VN-Index\n{_fmt_tech(index_tech)}\n\n"
        f"## Biến động rổ theo dõi\n{movers}\n\n"
        f"## Tin quan trọng nhất 48 giờ qua\n{_fmt_news(news)}\n\n"
        "Yêu cầu: headline 1 câu; summary 1 đoạn 4–6 câu; themes gồm 3–5 chủ đề nổi bật kèm "
        "mã liên quan; watch_list gồm 3–5 điều nhà đầu tư nên theo dõi trong phiên tới."
    )
    try:
        return _call(model, ANALYST_SYSTEM, prompt, MARKET_SCHEMA, effort)
    except anthropic.APIError as exc:
        print(f"[ai] Lỗi nhận định thị trường: {exc}")
        return None
