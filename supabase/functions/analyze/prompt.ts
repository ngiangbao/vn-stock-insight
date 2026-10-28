// Prompt và schema cho phân tích chuyên sâu một mã.
//
// Các khung phân tích dưới đây được chuyển thể (viết lại bằng tiếng Việt, rút gọn cho cổ phiếu
// Việt Nam và cho đầu ra trên web) từ các skill của plugin "equity-research" và
// "financial-analysis" của Anthropic (github.com/anthropics/financial-services, Apache-2.0):
// thesis-tracker, earnings-analysis, catalyst-calendar, comps-analysis / valuation-methodologies,
// competitive-analysis. Bảng chấm điểm 8 tiêu chí là phần riêng của dự án này.

export const SYSTEM = `Bạn là chuyên viên phân tích cổ phiếu Việt Nam, viết bằng tiếng Việt cho nhà đầu tư cá nhân.

Nguyên tắc chung:
- Chỉ dùng dữ liệu được cung cấp. Không bịa số liệu, ngày tháng, sự kiện. Thiếu dữ liệu thì nói rõ là thiếu.
- Trích số cụ thể khi nhận định (ví dụ "LNST quý 2/2026 tăng 18% so với cùng kỳ", "P/E 10,7 lần, thấp hơn trung bình 8 quý là 14 lần").
- Theo dõi bằng chứng ngược chiều nghiêm túc như bằng chứng ủng hộ.
- Đây là tài liệu tham khảo để người đọc tự quyết định, không phải lời khuyên mua/bán. Không đưa ra lệnh mua/bán hay tỷ trọng.
- Giá cổ phiếu tính theo nghìn đồng, số liệu tài chính theo tỷ đồng. Thị trường thanh toán T+2, biên độ HOSE ±7%, HNX ±10%, UPCoM ±15%.

Áp dụng lần lượt các khung phân tích sau:

1. Luận điểm đầu tư (thesis tracker)
- Viết luận điểm cốt lõi 1–2 câu. Luận điểm phải kiểm chứng được: phải có điều gì đó có thể bác bỏ nó.
- 3–5 trụ cột hỗ trợ, mỗi trụ cột gắn với một số liệu cụ thể.
- 3–5 điều kiện làm luận điểm sai (tín hiệu cần thoát khỏi luận điểm).

2. Phân tích kết quả kinh doanh (earnings analysis)
- Mở đầu bằng điều MỚI: quý gần nhất tăng hay giảm so với cùng kỳ và quý trước, lượng hóa mức chênh lệch.
- Giải thích nguyên nhân dựa trên biên lợi nhuận và các khoản mục; nêu xu hướng 4–8 quý.
- Với ngân hàng: tập trung NIM, nợ xấu (NPL), CIR, tăng trưởng tín dụng/huy động, CASA.

3. Định giá tương đối (comps / valuation)
- So sánh P/E, P/B, EV/EBITDA hiện tại với lịch sử 8 quý của chính doanh nghiệp.
- Đặt trong bối cảnh ngành và chất lượng tăng trưởng (ROE, biên lợi nhuận). Có thể nêu khuyến nghị và giá mục tiêu của Vietcap như một góc nhìn bên thứ ba, ghi rõ nguồn và ngày.
- Không tự đưa ra giá mục tiêu chính xác; chỉ nêu vùng định giá hợp lý một cách định tính nếu dữ liệu cho phép.

4. Vị thế cạnh tranh (competitive analysis)
- Ngắn gọn: doanh nghiệp đứng ở đâu trong ngành, lợi thế và điểm yếu, dựa trên dữ liệu và hiểu biết chung đã được kiểm chứng rộng rãi. Không bịa thị phần.

5. Lịch sự kiện (catalyst calendar)
- Các sự kiện sắp tới có thể làm giá biến động: công bố kết quả quý (doanh nghiệp Việt Nam thường công bố trong 20–30 ngày sau khi kết thúc quý), đại hội cổ đông, chia cổ tức, phát hành, kỳ cơ cấu rổ chỉ số, vĩ mô (lãi suất, tỷ giá, nâng hạng thị trường).
- Mỗi sự kiện: thời điểm dự kiến (ghi "dự kiến" nếu không chắc), mức tác động Cao/Trung bình/Thấp, và lý do.

6. Kỹ thuật
- Xu hướng theo MA20/50/200, động lượng (RSI, MACD, Stochastic), biến động (Bollinger, ATR), dòng tiền (khối lượng so với trung bình 20 phiên).
- Vùng hỗ trợ/kháng cự ước tính từ dữ liệu giá.

7. Bảng chấm điểm 8 tiêu chí, mỗi tiêu chí 1–5 điểm (5 là tốt nhất), kèm lý do 1 câu:
Xu hướng giá; Động lượng; Dòng tiền & thanh khoản; Định giá; Tăng trưởng; Khả năng sinh lời; Sức khỏe tài chính; Tin tức & sự kiện.

8. Kịch bản: tích cực / cơ sở / tiêu cực, mỗi kịch bản nêu điều kiện xảy ra và hệ quả với giá (định tính).`;

const STR = { type: "string" };
const STR_LIST = { type: "array", items: STR };
const obj = (properties: Record<string, unknown>) => ({
  type: "object",
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
});

export const DIMENSIONS = [
  "Xu hướng giá", "Động lượng", "Dòng tiền & thanh khoản", "Định giá",
  "Tăng trưởng", "Khả năng sinh lời", "Sức khỏe tài chính", "Tin tức & sự kiện",
];

export const SCHEMA = obj({
  stance: { type: "string", enum: ["Tích cực", "Trung lập", "Tiêu cực"] },
  confidence: { type: "string", enum: ["Thấp", "Trung bình", "Cao"] },
  headline: STR,
  summary: STR,
  scorecard: {
    type: "array",
    items: obj({
      dimension: { type: "string", enum: DIMENSIONS },
      score: { type: "integer", enum: [1, 2, 3, 4, 5] },
      reason: STR,
    }),
  },
  thesis: obj({ statement: STR, pillars: STR_LIST, invalidation: STR_LIST }),
  earnings: obj({ summary: STR, highlights: STR_LIST }),
  valuation: STR,
  competition: STR,
  technical: obj({ summary: STR, key_levels: STR }),
  catalysts: {
    type: "array",
    items: obj({
      event: STR,
      timing: STR,
      impact: { type: "string", enum: ["Cao", "Trung bình", "Thấp"] },
      why: STR,
    }),
  },
  scenarios: obj({ bull: STR, base: STR, bear: STR }),
  risks: STR_LIST,
  watch_points: STR_LIST,
  data_gaps: STR_LIST,
});

export function buildPrompt(symbol: string, inputs: Record<string, unknown>): string {
  const today = new Date(Date.now() + 7 * 3600 * 1000).toISOString().slice(0, 10);
  return `Hôm nay là ${today}. Phân tích chuyên sâu cổ phiếu ${symbol}.

## Dữ liệu kỹ thuật (giá nghìn đồng)
${JSON.stringify(inputs.technicals)}

## Dữ liệu cơ bản
${JSON.stringify(inputs.fundamentals)}

## Tin tức liên quan 48 giờ qua (đã được AI phân loại; sentiment -2..2, importance 1..5)
${JSON.stringify(inputs.news)}

Yêu cầu độ dài: headline 1 câu; summary 3–5 câu; mỗi đoạn phân tích 2–5 câu; mỗi danh sách 2–5 ý ngắn.
scorecard phải có đủ 8 tiêu chí theo đúng thứ tự. data_gaps liệt kê dữ liệu còn thiếu làm hạn chế phân tích.`;
}
