// Số liệu cơ bản từ Vietcap IQ: hồ sơ, chỉ số TTM theo quý, kết quả kinh doanh theo quý.
// Số liệu tính theo đồng; được quy đổi sang tỷ đồng khi đưa vào prompt.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market.dart' show userAgent;

const _iq = 'https://iq.vietcap.com.vn/api/iq-insight-service/v1/company';

// Mã khoản mục báo cáo kết quả kinh doanh (doanh nghiệp phi tài chính, chuẩn VAS)
const _incomeItems = {
  'isa3': 'doanh_thu_thuan',
  'isa5': 'loi_nhuan_gop',
  'isa11': 'loi_nhuan_hoat_dong',
  'isa16': 'loi_nhuan_truoc_thue',
  'isa22': 'loi_nhuan_sau_thue_cong_ty_me',
};

const _ratioItems = [
  'pe', 'pb', 'ps', 'evToEbitda', 'dividendYield', 'roe', 'roa', 'roic', 'grossMargin', //
  'ebitMargin', 'afterTaxProfitMargin', 'debtToEquity', 'currentRatio', 'cashCycle',
  // Chỉ số riêng cho ngân hàng
  'netInterestMargin', 'npl', 'cir', 'ldrLoanDepositRatio', 'loansGrowth', 'depositGrowth', 'casaRatio',
];

Future<dynamic> _get(String url) async {
  final resp = await http.get(Uri.parse(url), headers: userAgent).timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
  return (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['data'];
}

double? _r(dynamic x, [int d = 4]) {
  if (x is! num || x == 0) return null;
  return double.parse(x.toStringAsFixed(d));
}

int? _ty(dynamic x) => x is num ? (x / 1e9).round() : null;

String _period(int quarter, dynamic year) => 'Q$quarter/$year';

Future<Map<String, dynamic>> fetchFundamentals(String symbol) async {
  final out = <String, dynamic>{};
  var isBank = false;

  try {
    final c = (await _get('$_iq/$symbol')) as Map<String, dynamic>? ?? {};
    isBank = c['isBank'] == true;
    out['company'] = {
      'ten': c['viOrganName'],
      'nganh': c['sectorVn'],
      'la_ngan_hang': isBank,
      'von_hoa_ty_dong': _ty(c['marketCap']),
      'so_huu_nuoc_ngoai': c['foreignerPercentage'],
      'room_nuoc_ngoai_toi_da': c['maximumForeignPercentage'],
      'so_huu_nha_nuoc': c['statePercentage'],
      'gia_tri_khop_tb_1_thang_ty_dong': _ty(c['averageMatchValue1Month']),
      // Khuyến nghị của bộ phận phân tích Vietcap (nguồn bên thứ ba, chỉ để tham chiếu)
      'vietcap_khuyen_nghi': c['rating'],
      'vietcap_gia_muc_tieu': c['targetPrice'],
      'vietcap_ngay_khuyen_nghi': c['ratingAsOf'],
    };
  } catch (_) {}

  try {
    final rows = ((await _get('$_iq/$symbol/statistics-financial')) as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((r) => (r['quarter'] ?? 0) >= 1 && (r['quarter'] ?? 0) <= 4)
        .toList()
      ..sort((a, b) {
        final y = (a['yearReport'] as num).compareTo(b['yearReport'] as num);
        return y != 0 ? y : (a['quarter'] as num).compareTo(b['quarter'] as num);
      });
    out['chi_so_ttm_theo_quy'] = [
      for (final r in rows.skip(rows.length > 8 ? rows.length - 8 : 0))
        {
          'ky': _period(r['quarter'], r['yearReport']),
          for (final k in _ratioItems)
            if (_r(r[k]) != null) k: _r(r[k]),
        },
    ];
  } catch (_) {}

  if (!isBank) {
    try {
      final data = (await _get('$_iq/$symbol/financial-statement?section=INCOME_STATEMENT')) as Map<String, dynamic>;
      final rows = ((data['quarters'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .where((r) => (r['lengthReport'] ?? 0) >= 1 && (r['lengthReport'] ?? 0) <= 4)
          .toList()
        ..sort((a, b) {
          final y = (a['yearReport'] as num).compareTo(b['yearReport'] as num);
          return y != 0 ? y : (a['lengthReport'] as num).compareTo(b['lengthReport'] as num);
        });
      out['ket_qua_kinh_doanh_theo_quy_ty_dong'] = [
        for (final r in rows.skip(rows.length > 8 ? rows.length - 8 : 0))
          {
            'ky': _period(r['lengthReport'], r['yearReport']),
            'ngay_cong_bo': (r['publicDate'] as String?)?.substring(0, 10),
            for (final e in _incomeItems.entries)
              if (r[e.key] != null) e.value: _ty(r[e.key]),
          },
      ];
    } catch (_) {}
  }
  return out;
}
