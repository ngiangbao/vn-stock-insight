import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart' show appTheme;
import 'package:vn_stock_insight/services/cfa.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/analysis_report.dart';
import 'package:vn_stock_insight/ui/cfa_page.dart';
import 'package:vn_stock_insight/ui/cfa_report.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-cfa';
  @override
  Future<String?> getDownloadsPath() async => '/tmp/vnsi-test-cfa-downloads';
}

Map<String, dynamic> _record({String symbol = 'HPG', DateTime? at}) {
  final now = at ?? DateTime.now();
  final dates = [for (var i = 0; i < 120; i++) DateTime.utc(2026, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10)];
  return {
    'id': '${now.millisecondsSinceEpoch}-$symbol',
    'symbol': symbol,
    'name': 'CTCP Tập đoàn Hòa Phát',
    'sector': 'Vật liệu xây dựng',
    'day': '2026-10-29',
    'created_at': now.toIso8601String(),
    'ai': 'test',
    'price': 26.45,
    'assumptions': {'rf': 0.045, 'erp': 0.07, 'g': 0.04},
    'inputs': {
      'quant': {
        'so_phien': 252,
        'loi_suat_nam': 0.21,
        'loi_suat_vnindex_nam': 0.12,
        'bien_dong_nam': 0.31,
        'bien_dong_vnindex_nam': 0.18,
        'sharpe': 0.54,
        'sortino': 0.8,
        'sut_giam_toi_da': -0.27,
        'sut_giam_hien_tai': -0.05,
        'var95_1_ngay': 0.031,
        'cvar95_1_ngay': 0.045,
        'do_lech_skew': -0.2,
        'kurtosis_vuot_chuan': 1.4,
        'beta': 1.22,
        'alpha_jensen_nam': 0.03,
        'tuong_quan_vnindex': 0.71,
        'r_binh_phuong': 0.5,
        'tracking_error': 0.2,
        'information_ratio': 0.45,
        'capture_tang': 1.1,
        'capture_giam': 1.2,
        'dong_luong_12_1': 0.15,
      },
      'valuation': {
        'chi_phi_von_chu_so_huu_capm': 0.1304,
        'pb_hien_tai': 1.6,
        'pb_chinh_dang': 1.9,
        'gia_noi_tai_uoc_tinh_nghin_dong': 31.4,
        'chenh_lech_so_voi_gia_pct': 18.7,
        'dupont': {'roe': 0.12, 'bien_loi_nhuan_rong': 0.08, 'vong_quay_tai_san_suy_ra': 0.75, 'don_bay_tai_chinh_xap_xi': 2.0},
        'bang_do_nhay': [
          for (final k in [0.1204, 0.1304, 0.1404])
            for (final g in [0.03, 0.04, 0.05]) {'chi_phi_von': k, 'tang_truong': g, 'pb_chinh_dang': 1.9, 'gia_nghin_dong': 31.4},
        ],
        'ghi_chu': ['Ghi chú định giá'],
      },
    },
    'series': {
      'dates': dates,
      'stock': [for (var i = 0; i < 120; i++) i * 0.2],
      'index': [for (var i = 0; i < 120; i++) i * 0.1 - 3],
    },
    'result': {
      'stance': 'Tích cực',
      'confidence': 'Vừa',
      'headline': 'Chất lượng tốt, định giá hợp lý',
      'summary': 'Tóm tắt ' * 25,
      'ethics': 'Giới hạn ' * 10,
      'economics': {
        'context': 'Bối cảnh ' * 8,
        'implications': ['Tác động một', 'Tác động hai'],
      },
      'fsa': {
        'summary': 'KQKD ' * 10,
        'dupont': 'DuPont ' * 8,
        'earnings_quality': 'Chất lượng ' * 6,
        'red_flags': ['Cờ đỏ một'],
      },
      'corporate': {'capital_structure': 'Vốn ' * 10, 'cost_of_capital': 'WACC ' * 6, 'governance': 'Quản trị ' * 6},
      'quant': {
        'summary': 'Định lượng ' * 10,
        'risk_return': 'RR ' * 10,
        'regression': 'Hồi quy ' * 6,
        'tail_risk': 'Đuôi ' * 6,
        'cautions': ['Mẫu 1 năm'],
      },
      'valuation': {
        'summary': 'Định giá ' * 10,
        'intrinsic_view': 'Nội tại ' * 6,
        'margin_of_safety': 'Biên ' * 5,
        'sensitivity': 'Nhạy ' * 5,
        'cross_check': 'Đối chiếu ' * 5,
      },
      'portfolio': {
        'role': 'Vai trò ' * 6,
        'diversification': 'Đa dạng ' * 6,
        'risk_budget': 'Ngân sách ' * 5,
        'behavioral_biases': ['Neo giá'],
        'suitability': 'Phù hợp ' * 6,
      },
      'scenarios': [
        for (final (n, p) in [('Tích cực', 30), ('Cơ sở', 50), ('Tiêu cực', 20)])
          {'name': n, 'probability': p, 'condition': 'Điều kiện $n', 'price_effect': 'Giá $n', 'signals': 'Tín hiệu $n'},
      ],
      'monitoring': ['Theo dõi một'],
      'risks': ['Rủi ro một'],
      'data_gaps': ['Thiếu dữ liệu dòng tiền khối ngoại', 'Thiếu so sánh cùng ngành'],
    },
  };
}

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false, 'flutter.autoScale': false});
  FlutterSecureStorage.setMockInitialValues({});
  PathProviderPlatform.instance = _FakePaths();
  final dir = Directory('/tmp/vnsi-test-cfa');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final state = AppState();
  await tester.runAsync(() => state.init(startDashboard: false));
  return state;
}

