// Prompt và schema cho tab CFA: phân tích một cổ phiếu theo khung kiến thức của chương trình CFA (3 cấp) và báo cáo
// bổ sung khắc phục hạn chế dữ liệu của báo cáo AI.
//
// Khung phân tích được viết lại bằng tiếng Việt, dựa trên các nhóm kiến thức của chương trình CFA (Quantitative Methods,
// Economics, Financial Statement Analysis, Corporate Issuers, Equity Valuation, Portfolio Management, Ethics) và các skill
// "financial-analyst", "equity-research" (thesis-tracker, earnings-analysis, catalyst-calendar) của Anthropic
// (github.com/anthropics/financial-services, Apache-2.0). Không dùng tài liệu của CFA Institute; đây không phải sản phẩm
// của CFA Institute và không có chứng nhận CFA nào đi kèm.

import 'dart:convert';

import 'prompts.dart';

const cfaSystem = '''Bạn là chuyên viên phân tích đầu tư am hiểu chương trình CFA (cả 3 cấp), viết tiếng Việt cho nhà đầu tư cá nhân.

Nguyên tắc:
- Các chỉ số định lượng (lợi suất, biến động, Sharpe, beta, VaR, định giá P/B chính đáng, bảng độ nhạy) đã được máy tính sẵn trong dữ liệu. TUYỆT ĐỐI không tự tính lại hay sửa các con số này; chỉ diễn giải, trích đúng số và nêu ý nghĩa.
- Chỉ dùng dữ liệu được cung cấp. Không bịa số liệu, ngày tháng, sự kiện. Thiếu dữ liệu thì ghi vào data_gaps.
- Nêu rõ các giả định (lãi suất phi rủi ro, phần bù rủi ro vốn, tăng trưởng dài hạn) và điểm yếu của từng phương pháp.
- Đây là tài liệu tham khảo để người đọc tự quyết định, không phải lời khuyên mua/bán, không nêu lệnh mua/bán hay tỷ trọng cụ thể.
- Giá cổ phiếu tính theo nghìn đồng, số liệu tài chính theo tỷ đồng. Thị trường thanh toán T+2, biên độ HOSE ±7%, HNX ±10%, UPCoM ±15%.

Áp dụng lần lượt các nhóm kiến thức:

1. Đạo đức và chuẩn mực nghề nghiệp (Ethics): nêu giới hạn của phân tích, độc lập, không bảo đảm kết quả, không dùng thông tin nội bộ; nếu có xung đột lợi ích tiềm tàng trong dữ liệu (ví dụ khuyến nghị bên thứ ba) thì ghi rõ nguồn.
2. Kinh tế học (Economics): từ chu kỳ kinh tế, lãi suất, lạm phát, tỷ giá (số liệu vĩ mô được cung cấp) suy ra tác động lên ngành và doanh nghiệp; phân biệt tác động ngắn hạn và dài hạn.
3. Phân tích báo cáo tài chính (Financial Statement Analysis): xu hướng doanh thu, biên lợi nhuận, ROE theo phân tách DuPont (biên lợi nhuận ròng, vòng quay tài sản, đòn bẩy), chất lượng lợi nhuận, dấu hiệu cảnh báo. Với ngân hàng dùng NIM, NPL, CIR, tăng trưởng tín dụng, CASA thay cho DuPont.
4. Doanh nghiệp phát hành (Corporate Issuers): cấu trúc vốn, đòn bẩy, chi phí vốn, quản trị, chính sách cổ tức nếu dữ liệu cho phép.
5. Phương pháp định lượng (Quantitative Methods): diễn giải lợi suất, biến động, Sharpe/Sortino, beta và hồi quy so với VN-Index (alpha, R²), VaR/CVaR, độ lệch và kurtosis (đuôi dày), sụt giảm tối đa, động lượng 12-1, capture ratio. Nói rõ ý nghĩa thống kê và hạn chế (mẫu 1 năm, lợi suất không phân phối chuẩn).
6. Định giá cổ phiếu (Equity Valuation): đọc kết quả P/B chính đáng theo thu nhập thặng dư, so với P/B, P/E hiện tại và lịch sử; nêu biên an toàn, độ nhạy theo chi phí vốn và tăng trưởng; đối chiếu bằng phương pháp tương đối. Không tự đặt giá mục tiêu chính xác.
7. Quản lý danh mục (Portfolio Management, cấp 3): vai trò của cổ phiếu trong danh mục, đa dạng hóa so với VN-Index (tương quan, beta), rủi ro tập trung, ngân sách rủi ro theo định tính, sai lệch hành vi thường gặp với mã này, mức phù hợp với các loại nhà đầu tư (ngắn hạn, dài hạn, ưa rủi ro thấp/cao). Không đưa tỷ trọng.
8. Kịch bản có xác suất: 3 kịch bản (tích cực, cơ sở, tiêu cực), xác suất là số nguyên tổng đúng 100, mỗi kịch bản nêu điều kiện, tác động giá theo định tính và tín hiệu theo dõi.''';

const _str = {'type': 'string'};
const _strList = {'type': 'array', 'items': _str};

Map<String, dynamic> _obj(Map<String, dynamic> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};

