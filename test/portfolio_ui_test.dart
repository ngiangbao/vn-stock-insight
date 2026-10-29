import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart' show appTheme;
import 'package:vn_stock_insight/services/cfa.dart';
import 'package:vn_stock_insight/services/portfolio.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/analysis_report.dart';
import 'package:vn_stock_insight/ui/cfa_page.dart';
import 'package:vn_stock_insight/ui/cfa_report.dart';
import 'package:vn_stock_insight/ui/portfolio_page.dart';
import 'package:vn_stock_insight/ui/portfolio_report.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-pf';
  @override
  Future<String?> getDownloadsPath() async => '/tmp/vnsi-test-pf-downloads';
}

Map<String, dynamic> _analysis({DateTime? at, List<Map<String, dynamic>>? snapshot}) {
  final now = at ?? DateTime.now();
  final dates = [for (var i = 0; i < 100; i++) DateTime.utc(2026, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10)];
  return {
    'id': '${now.millisecondsSinceEpoch}',
    'created_at': now.toIso8601String(),
    'ai': 'test',
    'assumptions': {'rf': 0.045, 'erp': 0.07, 'g': 0.04},
    'ips': {'goal': 'Cân bằng', 'horizon': 'Trung hạn (1–3 năm)', 'risk': 'Vừa'},
    'snapshot':
        snapshot ??
        [
          {'symbol': 'FPT', 'shares': 1000.0},
          {'symbol': 'VCB', 'shares': 500.0},
        ],
    'cash': 0.0,
    'series': {
      'dates': dates,
      'danh_muc': [for (var i = 0; i < 100; i++) i * 0.15],
      'vnindex': [for (var i = 0; i < 100; i++) i * 0.1 - 2],
    },
    'inputs': {
      'stats': {
        'den_ngay': '2026-10-29',
        'tong_gia_tri_nghin_dong': 120000.0,
        'ty_trong_tien_mat': 0.0,
        'so_ma': 2,
        'ma_bi_bo_qua_thieu_du_lieu_gia': ['ZZZ'],
        'chi_so_danh_muc': {
          'loi_suat_nam': 0.18,
          'loi_suat_vnindex_nam': 0.12,
          'bien_dong_nam': 0.22,
          'bien_dong_vnindex_nam': 0.18,
          'sharpe': 0.7,
          'sortino': 1.0,
          'sut_giam_toi_da': -0.2,
          'sut_giam_hien_tai': -0.03,
          'var95_1_ngay': 0.02,
          'cvar95_1_ngay': 0.03,
          'beta': 1.1,
          'alpha_jensen_nam': 0.02,
          'tuong_quan_vnindex': 0.8,
          'r_binh_phuong': 0.64,
          'tracking_error': 0.1,
          'information_ratio': 0.5,
          'so_phien': 252,
          'do_lech_skew': -0.1,
          'kurtosis_vuot_chuan': 1.0,
          'capture_tang': 1.1,
          'capture_giam': 1.0,
          'dong_luong_12_1': 0.1,
        },
        'vi_the': [
          {
            'ma': 'FPT',
            'nganh': 'Công nghệ',
            'so_luong': 1000.0,
            'gia': 100.0,
            'gia_tri_nghin_dong': 100000.0,
            'ty_trong': 0.7,
            'gia_von': 80.0,
            'lai_lo_pct': 25.0,
            'loi_suat_nam': 0.3,
            'bien_dong_nam': 0.28,
            'beta': 1.2,
            'dong_gop_rui_ro': 0.78,
          },
          {
            'ma': 'VCB',
            'nganh': 'Ngân hàng',
            'so_luong': 500.0,
            'gia': 40.0,
            'gia_tri_nghin_dong': 20000.0,
            'ty_trong': 0.3,
            'gia_von': null,
            'lai_lo_pct': null,
            'loi_suat_nam': 0.1,
            'bien_dong_nam': 0.2,
            'beta': 0.9,
            'dong_gop_rui_ro': 0.22,
          },
        ],
        'nganh': [
          {'nganh': 'Công nghệ', 'ty_trong': 0.7},
          {'nganh': 'Ngân hàng', 'ty_trong': 0.3},
        ],
        'da_dang_hoa': {
          'bien_dong_danh_muc_nam': 0.22,
          'ty_so_da_dang_hoa': 1.1,
          'tuong_quan_binh_quan_cap': 0.75,
          'hhi': 0.58,
          'so_ma_hieu_dung': 1.7,
          'ty_trong_ma_lon_nhat': 0.7,
          'ty_trong_3_ma_lon_nhat': 1.0,
          'so_nganh': 2,
        },
        'tuong_quan': {
          'ma': ['FPT', 'VCB'],
          'ma_tran': [
            [1.0, 0.75],
            [0.75, 1.0],
          ],
        },
        'kiem_tra_suc_chiu_dung': {
          'cu_soc_theo_beta': [
            {'vnindex_pct': -10, 'danh_muc_uoc_tinh_pct': -11.0},
            {'vnindex_pct': -20, 'danh_muc_uoc_tinh_pct': -22.0},
          ],
          'te_nhat_1_ngay_pct': -5.1,
          'te_nhat_20_phien_pct': -14.0,
          'luu_y': 'Chỉ mang tính ước lượng.',
        },
      },
      'valuation': {'pe': 15.2, 'pb': 2.8, 'roe': 0.19},
    },
    'result': {
      'rating': 'Cần cân nhắc',
      'confidence': 'Trung bình',
      'headline': 'Danh mục tập trung vào công nghệ',
      'summary': 'Tóm tắt ' * 20,
      'ips': {'objective': 'Mục tiêu ' * 5, 'horizon': 'Thời gian ' * 4, 'risk_tolerance': 'Rủi ro ' * 5, 'verdict': 'Phù hợp một phần'},
      'risk': {
        'summary': 'Rủi ro ' * 8,
        'concentration': 'Tập trung ' * 5,
        'correlation': 'Tương quan ' * 5,
        'tail': 'Đuôi ' * 5,
        'stress': 'Sức chịu ' * 5,
      },
      'returns': {'summary': 'Lợi suất ' * 6, 'attribution': 'Đóng góp ' * 5, 'risk_adjusted': 'Sharpe ' * 5},
      'valuation': {'summary': 'Định giá ' * 6, 'style': 'Tăng trưởng ' * 4},
      'diversification': {
        'summary': 'Đa dạng ' * 6,
        'sectors': 'Ngành ' * 5,
        'considerations': ['Cân nhắc một'],
      },
      'holdings': [
        {'symbol': 'FPT', 'comment': 'Chiếm gần hết rủi ro', 'consideration': 'Cân nhắc giảm tập trung'},
        {'symbol': 'VCB', 'comment': 'Ổn định', 'consideration': 'Giữ và theo dõi'},
      ],
      'rebalancing': {
        'approach': 'Theo ngưỡng ' * 5,
        'triggers': ['Lệch quá 5%'],
        'costs': 'Phí và T+2',
      },
      'behavioral': ['Neo giá vốn'],
      'scenarios': [
        for (final (n, p) in [('Tích cực', 30), ('Cơ sở', 50), ('Tiêu cực', 20)])
          {'name': n, 'probability': p, 'condition': 'Điều kiện $n', 'effect': 'Tác động $n', 'signals': 'Tín hiệu $n'},
      ],
      'monitoring': ['Theo dõi một'],
      'risks': ['Rủi ro một'],
      'data_gaps': ['Thiếu giá một mã'],
      'ethics': 'Giới hạn ' * 8,
    },
  };
}

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false, 'flutter.autoScale': false});
  FlutterSecureStorage.setMockInitialValues({});
  PathProviderPlatform.instance = _FakePaths();
  final dir = Directory('/tmp/vnsi-test-pf');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final state = AppState();
  await tester.runAsync(() => state.init(startDashboard: false));
  return state;
}

