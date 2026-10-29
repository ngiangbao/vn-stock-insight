import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/quant.dart';

// Phiên giao dịch thứ i (bỏ qua cuối tuần không quan trọng vì chỉ cần ngày khác nhau)
int _t(int i) => DateTime.utc(2024, 1, 1).add(Duration(days: i)).millisecondsSinceEpoch ~/ 1000 + 3600 * 3;

List<Bar> _bars(List<double> closes) => [for (var i = 0; i < closes.length; i++) Bar(_t(i), closes[i], closes[i], closes[i], closes[i], 1000)];

void main() {
  test('beta = 2 khi cổ phiếu nhân đôi lợi suất của chỉ số; alpha gần 0', () {
    final rnd = math.Random(7);
    final idx = <double>[1000];
    final stock = <double>[10];
    for (var i = 0; i < 300; i++) {
      final r = (rnd.nextDouble() - 0.5) * 0.02;
      idx.add(idx.last * (1 + r));
      stock.add(stock.last * (1 + 2 * r));
    }
    final q = quantStats(_bars(stock), _bars(idx))!;
    expect(q['beta'], closeTo(2.0, 0.01));
    expect(q['tuong_quan_vnindex'], closeTo(1.0, 0.001));
    expect(q['r_binh_phuong'], closeTo(1.0, 0.01));
    expect(q['so_phien'], 252);
    expect(q['sut_giam_toi_da'] as double, lessThan(0));
    expect(q['var95_1_ngay'] as double, greaterThan(0));
    expect(q['cvar95_1_ngay'] as double, greaterThanOrEqualTo(q['var95_1_ngay'] as double));
    expect(quantStats(_bars(stock.take(30).toList()), _bars(idx.take(30).toList())), isNull);
  });

  test('sụt giảm tối đa và Sharpe trên chuỗi biết trước', () {
    final c = [for (var i = 0; i < 100; i++) 100.0 + i]; // tăng đều
    c.addAll([for (var i = 0; i < 50; i++) 199.0 - i * 2]); // giảm 50%
    final q = quantStats(_bars(c), _bars([for (final v in c) v * 10]))!;
    expect(q['sut_giam_toi_da'], closeTo(-0.5, 0.01));
    expect(q['so_phien_duoi_dinh_dai_nhat'], 49);
  });

  test('định giá P/B chính đáng: (ROE - g) / (ke - g) và bảng độ nhạy', () {
    final fund = {
      'company': {'la_ngan_hang': false},
      'chi_ttm_theo_quy': [],
      'chi_so_ttm_theo_quy': [
        {'ky': 'Q1/2026', 'roe': 0.18, 'pb': 3.0, 'pe': 16.0, 'afterTaxProfitMargin': 0.09, 'debtToEquity': 1.0},
      ],
    };
    const a = CfaAssumptions(rf: 0.04, erp: 0.06, g: 0.04);
    final v = cfaValuation(fund, 30, 1.0, a);
    expect(v['chi_phi_von_chu_so_huu_capm'], closeTo(0.10, 1e-9));
    // (0.18 - 0.04) / (0.10 - 0.04) = 2.333
    expect(v['pb_chinh_dang'], closeTo(2.33, 0.01));
    expect(v['bvps_uoc_tinh_nghin_dong'], 10.0);
    expect(v['gia_noi_tai_uoc_tinh_nghin_dong'], closeTo(23.3, 0.1));
    expect(v['chenh_lech_so_voi_gia_pct'], closeTo(-22.2, 0.2));
    expect((v['bang_do_nhay'] as List).length, 9);
    expect(v['dupont']['don_bay_tai_chinh_xap_xi'], 2.0);
    // thiếu dữ liệu: không ném lỗi, có ghi chú
    final empty = cfaValuation(null, null, null, a);
    expect(empty['pb_chinh_dang'], isNull);
    expect((empty['ghi_chu'] as List), isNotEmpty);
  });
}