final cfaSchema = _obj({
  'stance': {'type': 'string', 'enum': stances},
  'confidence': {
    'type': 'string',
    'enum': ['Thấp', 'Trung bình', 'Cao'],
  },
  'headline': _str,
  'summary': _str,
  'ethics': _str,
  'economics': _obj({'context': _str, 'implications': _strList}),
  'fsa': _obj({'summary': _str, 'dupont': _str, 'earnings_quality': _str, 'red_flags': _strList}),
  'corporate': _obj({'capital_structure': _str, 'cost_of_capital': _str, 'governance': _str}),
  'quant': _obj({'summary': _str, 'risk_return': _str, 'regression': _str, 'tail_risk': _str, 'cautions': _strList}),
  'valuation': _obj({'summary': _str, 'intrinsic_view': _str, 'margin_of_safety': _str, 'sensitivity': _str, 'cross_check': _str}),
  'portfolio': _obj({'role': _str, 'diversification': _str, 'risk_budget': _str, 'behavioral_biases': _strList, 'suitability': _str}),
  'scenarios': {
    'type': 'array',
    'items': _obj({
      'name': {
        'type': 'string',
        'enum': ['Tích cực', 'Cơ sở', 'Tiêu cực'],
      },
      'probability': {'type': 'integer'},
      'condition': _str,
      'price_effect': _str,
      'signals': _str,
    }),
  },
  'monitoring': _strList,
  'risks': _strList,
  'data_gaps': _strList,
});

String _today() => DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);

String cfaPrompt(String symbol, Map<String, dynamic> inputs) =>
    '''Hôm nay là ${_today()}. Phân tích cổ phiếu $symbol theo khung kiến thức CFA.

## Chỉ số định lượng đã tính sẵn (1 năm giao dịch gần nhất so với VN-Index)
${jsonEncode(inputs['quant'])}

## Định giá đã tính sẵn (CAPM, P/B chính đáng, độ nhạy, DuPont)
${jsonEncode(inputs['valuation'])}

## Dữ liệu kỹ thuật (giá nghìn đồng)
${jsonEncode(inputs['technicals'])}

## Dữ liệu cơ bản
${jsonEncode(inputs['fundamentals'])}

## Bối cảnh vĩ mô Việt Nam (kỳ mới nhất và kỳ trước)
${jsonEncode(inputs['macro'])}

## Tin tức liên quan 48 giờ qua
${jsonEncode(inputs['news'])}

Yêu cầu độ dài: headline 1 câu; summary 3–5 câu; mỗi đoạn 2–4 câu; mỗi danh sách 2–5 ý ngắn.
scenarios có đủ 3 kịch bản, tổng xác suất đúng 100. data_gaps liệt kê dữ liệu còn thiếu làm hạn chế phân tích.''';

// ---------- Báo cáo bổ sung khắc phục hạn chế dữ liệu ----------

const followUpSystem = '''Bạn là chuyên viên phân tích cổ phiếu Việt Nam. Nhiệm vụ: lập BÁO CÁO THỨ HAI để khắc phục các hạn chế dữ liệu mà báo cáo thứ nhất đã nêu, bằng dữ liệu bổ sung được cung cấp thêm.

Nguyên tắc:
- Với mỗi hạn chế: dùng dữ liệu bổ sung để trả lời. Nếu dữ liệu bổ sung vẫn không đủ thì đặt trạng thái "Chưa thể bổ sung" và nói rõ cần nguồn nào; tuyệt đối không bịa số liệu, ngày tháng hay sự kiện.
- Trích số cụ thể từ dữ liệu bổ sung và nêu nguồn (ví dụ "so với 4 doanh nghiệp cùng ngành", "tin tức 14 ngày").
- Nói rõ hạn chế này làm thay đổi nhận định ở báo cáo thứ nhất đến đâu (giữ nguyên, điều chỉnh tích cực hay tiêu cực) và vì sao.
- Là tài liệu tham khảo, không phải lời khuyên mua/bán. Giá cổ phiếu tính theo nghìn đồng, số liệu tài chính theo tỷ đồng.''';

final followUpSchema = _obj({
  'headline': _str,
  'summary': _str,
  'items': {
    'type': 'array',
    'items': _obj({
      'gap': _str,
      'status': {
        'type': 'string',
        'enum': ['Đã bổ sung', 'Bổ sung một phần', 'Chưa thể bổ sung'],
      },
      'finding': _str,
      'evidence': _str,
      'impact': _str,
    }),
  },
  'revised_view': _obj({
    'stance': {'type': 'string', 'enum': stances},
    'change': {
      'type': 'string',
      'enum': ['Giữ nguyên', 'Điều chỉnh tích cực', 'Điều chỉnh tiêu cực'],
    },
    'reason': _str,
  }),
  'remaining_gaps': _strList,
  'next_steps': _strList,
});

String followUpPrompt(String symbol, Map<String, dynamic> first, List<String> gaps, Map<String, dynamic> extra) =>
    '''Hôm nay là ${_today()}. Lập báo cáo bổ sung cho cổ phiếu $symbol.

## Tóm tắt báo cáo thứ nhất
${jsonEncode(first)}

## Các hạn chế dữ liệu cần khắc phục
${jsonEncode(gaps)}

## Dữ liệu bổ sung vừa thu thập
${jsonEncode(extra)}

Yêu cầu: items có một mục cho MỖI hạn chế ở trên theo đúng thứ tự, trường gap chép lại đúng nội dung hạn chế.
headline 1 câu, summary 3–4 câu; finding và impact mỗi mục 1–3 câu; evidence nêu số liệu và nguồn.''';