Widget _app(AppState state, Widget home) => AppScope(
  state: state,
  child: MaterialApp(theme: appTheme(Brightness.light), darkTheme: appTheme(Brightness.dark), themeMode: ThemeMode.dark, home: home),
);

void main() {
  for (final w in [1100.0, 700.0, 360.0]) {
    testWidgets('báo cáo danh mục hiển thị đủ phần, không tràn (${w.toInt()} px)', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = newPortfolio('Danh mục A');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: PortfolioReport(p, _analysis())),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final t in [
        '1. Chính sách đầu tư (IPS)',
        '2. Vị thế và đóng góp rủi ro',
        '3. Hiệu suất so với VN-Index',
        '4. Rủi ro, đa dạng hóa và sức chịu đựng',
        '6. Tái cân bằng',
        '8. Kịch bản có xác suất',
      ]) {
        expect(find.text(t.toUpperCase()), findsOneWidget, reason: t);
      }
      expect(find.text('Tỷ trọng vốn so với đóng góp rủi ro'), findsOneWidget);
      expect(find.text('Cân nhắc giảm tập trung'), findsOneWidget);
      expect(find.textContaining('không phải lệnh mua/bán'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tab Danh mục: tạo danh mục, kiểm tra dữ liệu nhập, lưu trên máy, sửa lại', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    await tester.pumpWidget(_app(state, const CfaPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(Tab, 'Danh mục'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Chưa có danh mục nào.'), findsOneWidget);

    await tester.tap(find.text('Tạo danh mục mới'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tạo danh mục'), findsOneWidget);

    // Chưa đặt tên
    await tester.tap(find.text('Lưu và phân tích'));
    await tester.pump();
    expect(find.text('Hãy đặt tên cho danh mục.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tên danh mục'), 'Danh mục dài hạn');
    // Mã sai
    await tester.enterText(find.widgetWithText(TextField, 'Mã 1'), 'AB');
    await tester.enterText(find.widgetWithText(TextField, 'Số lượng'), '100');
    await tester.tap(find.text('Lưu và phân tích'));
    await tester.pump();
    expect(find.textContaining('3 đến 5 ký tự'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Mã 1'), 'fpt');
    await tester.enterText(find.widgetWithText(TextField, 'Số lượng'), '1000');
    await tester.enterText(find.widgetWithText(TextField, 'Giá vốn (nghìn đ)'), '90,5');
    await tester.ensureVisible(find.text('Thêm cổ phiếu'));
    await tester.tap(find.text('Thêm cổ phiếu'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Mã 2'), 'VCB');
    await tester.tap(find.text('Lưu và phân tích'));
    await tester.pump();
    expect(find.textContaining('số lượng cổ phiếu phải lớn hơn 0'), findsOneWidget, reason: 'dòng 2 thiếu số lượng');
    await tester.enterText(find.widgetWithText(TextField, 'Số lượng').last, '500');

    // Lưu (không phân tích)
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 600));
    final saved = state.portfolios.portfolios.single;
    expect(saved['name'], 'Danh mục dài hạn');
    final holdings = (saved['holdings'] as List).cast<Map>();
    expect(holdings.map((h) => h['symbol']), ['FPT', 'VCB']);
    expect(holdings.first['cost'], 90.5);
    expect(holdings.last.containsKey('cost'), isFalse);

    // Thẻ danh mục hiện trên lưới và sửa lại (xóa một dòng, đổi số lượng)
    expect(find.text('Danh mục dài hạn'), findsOneWidget);
    expect(find.text('Phân tích'), findsOneWidget, reason: 'chưa phân tích lần nào');
    await tester.tap(find.byTooltip('Sửa danh mục'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sửa danh mục'), findsOneWidget);
    await tester.tap(find.byTooltip('Xóa dòng 2'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Số lượng'), '2000');
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 600));
    final edited = state.portfolios.portfolios.single;
    expect((edited['holdings'] as List).length, 1);
    expect(((edited['holdings'] as List).first as Map)['shares'], 2000.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trang danh mục: lịch sử phân tích, báo hiệu danh mục đã đổi, xuất PDF', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    final p = newPortfolio('Danh mục thử');
    p['holdings'] = [
      {'symbol': 'FPT', 'shares': 1000.0},
      {'symbol': 'VCB', 'shares': 500.0},
    ];
    await tester.runAsync(() async {
      await state.portfolios.upsert(p);
      await state.portfolios.addAnalysis(p['id'] as String, _analysis(at: DateTime.now().subtract(const Duration(days: 3))));
      await state.portfolios.addAnalysis(p['id'] as String, _analysis());
    });
    final out = File(
      '/tmp/vnsi-test-pf-downloads/danh-muc-Danh-muc-th-${DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10)}.pdf',
    );
    final dir = Directory('/tmp/vnsi-test-pf-downloads');
    if (dir.existsSync()) dir.deleteSync(recursive: true);

    await tester.pumpWidget(_app(state, PortfolioDetailPage(p['id'] as String)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Lịch sử 2 lần:'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.textContaining('đã được chỉnh sửa sau bản phân tích này'), findsNothing);
    expect(find.text('BÁO CÁO PHÂN TÍCH DANH MỤC ĐẦU TƯ'), findsOneWidget);
    expect(find.text('Phân tích lại với giá mới nhất'), findsOneWidget);

    // Sửa danh mục sau khi phân tích: có cảnh báo
    await tester.runAsync(() async {
      p['holdings'] = [
        {'symbol': 'FPT', 'shares': 1500.0},
      ];
      await state.portfolios.upsert(p);
    });
    await tester.pump();
    expect(find.textContaining('đã được chỉnh sửa sau bản phân tích này'), findsOneWidget);

    // Chọn bản cũ
    await tester.tap(find.byType(ChoiceChip).last);
    await tester.pump();
    expect(find.text('BÁO CÁO PHÂN TÍCH DANH MỤC ĐẦU TƯ'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Xuất PDF'));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (dir.existsSync() && dir.listSync().isNotEmpty && find.text('Đang xuất…').evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 400));
    final files = dir.listSync().whereType<File>().toList();
    expect(files, isNotEmpty);
    expect(files.first.path, contains('danh-muc-'));
    expect(String.fromCharCodes(files.first.readAsBytesSync().take(5)), '%PDF-');
    expect(out.path, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phân tích danh mục rỗng báo lỗi dễ hiểu', (tester) async {
    final state = await _state(tester);
    final p = newPortfolio('Trống');
    await tester.runAsync(() => state.portfolios.upsert(p));
    Object? err;
    await tester.runAsync(() async {
      try {
        await state.analyzePortfolio(p['id'] as String);
      } catch (e) {
        err = e;
      }
    });
    expect('$err', contains('chưa có cổ phiếu'));
  });

  testWidgets('tab CFA giãn hết chiều ngang cửa sổ (form, lưới, báo cáo, danh mục)', (tester) async {
    const w = 1800.0;
    tester.view.physicalSize = const Size(w, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    final p = newPortfolio('Rộng');
    p['holdings'] = [
      {'symbol': 'FPT', 'shares': 1000.0},
    ];
    await tester.runAsync(() async {
      await state.portfolios.upsert(p);
      await state.portfolios.addAnalysis(p['id'] as String, _analysis());
    });
    await tester.pumpWidget(_app(state, const CfaPage()));
    await tester.pump(const Duration(milliseconds: 300));

    // Form: hai thẻ cạnh nhau, thẻ phải kết thúc sát mép phải
    final cards = find.byType(Card);
    expect(cards, findsNWidgets(2));
    expect(tester.getTopLeft(cards.last).dx, greaterThan(w / 2 - 20));
    expect(tester.getTopRight(cards.last).dx, greaterThan(w - 40));

    // Danh mục: lưới nhiều cột thẻ, thẻ cuối sát mép phải
    await tester.tap(find.widgetWithText(Tab, 'Danh mục'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PortfolioCard), findsOneWidget);
    expect(tester.getSize(find.byType(Card).first).width, lessThanOrEqualTo(w));

    // Báo cáo danh mục chiếm hết chiều ngang
    await tester.pumpWidget(_app(state, PortfolioDetailPage(p['id'] as String)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopRight(find.byType(PortfolioReport)).dx, greaterThan(w - 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('khung kịch bản ở báo cáo AI, CFA và danh mục cùng rộng, cùng cao dù nội dung dài ngắn khác nhau', (tester) async {
    const w = 1400.0;
    tester.view.physicalSize = const Size(w, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Báo cáo AI một cổ phiếu
    final ai = {
      'symbol': 'FPT',
      'created_at': DateTime.now().toIso8601String(),
      'ai': 'test',
      'inputs': {
        'technicals': {'close': 52.5},
      },
      'result': {
        'stance': 'Trung lập',
        'confidence': 'Vừa',
        'headline': 'H',
        'summary': 'S',
        'scenarios': {'bull': 'Ngắn', 'base': 'Vừa phải ' * 8, 'bear': 'Rất dài ' * 40},
      },
    };
    // Báo cáo CFA và danh mục: thay nội dung kịch bản bằng độ dài lệch nhau
    final pa = _analysis();
    (pa['result'] as Map)['scenarios'] = [
      {'name': 'Tích cực', 'probability': 30, 'condition': 'Ngắn', 'effect': 'a', 'signals': 'b'},
      {'name': 'Cơ sở', 'probability': 50, 'condition': 'Vừa ' * 20, 'effect': 'a', 'signals': 'b'},
      {'name': 'Tiêu cực', 'probability': 20, 'condition': 'Rất dài ' * 50, 'effect': 'a', 'signals': 'b'},
    ];
    final cfa = {
      ...pa,
      'symbol': 'HPG',
      'series': {
        'dates': (pa['series'] as Map)['dates'],
        'stock': (pa['series'] as Map)['danh_muc'],
        'index': (pa['series'] as Map)['vnindex'],
      },
      'inputs': {'quant': {}, 'valuation': {}},
      'result': {
        'stance': 'Tích cực',
        'confidence': 'Vừa',
        'headline': 'H',
        'summary': 'S',
        'scenarios': [
          for (final (n, t) in [('Tích cực', 'Ngắn'), ('Cơ sở', 'Vừa ' * 20), ('Tiêu cực', 'Rất dài ' * 50)])
            {'name': n, 'probability': 30, 'condition': t, 'price_effect': 'a', 'signals': 'b'},
        ],
      },
    };

    for (final (name, widget) in [
      ('AI', ResearchReport(ai)),
      ('CFA', CfaReport(cfa)),
      ('Danh mục', PortfolioReport(newPortfolio('X'), pa)),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: widget),
            ),
          ),
        ),
      );
      await tester.pump();
      final row = find.byType(ScenarioRow);
      expect(row, findsOneWidget, reason: name);
      final rowWidget = tester.widget<Row>(find.descendant(of: row, matching: find.byType(Row)).first);
      final cards = [
        for (final c in rowWidget.children)
          if (c is Expanded) c,
      ];
      expect(cards.length, 3, reason: name);
      final rects = [for (final c in cards) tester.getRect(find.byWidget(c))];
      expect({for (final r in rects) r.width.toStringAsFixed(1)}.length, 1, reason: '$name: cùng rộng');
      expect({for (final r in rects) r.height.toStringAsFixed(1)}.length, 1, reason: '$name: cùng cao');
      expect(rects.first.left, tester.getTopLeft(row).dx, reason: name);
      expect(rects.last.right, closeTo(tester.getTopRight(row).dx, 0.5), reason: '$name: trải hết chiều ngang của khung');
      expect(tester.getTopRight(row).dx, greaterThan(w - 60), reason: '$name: khung kịch bản giãn gần hết cửa sổ');
      expect(tester.takeException(), isNull, reason: name);
    }
  });

  test('số cột lưới KPI báo cáo chọn để hàng cuối ít ô trống nhất', () {
    expect(ReportTileGrid.columnsFor(12, 6), 6);
    expect(ReportTileGrid.columnsFor(12, 7), 6, reason: '12 thẻ: 6 cột không thừa ô, hơn 7 cột thừa 2');
    expect(ReportTileGrid.columnsFor(14, 7), 7);
    expect(ReportTileGrid.columnsFor(12, 2), 2);
    expect(ReportTileGrid.columnsFor(12, 1), 1);
  });

  for (final w in [1900.0, 1100.0, 380.0]) {
    testWidgets('thẻ KPI báo cáo CFA và danh mục cùng rộng, cùng cao, trải hết khung (${w.toInt()} px)', (tester) async {
      tester.view.physicalSize = Size(w, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pa = _analysis();
      final cfa = {
        ...pa,
        'symbol': 'VCB',
        'series': {
          'dates': (pa['series'] as Map)['dates'],
          'stock': (pa['series'] as Map)['danh_muc'],
          'index': (pa['series'] as Map)['vnindex'],
        },
        'inputs': {
          'quant': {
            'loi_suat_nam': -0.036,
            'bien_dong_nam': 0.269,
            'sharpe': -0.3,
            'beta': 0.72,
            'sut_giam_toi_da': -0.283,
            'var95_1_ngay': 0.024,
          },
          'valuation': {
            'chi_phi_von_chu_so_huu_capm': 0.095,
            'pb_hien_tai': 1.89,
            'pb_chinh_dang': 2.51,
            'gia_noi_tai_uoc_tinh_nghin_dong': 75.9,
            'chenh_lech_so_voi_gia_pct': 32.7,
          },
        },
        'price': 57.2,
        'result': {'stance': 'Trung lập', 'confidence': 'Trung bình', 'headline': 'H', 'summary': 'S'},
      };
      for (final (name, widget) in [('CFA', CfaReport(cfa)), ('Danh mục', PortfolioReport(newPortfolio('X'), pa))]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(20), child: widget),
              ),
            ),
          ),
        );
        await tester.pump();
        final grid = find.byType(ReportTileGrid);
        expect(grid, findsOneWidget, reason: name);
        final tiles = find
            .descendant(of: grid, matching: find.byType(Container))
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .where((r) => r.height > 30)
            .toList();
        expect(tiles.length, name == 'CFA' ? 12 : 14, reason: name);
        expect({for (final r in tiles) r.width.toStringAsFixed(1)}.length, 1, reason: '$name: cùng rộng');
        expect({for (final r in tiles) r.height.toStringAsFixed(1)}.length, 1, reason: '$name: cùng cao');
        final gridRect = tester.getRect(grid);
        expect(tiles.map((r) => r.left).reduce((a, b) => a < b ? a : b), gridRect.left, reason: name);
        expect(
          tiles.map((r) => r.right).reduce((a, b) => a > b ? a : b),
          closeTo(gridRect.right, 0.6),
          reason: '$name: trải hết chiều ngang',
        );
        expect(tester.takeException(), isNull, reason: name);
      }
    });
  }

  testWidgets('ma trận tương quan danh mục to hơn và căn giữa khung', (tester) async {
    const w = 1500.0;
    tester.view.physicalSize = const Size(w, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pa = _analysis();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: PortfolioReport(newPortfolio('X'), pa)),
          ),
        ),
      ),
    );
    await tester.pump();
    final title = find.textContaining('Tương quan lợi suất ngày giữa các mã');
    expect(title, findsOneWidget);
    final cells = find.text('0,75'); // hai ô ngoài đường chéo của ma trận 2x2 (bộ test dùng tương quan 0,75)
    expect(cells, findsNWidgets(2));
    final boxes = [for (var i = 0; i < 2; i++) tester.getRect(find.ancestor(of: cells.at(i), matching: find.byType(Container)).first)];
    for (final r in boxes) {
      expect(r.width, greaterThanOrEqualTo(56), reason: 'ô rộng tối thiểu 56 px');
      expect(r.height, greaterThanOrEqualTo(50), reason: 'ô cao tối thiểu 50 px');
    }
    // Căn giữa: tâm các ô trùng tâm tiêu đề (cùng một khung) với sai số bằng nửa cột nhãn mã
    final center = (boxes[0].center.dx + boxes[1].center.dx) / 2;
    expect(center, closeTo(tester.getCenter(title).dx, 60), reason: 'ma trận nằm giữa khung');
    expect(tester.takeException(), isNull);
  });
}
