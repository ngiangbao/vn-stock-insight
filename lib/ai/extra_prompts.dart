// Các phân tích bổ sung theo chủ đề cho báo cáo AI một cổ phiếu: chuyển động ngành, cổ phiếu cùng ngành, dòng tiền,
// vĩ mô, tin tức và sự kiện, kịch bản xấu. Mỗi chủ đề dùng dữ liệu bổ sung riêng (tính trên máy) và chung một schema kết quả.

import 'dart:convert';

import 'prompts.dart';

class ExtraKind {
  final String id, title, button, instruction;
  const ExtraKind(this.id, this.title, this.button, this.instruction);
}

const extraKinds = <ExtraKind>[
  ExtraKind(
    'sector',
    'Chuyển động ngành',
    'Phân tích chuyển động ngành',
    'Đánh giá ngành của cổ phiếu đang chuyển động ra sao: hiệu suất 1 tuần/1 tháng/3 tháng/6 tháng/từ đầu năm so với VN-Index, độ rộng '
        '(tỷ lệ mã tăng), dòng tiền và khối ngoại hôm nay của cả ngành, mã dẫn dắt và mã yếu. Rồi đặt cổ phiếu vào bức tranh đó: mạnh hay yếu '
        'hơn ngành, ngành đang được hay bị rút tiền, điều đó ủng hộ hay làm yếu luận điểm của báo cáo thứ nhất.',
  ),
  ExtraKind(
    'peers',
    'Cổ phiếu cùng ngành',
    'Phân tích các cổ phiếu cùng ngành',
    'So sánh cổ phiếu với các doanh nghiệp lớn cùng ngành theo P/E, P/B, ROE, biên lợi nhuận, đòn bẩy, hiệu suất giá. Xếp hạng vị trí của '
        'cổ phiếu trong nhóm, chỉ ra điểm hơn/kém, định giá đắt hay rẻ tương đối có lý do hay không, và mã nào trong nhóm đáng so sánh nhất.',
  ),
  ExtraKind(
    'flow',
    'Dòng tiền và thanh khoản',
    'Phân tích dòng tiền',
    'Phân tích dòng tiền và thanh khoản: khối lượng so với trung bình, giá trị giao dịch, khối ngoại mua/bán ròng, thanh khoản trong phiên '
        'hôm nay so với phiên trước, mức độ dễ vào/ra lệnh. Dòng tiền xác nhận hay phủ nhận xu hướng giá.',
  ),
  ExtraKind(
    'macro',
    'Tác động vĩ mô',
    'Phân tích tác động vĩ mô',
    'Dùng số liệu vĩ mô được cung cấp (tăng trưởng, lạm phát, tỷ giá, cán cân, nợ công...) để suy ra tác động tới ngành và cổ phiếu: kênh '
        'truyền dẫn (lãi suất, tỷ giá, nhu cầu, chi phí đầu vào), mức nhạy cảm, và chỉ tiêu vĩ mô cần theo dõi nhất với cổ phiếu này.',
  ),
  ExtraKind(
    'news',
    'Tin tức và sự kiện',
    'Phân tích tin tức, sự kiện',
    'Tổng hợp tin tức 14 ngày về cổ phiếu và ngành: chia nhóm theo chủ đề, phân biệt tin ảnh hưởng thực sự đến giá trị doanh nghiệp với tin '
        'gây nhiễu, tâm lý chung (tích cực/tiêu cực), và các sự kiện sắp tới cần chú ý. Không bịa tin; thiếu tin thì nói rõ.',
  ),
  ExtraKind(
    'risk',
    'Kịch bản xấu và rủi ro',
    'Phân tích kịch bản xấu',
    'Kiểm tra sức chịu đựng: dùng beta, VaR, sụt giảm lịch sử và các cú sốc giả định (VN-Index giảm 10% và 20%) đã tính sẵn để ước lượng '
        'thiệt hại; nêu 3–5 yếu tố có thể gây kịch bản xấu, dấu hiệu cảnh báo sớm và ngưỡng làm luận điểm sai.',
  ),
];

ExtraKind extraKind(String id) => extraKinds.firstWhere((k) => k.id == id);

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, dynamic> _obj(Map<String, dynamic> properties) => {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
      'additionalProperties': false,
    };

final extraSchema = _obj({
  'headline': _str,
  'summary': _str,
  'findings': {
    'type': 'array',
    'items': _obj({'title': _str, 'detail': _str, 'evidence': _str}),
  },
  'metrics': {
    'type': 'array',
    'items': _obj({'label': _str, 'value': _str, 'note': _str}),
  },
  'implication': _str,
  'watch_points': _strList,
  'limits': _strList,
});

String extraSystem(ExtraKind k) => '''$stockCommon

Nhiệm vụ: lập phân tích bổ sung theo chủ đề "${k.title}" cho báo cáo cổ phiếu đã có.
${k.instruction}

Quy tắc riêng:
- Các số liệu trong dữ liệu bổ sung đã được tính sẵn trên máy; chỉ trích dẫn đúng số, không tự tính lại hay làm tròn sai.
- Mỗi phát hiện (findings) phải có bằng chứng (evidence) là số liệu hoặc nguồn cụ thể trong dữ liệu.
- metrics là 4–8 chỉ số then chốt đáng nhìn nhất (nhãn ngắn, giá trị kèm đơn vị, ghi chú 1 câu).
- implication nêu rõ chủ đề này ủng hộ hay làm yếu nhận định ở báo cáo thứ nhất, và vì sao.
- limits ghi dữ liệu còn thiếu làm hạn chế phân tích này. Không bịa số liệu, ngày tháng, sự kiện.''';

String extraPrompt(String symbol, ExtraKind k, Map<String, dynamic> first, Map<String, dynamic> data) =>
    '''Hôm nay là ${DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10)}. Phân tích bổ sung "${k.title}" cho cổ phiếu $symbol.

## Tóm tắt báo cáo thứ nhất
${jsonEncode(first)}

## Dữ liệu bổ sung (tính sẵn)
${jsonEncode(data)}

Yêu cầu độ dài: headline 1 câu; summary 3–4 câu; 3–5 findings, mỗi mục detail 1–3 câu; 4–8 metrics; implication 2–3 câu; watch_points 2–4 ý ngắn.''';
