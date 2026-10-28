// Prompt và schema cho phân tích chuyên sâu một mã và nhận định thị trường.
//
// Các khung phân tích được chuyển thể (viết lại bằng tiếng Việt, rút gọn cho cổ phiếu Việt Nam)
// từ các skill của plugin "equity-research" và "financial-analysis" của Anthropic
// (github.com/anthropics/financial-services, Apache-2.0): thesis-tracker, earnings-analysis,
// catalyst-calendar, comps-analysis / valuation-methodologies, competitive-analysis.
// Bảng chấm điểm 8 tiêu chí là phần riêng của dự án này.

import 'dart:convert';

const _common = '''Bạn là chuyên viên phân tích cổ phiếu Việt Nam, viết bằng tiếng Việt cho nhà đầu tư cá nhân.

Nguyên tắc chung:
- Chỉ dùng dữ liệu được cung cấp. Không bịa số liệu, ngày tháng, sự kiện. Thiếu dữ liệu thì nói rõ là thiếu.
- Trích số cụ thể khi nhận định (ví dụ "LNST quý 2/2026 tăng 18% so với cùng kỳ", "P/E 10,7 lần, thấp hơn trung bình 8 quý là 14 lần").
- Theo dõi bằng chứng ngược chiều nghiêm túc như bằng chứng ủng hộ.
- Đây là tài liệu tham khảo để người đọc tự quyết định, không phải lời khuyên mua/bán. Không đưa ra lệnh mua/bán hay tỷ trọng.
- Giá cổ phiếu tính theo nghìn đồng, số liệu tài chính theo tỷ đồng. Thị trường thanh toán T+2, biên độ HOSE ±7%, HNX ±10%, UPCoM ±15%.''';

const stockSystem = '''$_common

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

8. Kịch bản: tích cực / cơ sở / tiêu cực, mỗi kịch bản nêu điều kiện xảy ra và hệ quả với giá (định tính).''';

const marketSystem = _common;

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, dynamic> _obj(Map<String, dynamic> properties) => {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
      'additionalProperties': false,
    };

const stances = ['Tích cực', 'Trung lập', 'Tiêu cực'];

const dimensions = [
  'Xu hướng giá', 'Động lượng', 'Dòng tiền & thanh khoản', 'Định giá', //
  'Tăng trưởng', 'Khả năng sinh lời', 'Sức khỏe tài chính', 'Tin tức & sự kiện',
];

final stockSchema = _obj({
  'stance': {'type': 'string', 'enum': stances},
  'confidence': {
    'type': 'string',
    'enum': ['Thấp', 'Trung bình', 'Cao'],
  },
  'headline': _str,
  'summary': _str,
  'scorecard': {
    'type': 'array',
    'items': _obj({
      'dimension': {'type': 'string', 'enum': dimensions},
      'score': {
        'type': 'integer',
        'enum': [1, 2, 3, 4, 5],
      },
      'reason': _str,
    }),
  },
  'thesis': _obj({'statement': _str, 'pillars': _strList, 'invalidation': _strList}),
  'earnings': _obj({'summary': _str, 'highlights': _strList}),
  'valuation': _str,
  'competition': _str,
  'technical': _obj({'summary': _str, 'key_levels': _str}),
  'catalysts': {
    'type': 'array',
    'items': _obj({
      'event': _str,
      'timing': _str,
      'impact': {
        'type': 'string',
        'enum': ['Cao', 'Trung bình', 'Thấp'],
      },
      'why': _str,
    }),
  },
  'scenarios': _obj({'bull': _str, 'base': _str, 'bear': _str}),
  'risks': _strList,
  'watch_points': _strList,
  'data_gaps': _strList,
});

final marketSchema = _obj({
  'mood': {'type': 'string', 'enum': stances},
  'headline': _str,
  'summary': _str,
  'themes': {
    'type': 'array',
    'items': _obj({'theme': _str, 'detail': _str, 'tickers': _strList}),
  },
  'watch_list': _strList,
});

String _today() => DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);

String stockPrompt(String symbol, Map<String, dynamic> inputs) => '''Hôm nay là ${_today()}. Phân tích chuyên sâu cổ phiếu $symbol.

## Dữ liệu kỹ thuật (giá nghìn đồng)
${jsonEncode(inputs['technicals'])}

## Dữ liệu cơ bản
${jsonEncode(inputs['fundamentals'])}

## Tin tức liên quan 48 giờ qua
${jsonEncode(inputs['news'])}

Yêu cầu độ dài: headline 1 câu; summary 3–5 câu; mỗi đoạn phân tích 2–5 câu; mỗi danh sách 2–5 ý ngắn.
scorecard phải có đủ 8 tiêu chí theo đúng thứ tự. data_gaps liệt kê dữ liệu còn thiếu làm hạn chế phân tích.''';

String marketPrompt(Map<String, dynamic> index, String movers, List<Map<String, dynamic>> news) =>
    '''Hôm nay là ${_today()}. Viết nhận định thị trường chứng khoán Việt Nam.

## VN-Index
${jsonEncode(index)}

## Biến động rổ VN30
$movers

## Tin mới nhất 48 giờ qua
${jsonEncode(news)}

Yêu cầu: headline 1 câu; summary 1 đoạn 4–6 câu; themes gồm 3–5 chủ đề nổi bật kèm mã liên quan;
watch_list gồm 3–5 điều nhà đầu tư nên theo dõi trong phiên tới.''';
