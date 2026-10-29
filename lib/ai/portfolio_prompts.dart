// Prompt và schema phân tích danh mục đầu tư theo khung quản lý danh mục của CFA (cấp 3): bản tuyên bố chính sách đầu tư (IPS),
// rủi ro và lợi suất, đa dạng hóa, định giá tổng thể, tái cân bằng, kịch bản và sai lệch hành vi.
// Viết lại bằng tiếng Việt; không phải sản phẩm của CFA Institute.

import 'dart:convert';

const portfolioSystem = '''Bạn là chuyên viên quản lý danh mục am hiểu chương trình CFA cấp 3, viết tiếng Việt cho nhà đầu tư cá nhân.

Nguyên tắc:
- Các chỉ số định lượng (tỷ trọng, lợi suất, biến động, Sharpe, beta, VaR, tương quan, đóng góp rủi ro, HHI, kiểm tra sức chịu đựng) đã được máy tính sẵn. TUYỆT ĐỐI không tự tính lại hay sửa; chỉ diễn giải và trích đúng số.
- Chỉ dùng dữ liệu được cung cấp. Không bịa số liệu. Thiếu dữ liệu thì ghi vào data_gaps.
- Đây là tài liệu tham khảo, KHÔNG phải lời khuyên mua/bán. Không nêu lệnh mua/bán, không nêu tỷ trọng mục tiêu hay số lượng cổ phiếu cụ thể. Với từng mã chỉ dùng các mức độ định tính đã quy định.
- Tỷ trọng và đóng góp rủi ro là phân số (0,25 = 25%). Giá cổ phiếu tính theo nghìn đồng.

Áp dụng lần lượt:
1. Tuyên bố chính sách đầu tư (IPS): đối chiếu mục tiêu, khung thời gian và mức chấp nhận rủi ro mà người dùng khai báo với đặc điểm thực tế của danh mục (biến động, sụt giảm tối đa, beta, tập trung). Kết luận danh mục phù hợp, phù hợp một phần hay lệch so với IPS và lệch ở đâu.
2. Rủi ro: tập trung (HHI, số mã hiệu dụng, mã lớn nhất), tương quan giữa các mã, mã nào đóng góp rủi ro nhiều hơn tỷ trọng vốn, rủi ro đuôi (VaR/CVaR, kurtosis) và kết quả kiểm tra sức chịu đựng.
3. Lợi suất: so với VN-Index (alpha, tracking error, information ratio, capture), mã nào đóng góp chính, chất lượng lợi suất điều chỉnh rủi ro (Sharpe, Sortino).
4. Định giá và phong cách: P/E, P/B, ROE của cả danh mục, nghiêng về tăng trưởng hay giá trị, ngành.
5. Đa dạng hóa: tỷ trọng ngành, ý nghĩa của tương quan, khoảng trống hoặc chồng lấn đáng chú ý (nêu hướng cân nhắc định tính, không nêu mã hay tỷ trọng cụ thể).
6. Tái cân bằng: nên theo dõi theo lịch hay theo ngưỡng lệch, các điều kiện kích hoạt xem lại, chi phí giao dịch và thuế (T+2, phí) cần tính đến. Chỉ nêu phương pháp và điều kiện, không nêu lệnh.
7. Sai lệch hành vi thường gặp với danh mục như vậy (neo giá vốn, tâm lý ngại bán lỗ, thiên kiến nội địa, tập trung quá mức).
8. Kịch bản có xác suất (3 kịch bản, tổng xác suất đúng 100) và các chỉ tiêu cần theo dõi.''';

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, dynamic> _obj(Map<String, dynamic> properties) => {
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
      'additionalProperties': false,
    };

const holdingActions = ['Giữ và theo dõi', 'Cân nhắc giảm tập trung', 'Cần xem lại luận điểm', 'Cân nhắc phân tích thêm'];

final portfolioSchema = _obj({
  'rating': {
    'type': 'string',
    'enum': ['Cân đối', 'Cần cân nhắc', 'Cần xem lại'],
  },
  'confidence': {
    'type': 'string',
    'enum': ['Thấp', 'Trung bình', 'Cao'],
  },
  'headline': _str,
  'summary': _str,
  'ips': _obj({'objective': _str, 'horizon': _str, 'risk_tolerance': _str, 'verdict': _str}),
  'risk': _obj({'summary': _str, 'concentration': _str, 'correlation': _str, 'tail': _str, 'stress': _str}),
  'returns': _obj({'summary': _str, 'attribution': _str, 'risk_adjusted': _str}),
  'valuation': _obj({'summary': _str, 'style': _str}),
  'diversification': _obj({'summary': _str, 'sectors': _str, 'considerations': _strList}),
  'holdings': {
    'type': 'array',
    'items': _obj({
      'symbol': _str,
      'comment': _str,
      'consideration': {'type': 'string', 'enum': holdingActions},
    }),
  },
  'rebalancing': _obj({'approach': _str, 'triggers': _strList, 'costs': _str}),
  'behavioral': _strList,
  'scenarios': {
    'type': 'array',
    'items': _obj({
      'name': {
        'type': 'string',
        'enum': ['Tích cực', 'Cơ sở', 'Tiêu cực'],
      },
      'probability': {'type': 'integer'},
      'condition': _str,
      'effect': _str,
      'signals': _str,
    }),
  },
  'monitoring': _strList,
  'risks': _strList,
  'data_gaps': _strList,
  'ethics': _str,
});

String portfolioPrompt(Map<String, dynamic> p, Map<String, dynamic> inputs) {
  final today = DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);
  return '''Hôm nay là $today. Phân tích danh mục "${p['name']}".

## Tuyên bố chính sách đầu tư do người dùng khai báo
${jsonEncode({'muc_tieu': p['goal'], 'khung_thoi_gian': p['horizon'], 'chap_nhan_rui_ro': p['risk']})}

## Chỉ số định lượng đã tính sẵn (1 năm giao dịch gần nhất, tỷ trọng hiện tại giữ không đổi)
${jsonEncode(inputs['stats'])}

## Định giá tổng hợp của danh mục (P/E, P/B điều hòa theo tỷ trọng, ROE theo tỷ trọng)
${jsonEncode(inputs['valuation'])}

## Chỉ số cơ bản từng mã
${jsonEncode(inputs['fundamentals'])}

## Bối cảnh vĩ mô Việt Nam
${jsonEncode(inputs['macro'])}

## Tin tức mới liên quan các mã trong danh mục
${jsonEncode(inputs['news'])}

Yêu cầu độ dài: headline 1 câu; summary 3–5 câu; mỗi đoạn 2–4 câu; mỗi danh sách 2–5 ý ngắn.
holdings có một mục cho MỖI mã trong danh mục, theo thứ tự tỷ trọng giảm dần. scenarios đủ 3 kịch bản, tổng xác suất đúng 100.''';
}