void main() {
  test('CfaStore lưu và nạp lại, xóa theo id, giữ tối đa số bản quy định', () async {
    final dir = await Directory.systemTemp.createTemp('cfa');
    final file = File('${dir.path}/cfa_reports.json');
    final store = CfaStore(file);
    await store.add(_record(symbol: 'FPT', at: DateTime(2026, 10, 1)));
    await store.add(_record(symbol: 'HPG', at: DateTime(2026, 10, 2)));
    expect(store.reports.first['symbol'], 'HPG');
    final again = CfaStore(file);
    await again.load();
    expect(again.reports.map((r) => r['symbol']), ['HPG', 'FPT']);
    await again.remove(again.reports.first['id'] as String);
    final third = CfaStore(file);
    await third.load();
    expect(third.reports.length, 1);
    for (var i = 0; i < CfaStore.maxReports + 5; i++) {
      await third.add(
        _record(
          symbol: 'AAA',
          at: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }
    expect(third.reports.length, CfaStore.maxReports);
    await dir.delete(recursive: true);
  });

  for (final w in [1100.0, 700.0, 360.0]) {
    testWidgets('báo cáo CFA hiển thị đủ phần, không tràn (${w.toInt()} px)', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: CfaReport(_record())),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final t in [
        '1. Phương pháp định lượng',
        '2. Kinh tế học',
        '5. Định giá cổ phiếu',
        '6. Quản lý danh mục',
        '7. Kịch bản có xác suất',
      ]) {
        expect(find.text(t.toUpperCase()), findsOneWidget, reason: t);
      }
      expect(find.text('CHẤT LƯỢNG TỐT, ĐỊNH GIÁ HỢP LÝ'), findsOneWidget);
      expect(find.textContaining('Giả định: lãi suất phi rủi ro 4,5%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tab CFA: biểu mẫu kiểm tra mã, lưới bản đã lưu, xem báo cáo và xuất PDF', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _state(tester);
    await tester.runAsync(() => state.cfa.add(_record()));
    final out = File('/tmp/vnsi-test-cfa-downloads/cfa-HPG-2026-10-29.pdf');
    if (out.existsSync()) out.deleteSync();

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: ThemeMode.dark,
          home: const CfaPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 bản phân tích, 0 danh mục lưu trên máy'), findsOneWidget);
    expect(find.text('Chọn cổ phiếu cần phân tích'), findsOneWidget);

    // Mã sai: báo lỗi, không gọi AI
    await tester.tap(find.widgetWithText(FilledButton, 'Phân tích CFA'));
    await tester.pump();
    expect(find.textContaining('3 đến 5 ký tự'), findsOneWidget);

    expect(tester.takeException(), isNull, reason: 'form');
    await tester.tap(find.widgetWithText(Tab, 'Đã lưu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('HPG'), findsOneWidget);
    expect(find.text('Chất lượng tốt, định giá hợp lý'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'grid');
    expect(find.text('Xem báo cáo'), findsOneWidget);
    for (final tip in ['Xuất PDF', 'Xóa bản lưu']) {
      final btn = find.byTooltip(tip);
      expect(btn, findsOneWidget);
      expect(tester.getSize(btn).shortestSide, greaterThanOrEqualTo(48), reason: tip);
    }

    await tester.tap(find.text('Xem báo cáo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'report page');
    expect(find.text('CFA · HPG'), findsOneWidget);
    expect(find.text('7. KỊCH BẢN CÓ XÁC SUẤT'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Xuất PDF'));
    await tester.pump();
    for (var i = 0; i < 60 && find.text('Đang xuất…').evaluate().isNotEmpty || !out.existsSync(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (i > 55) break;
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(out.existsSync(), isTrue);
    expect(String.fromCharCodes(out.readAsBytesSync().take(5)), '%PDF-');
    // Giao diện đang tối nhưng PDF phải in chữ đậm trên nền trắng (không bị chữ sáng trên nền trắng)
    if (Process.runSync('which', ['pdftoppm']).exitCode == 0) {
      final ppm = Process.runSync('pdftoppm', [
        '-r',
        '40',
        '-f',
        '1',
        '-l',
        '1',
        '-gray',
        out.path,
        '/tmp/vnsi-test-cfa-page',
      ], stdoutEncoding: null);
      expect(ppm.exitCode, 0);
      final img = File('/tmp/vnsi-test-cfa-page-1.pgm').existsSync()
          ? File('/tmp/vnsi-test-cfa-page-1.pgm')
          : File('/tmp/vnsi-test-cfa-page-01.pgm');
      final px = img.readAsBytesSync().skip(15).toList();
      final dark = px.where((v) => v < 100).length / px.length;
      final white = px.where((v) => v > 240).length / px.length;
      expect(white, greaterThan(0.5), reason: 'nền trắng');
      expect(dark, greaterThan(0.01), reason: 'có chữ tối');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('các nút phân tích sâu hơn (ngành, cùng ngành, dòng tiền...) thay cho nút khắc phục hạn chế', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    final rec = {
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
        'data_gaps': ['Thiếu dòng tiền khối ngoại'],
      },
    };
    Widget host(Map<String, dynamic> r, {String? busy}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ResearchReport(r, onExtra: picked.add, extraBusy: busy),
        ),
      ),
    );
    await tester.pumpWidget(host(rec));
    await tester.pump();
    expect(find.text('Khắc phục tất cả hạn chế'), findsNothing, reason: 'đã bỏ nút khắc phục hạn chế dữ liệu');
    for (final label in [
      'Phân tích chuyển động ngành',
      'Phân tích các cổ phiếu cùng ngành',
      'Phân tích dòng tiền',
      'Phân tích tác động vĩ mô',
    ]) {
      final btn = find.widgetWithText(OutlinedButton, label);
      expect(btn, findsOneWidget, reason: label);
      expect(tester.getSize(btn).height, greaterThanOrEqualTo(48), reason: label);
    }
    await tester.ensureVisible(find.text('Phân tích chuyển động ngành'));
    await tester.tap(find.text('Phân tích chuyển động ngành'));
    await tester.tap(find.text('Phân tích các cổ phiếu cùng ngành'));
    expect(picked, ['sector', 'peers']);

    // Đang chạy một chủ đề: nút khóa và hiện trạng thái
    await tester.pumpWidget(host(rec, busy: 'sector'));
    await tester.pump();
    expect(find.text('Đang phân tích…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Phân tích dòng tiền')).onPressed, isNull);

    // Đã có kết quả: hiển thị dưới nút, nút ghi "làm lại"
    final withExtras = {
      ...rec,
      'extras': {
        'sector': {
          'created_at': DateTime.now().toIso8601String(),
          'ai': 'test',
          'result': {
            'headline': 'Ngành ngân hàng hút tiền',
            'summary': 'Tóm tắt ngành',
            'findings': [
              {'title': 'Dòng tiền vào', 'detail': 'Chi tiết', 'evidence': 'Giá trị 1.200 tỷ'},
            ],
            'metrics': [
              {'label': 'Biến động hôm nay', 'value': '+1,2%', 'note': 'theo vốn hóa'},
            ],
            'implication': 'Ủng hộ nhận định',
            'watch_points': ['Theo dõi khối ngoại'],
            'limits': ['Thiếu chỉ số ngành chính thức'],
          },
        },
      },
    };
    await tester.pumpWidget(host(withExtras));
    await tester.pump();
    expect(find.text('CHUYỂN ĐỘNG NGÀNH'), findsOneWidget);
    expect(find.text('Ngành ngân hàng hút tiền'), findsOneWidget);
    expect(find.text('Phân tích chuyển động ngành (làm lại)'), findsOneWidget);
    expect(find.textContaining('Ảnh hưởng đến nhận định'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lưu phân tích bổ sung vào lịch sử nhận định', (tester) async {
    final state = await _state(tester);
    final rec = {
      'symbol': 'FPT',
      'created_at': DateTime.now().toIso8601String(),
      'ai': 'test',
      'inputs': <String, dynamic>{},
      'result': {'stance': 'Trung lập'},
    };
    state.rememberAnalysis('FPT', rec);
    state.analyses['FPT'] = rec;
    final day = vietnamDayKey(DateTime.now());
    await tester.runAsync(
      () => state.saveExtra('FPT', day, 'sector', {
        'result': {'headline': 'x'},
      }),
    );
    await tester.runAsync(
      () => state.saveExtra('FPT', day, 'peers', {
        'result': {'headline': 'y'},
      }),
    );
    expect((state.analyses['FPT']!['extras'] as Map).keys, containsAll(['sector', 'peers']));
    expect((state.historyFor('FPT').first.$2['extras'] as Map).keys, containsAll(['sector', 'peers']));
  });
}
