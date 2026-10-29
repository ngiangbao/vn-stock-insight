import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/portfolio.dart';

int _t(int i) => DateTime.utc(2025, 1, 1).add(Duration(days: i)).millisecondsSinceEpoch ~/ 1000 + 3600 * 3;
List<Bar> _bars(List<double> c) => [for (var i = 0; i < c.length; i++) Bar(_t(i), c[i], c[i], c[i], c[i], 1000)];

void main() {
  final rnd = math.Random(3);
  final idx = <double>[1000], a = <double>[10], b = <double>[20], cc = <double>[30];
  for (var i = 0; i < 300; i++) {
    final m = (rnd.nextDouble() - 0.5) * 0.02;
    idx.add(idx.last * (1 + m));
    a.add(a.last * (1 + 1.5 * m)); // beta 1,5
    b.add(b.last * (1 + 0.5 * m)); // beta 0,5
    cc.add(cc.last * (1 + (rnd.nextDouble() - 0.5) * 0.02)); // độc lập
  }
  final bars = {'AAA': _bars(a), 'BBB': _bars(b), 'CCC': _bars(cc)};

  test('tỷ trọng, beta danh mục là trung bình theo tỷ trọng, đóng góp rủi ro cộng đủ 100%', () {
    final holdings = [
      {'symbol': 'AAA', 'shares': 1000.0, 'cost': 8.0}, // giá trị ~ 10 × 1000
      {'symbol': 'BBB', 'shares': 500.0}, // ~ 20 × 500
      {'symbol': 'CCC', 'shares': 100.0}, // ~ 30 × 100
      {'symbol': 'ZZZ', 'shares': 10.0}, // không có giá
    ];
    final s = portfolioStats(
      holdings: holdings,
      bars: bars,
      index: _bars(idx),
      sectors: {'AAA': 'Ngân hàng', 'BBB': 'Ngân hàng', 'CCC': 'Thép'},
    )!;
    final rows = (s['vi_the'] as List).cast<Map>();
    expect(rows.length, 3);
    expect((s['ma_bi_bo_qua_thieu_du_lieu_gia'] as List), ['ZZZ']);
    expect(rows.fold<double>(0, (x, r) => x + (r['ty_trong'] as double)), closeTo(1.0, 0.002));
    expect(rows.fold<double>(0, (x, r) => x + (r['dong_gop_rui_ro'] as double)), closeTo(1.0, 0.002));
    final sorted = [for (final r in rows) r['ty_trong'] as double];
    expect(sorted, [...sorted]..sort((x, y) => y.compareTo(x)), reason: 'sắp theo tỷ trọng giảm dần');
    // beta danh mục = Σ w_i beta_i
    final expectBeta = rows.fold<double>(0, (x, r) => x + (r['ty_trong'] as double) * (r['beta'] as double));
    expect((s['chi_so_danh_muc'] as Map)['beta'] as double, closeTo(expectBeta, 0.03));
    final div = s['da_dang_hoa'] as Map;
    expect(div['ty_so_da_dang_hoa'] as double, greaterThanOrEqualTo(1.0));
    expect(div['so_ma_hieu_dung'] as double, inInclusiveRange(1.0, 3.0));
    expect(div['so_nganh'], 2);
    expect(((s['nganh'] as List).first as Map)['nganh'], 'Ngân hàng');
    expect((s['tuong_quan'] as Map)['ma_tran'], hasLength(3));
    final stress = ((s['kiem_tra_suc_chiu_dung'] as Map)['cu_soc_theo_beta'] as List).cast<Map>();
    expect(stress.first['danh_muc_uoc_tinh_pct'] as double, closeTo(-10 * (expectBeta), 0.5));
    final lai = rows.firstWhere((r) => r['ma'] == 'AAA')['lai_lo_pct'];
    expect(lai, isNotNull);
  });

  test('một mã 100% và tiền mặt: danh mục bằng chính mã đó khi không có tiền, tiền mặt làm giảm biến động', () {
    final only = portfolioStats(
      holdings: [
        {'symbol': 'AAA', 'shares': 100.0},
      ],
      bars: bars,
      index: _bars(idx),
    )!;
    final withCash = portfolioStats(
      holdings: [
        {'symbol': 'AAA', 'shares': 100.0},
      ],
      bars: bars,
      index: _bars(idx),
      cash: 1000,
    )!;
    final v1 = (only['da_dang_hoa'] as Map)['bien_dong_danh_muc_nam'] as double;
    final v2 = (withCash['da_dang_hoa'] as Map)['bien_dong_danh_muc_nam'] as double;
    expect(v2, lessThan(v1));
    expect(withCash['ty_trong_tien_mat'] as double, greaterThan(0.3));
    expect(
      portfolioStats(
        holdings: [
          {'symbol': 'ZZZ', 'shares': 5.0},
        ],
        bars: bars,
        index: _bars(idx),
      ),
      isNull,
    );
    expect(portfolioStats(holdings: const [], bars: bars, index: _bars(idx)), isNull);
  });

  test('P/E, P/B điều hòa và ROE theo tỷ trọng', () {
    final rows = [
      {'ma': 'A', 'ty_trong': 0.5},
      {'ma': 'B', 'ty_trong': 0.5},
    ];
    final v = weightedValuation(rows, {
      'A': {'pe': 10, 'pb': 1, 'roe': 0.2},
      'B': {'pe': 20, 'pb': 3, 'roe': 10}, // ROE ở dạng phần trăm
    });
    expect(v['pe'], closeTo(13.33, 0.01)); // 1 / (0,5/10 + 0,5/20)
    expect(v['roe'], closeTo(0.15, 1e-9));
  });

  test('PortfolioStore: lưu, nạp lại, thêm phân tích mới nhất trước và giữ tối đa 10 bản', () async {
    final dir = await Directory.systemTemp.createTemp('pf');
    final file = File('${dir.path}/portfolios.json');
    final store = PortfolioStore(file);
    final p = newPortfolio('Danh mục A');
    (p['holdings'] as List).add({'symbol': 'FPT', 'shares': 100.0, 'cost': 90.0});
    await store.upsert(p);
    for (var i = 0; i < 12; i++) {
      await store.addAnalysis(p['id'] as String, {'id': 'a$i', 'created_at': DateTime(2026, 1, i + 1).toIso8601String()});
    }
    final again = PortfolioStore(file);
    await again.load();
    final loaded = again.byId(p['id'] as String)!;
    expect((loaded['analyses'] as List).length, PortfolioStore.maxAnalyses);
    expect(((loaded['analyses'] as List).first as Map)['id'], 'a11');
    expect(((loaded['holdings'] as List).first as Map)['symbol'], 'FPT');
    await again.remove(p['id'] as String);
    expect(again.portfolios, isEmpty);
    await dir.delete(recursive: true);
  });
}
