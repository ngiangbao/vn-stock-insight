import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart' show StockApp, appTheme;
import 'package:vn_stock_insight/services/macro.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/macro_chart.dart';
import 'package:vn_stock_insight/ui/macro_page.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test';
}

// ---------- Dữ liệu mẫu giống định dạng thật của từng nguồn ----------
String wbBody() => jsonEncode([
      {'page': 1},
      [
        {'date': '2025', 'value': 8.0},
        {'date': '2024', 'value': 7.1},
        {'date': '2023', 'value': null},
        {'date': '2022', 'value': 8.5},
      ],
    ]);

String imfBody(String code) => jsonEncode({
      'values': {
        code: {
          'VNM': {'2023': 5.0, '2024': 7.1, '2025': 8.0, '2026': 6.5, '2027': 6.0},
        },
      },
    });

String yahooBody() {
  final times = [for (var i = 0; i < 22; i++) DateTime.utc(2025, 1 + i, 1).millisecondsSinceEpoch ~/ 1000];
  final closes = [for (var i = 0; i < 22; i++) i == 3 ? null : 25000.0 + i * 50];
  return jsonEncode({
    'chart': {
      'result': [
        {
          'timestamp': times,
          'indicators': {
            'quote': [
              {'close': closes},
            ],
          },
        },
      ],
    },
  });
}

/// Máy chủ giả: trả dữ liệu mẫu cho cả ba nguồn; [fail] quyết định yêu cầu nào bị lỗi 500.
class FakeSources {
  int calls = 0;
  final agents = <String, Set<String>>{}; // máy chủ → các User-Agent đã gửi
  bool Function(Uri url) fail = (_) => false;

  http.Client get client => MockClient((req) async {
        calls++;
        (agents[req.url.host] ??= {}).add(req.headers['User-Agent'] ?? '');
        if (fail(req.url)) return http.Response('lỗi', 500);
        return switch (req.url.host) {
          'api.worldbank.org' => http.Response(wbBody(), 200),
          'www.imf.org' => http.Response(imfBody(req.url.pathSegments[req.url.pathSegments.length - 2]), 200),
          'query1.finance.yahoo.com' => http.Response(yahooBody(), 200),
          _ => http.Response('không có', 404),
        };
      });
}

MacroSeries series(String id, List<(String, double, bool)> pts) =>
    MacroSeries(macroDef(id), [for (final (p, v, f) in pts) MacroPoint(p, v, forecast: f)]);

double contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  group('đọc dữ liệu từ các nguồn', () {
    test('World Bank: bỏ giá trị null, sắp tăng dần, nhân tỉ lệ', () {
      final pts = parseWorldBank(wbBody(), scale: 10);
      expect([for (final p in pts) p.period], ['2022', '2024', '2025']);
      expect(pts.last.value, 80.0);
      expect(pts.any((p) => p.forecast), isFalse);
    });

    test('IMF: từ năm hiện tại trở đi là dự báo', () {
      final pts = parseImf(imfBody('X'), 'X', firstForecastYear: 2026);
      expect([for (final p in pts) p.forecast], [false, false, false, true, true]);
      expect(pts.first.period, '2023');
      expect(parseImf('{}', 'X', firstForecastYear: 2026), isEmpty);
    });

    test('Yahoo: kỳ theo tháng, bỏ tháng thiếu giá', () {
      final pts = parseYahooMonthly(yahooBody());
      expect(pts.length, 21);
      expect(pts.first.period, '2025-01');
      expect(pts.first.label, '01/2025');
      expect(pts.any((p) => p.period == '2025-04'), isFalse);
    });

    test('cửa sổ thời gian giữ dự báo và tính kỳ mới nhất theo số liệu thực', () {
      final s = series('gdp_growth', [
        for (var y = 1990; y <= 2025; y++) ('$y', y.toDouble(), false),
        ('2026', 6.5, true),
        ('2027', 6.0, true),
      ]);
      expect(s.latest!.period, '2025');
      expect(s.previous!.period, '2024');
      expect(s.window(5).map((p) => p.period).first, '2021');
      expect(s.window(5).last.period, '2027');
      expect(s.window(0).length, s.points.length);
    });
  });

  group('tải và lưu đệm', () {
    late Directory tmp;
    late File cache;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('macro-test');
      cache = File('${tmp.path}/macro_cache.json');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('lần đầu tải đủ rồi lưu đệm; trong 12 giờ không tải lại', () async {
      final src = FakeSources();
      var now = DateTime.utc(2026, 10, 29, 5);
      final repo = MacroRepository(cacheFile: cache, client: src.client, now: () => now);

      final first = await repo.load();
      expect(first.series.length, macroDefs.length);
      expect(first.failed, isEmpty);
      expect(first.fromCache, isFalse);
      expect(src.calls, macroDefs.length);
      expect(cache.existsSync(), isTrue);
      // IMF: 2026 là dự báo vì năm hiện tại (giả lập) là 2026
      expect(first.series['gdp_growth']!.points.where((p) => p.forecast).map((p) => p.period), ['2026', '2027']);

      now = now.add(const Duration(hours: 1));
      final second = await repo.load();
      expect(src.calls, macroDefs.length, reason: 'không gọi mạng khi bản lưu đệm còn mới');
      expect(second.fromCache, isTrue);
      expect(second.series['usdvnd']!.points.length, 21);
    });

    test('User-Agent đúng từng nguồn: IMF chặn "Mozilla/…" (lỗi gặp khi thử với mạng thật), Yahoo cần dạng trình duyệt', () async {
      final src = FakeSources();
      await MacroRepository(client: src.client).load();
      expect(src.agents['www.imf.org']!.single, isNot(startsWith('Mozilla')));
      expect(src.agents['api.worldbank.org']!.single, isNot(startsWith('Mozilla')));
      expect(src.agents['query1.finance.yahoo.com']!.single, startsWith('Mozilla'));
    });

    test('một nguồn lỗi thì giữ bản lưu đệm cũ của chỉ tiêu đó', () async {
      final src = FakeSources();
      var now = DateTime.utc(2026, 10, 29, 5);
      final repo = MacroRepository(cacheFile: cache, client: src.client, now: () => now);
      await repo.load();

      now = now.add(const Duration(hours: 13));
      src.fail = (u) => u.host == 'www.imf.org';
      final snap = await repo.load();
      expect(snap.failed, isEmpty);
      expect(snap.series['inflation'], isNotNull);
      expect(snap.fromCache, isFalse, reason: 'các nguồn còn lại đã được làm mới');
    });

    test('không có mạng và chưa có bản lưu đệm: báo lỗi từng chỉ tiêu, không văng lỗi', () async {
      final src = FakeSources()..fail = (_) => true;
      final snap = await MacroRepository(cacheFile: cache, client: src.client).load();
      expect(snap.series, isEmpty);
      expect(snap.failed.length, macroDefs.length);
      expect(cache.existsSync(), isFalse);
    });

    test('file lưu đệm hỏng thì tải lại bình thường', () async {
      cache.writeAsStringSync('không phải json');
      final snap = await MacroRepository(cacheFile: cache, client: FakeSources().client).load();
      expect(snap.series.length, macroDefs.length);
    });
  });

  group('biểu đồ', () {
    Future<void> pumpChart(WidgetTester tester, MacroSeries s, {int? years, double w = 420, double h = 260, Brightness b = Brightness.light}) {
      return tester.pumpWidget(MaterialApp(
        theme: appTheme(b),
        home: Scaffold(body: Center(child: SizedBox(width: w, height: h, child: MacroChart(s, years: years)))),
      ));
    }

    testWidgets('vẽ được mọi dạng dữ liệu ở cả hai chế độ sáng/tối', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final monthly = series('usdvnd', [for (var i = 0; i < 276; i++) ('${2003 + i ~/ 12}-${(i % 12 + 1).toString().padLeft(2, '0')}', 15000 + i * 40.0, false)]);
      final cases = {
        'có dự báo': series('gdp_growth', [('2023', 5.0, false), ('2024', 7.1, false), ('2025', 8.0, false), ('2026', 6.5, true), ('2027', 6.0, true)]),
        'cắt qua số 0': series('trade_balance', [('2019', 4.0, false), ('2020', -1.5, false), ('2021', -3.0, false), ('2022', 2.0, false)]),
        'theo tháng, 276 điểm': monthly,
        'chỉ hai điểm': series('gdp_pc', [('2024', 4500, false), ('2025', 4800, false)]),
        'hằng số': series('inflation', [('2023', 3.0, false), ('2024', 3.0, false), ('2025', 3.0, false)]),
        'chỉ có dự báo sau điểm cuối': series('inflation', [('2025', 3.3, false), ('2026', 3.6, true)]),
      };
      for (final b in Brightness.values) {
        for (final e in cases.entries) {
          await pumpChart(tester, e.value, b: b, years: e.key.contains('tháng') ? 10 : null);
          expect(tester.takeException(), isNull, reason: '${e.key} / ${b.name}');
        }
      }
    });

    testWidgets('phím mũi tên, Home, End, Esc chọn kỳ và cập nhật mô tả cho trình đọc màn hình', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final s = series('gdp_growth', [('2023', 5.0, false), ('2024', 7.1, false), ('2025', 8.0, false), ('2026', 6.5, true), ('2027', 6.0, true)]);
      await pumpChart(tester, s);

      final node = find.byType(MacroChart);
      SemanticsNode sem() => tester.getSemantics(node);
      expect(sem().label, contains('Tăng trưởng GDP thực'));
      expect(sem().label, contains('Mới nhất 8 %, kỳ 2025'));
      expect(sem().label, contains('Dự báo 2027'));
      expect(sem().value, isEmpty);

      await tester.tap(node); // chạm: nhận focus và chọn kỳ gần nhất
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(sem().value, contains('2027'));
      expect(sem().value, contains('dự báo'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(sem().value, contains('2026'));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(sem().value, contains('2023'));
      expect(sem().value, isNot(contains('dự báo')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(sem().value, isEmpty);
      handle.dispose();
    });

    testWidgets('rê chuột hiện tooltip và rời đi thì ẩn', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      await pumpChart(tester, series('gdp_growth', [('2023', 5.0, false), ('2024', 7.1, false), ('2025', 8.0, false)]));
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      await g.moveTo(tester.getCenter(find.byType(MacroChart)));
      await tester.pump();
      expect(tester.getSemantics(find.byType(MacroChart)).value, isNotEmpty);
      await g.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(tester.getSemantics(find.byType(MacroChart)).value, isEmpty);
      handle.dispose();
    });

    test('tóm tắt bằng lời nêu hướng thay đổi và đơn vị điểm phần trăm', () {
      final s = series('inflation', [('2023', 3.2, false), ('2024', 3.6, false), ('2025', 3.3, false)]);
      final t = macroSummary(s);
      expect(t, contains('So với 2024: giảm 0,3 điểm %'));
      expect(t, contains('Cao nhất 3,6 (2024), thấp nhất 3,2 (2023)'));
    });
  });

  group('trang Vĩ mô', () {
    Future<void> pumpPage(WidgetTester tester, FakeSources src, {Size size = const Size(1400, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: appTheme(Brightness.light),
        home: Scaffold(body: MacroPage(repository: MacroRepository(client: src.client))),
      ));
    }

    testWidgets('hiện trạng thái đang tải, sau đó đủ thẻ; mọi thẻ cùng kích thước', (tester) async {
      final src = FakeSources();
      await pumpPage(tester, src);
      expect(find.text('Đang tải số liệu…'), findsWidgets);
      await tester.pumpAndSettle();

      expect(find.text('Kinh tế vĩ mô'), findsOneWidget);
      for (final t in macroTabs) {
        expect(find.text(t.title), findsOneWidget);
      }
      final cards = find.byType(MacroCard);
      expect(cards, findsNWidgets(macroTabs.first.ids.length));
      final sizes = {for (var i = 0; i < macroTabs.first.ids.length; i++) tester.getSize(cards.at(i))};
      expect(sizes.length, 1, reason: 'các thẻ phải cùng chiều rộng và chiều cao');
      expect(find.textContaining('Kỳ báo cáo: Hàng năm'), findsWidgets);
      expect(find.textContaining('Kỳ báo cáo: Hàng tháng'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chuyển tab, đổi khoảng thời gian, mở bảng số liệu', (tester) async {
      await pumpPage(tester, FakeSources());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thương mại'));
      await tester.pumpAndSettle();
      expect(find.text('Xuất khẩu hàng hóa và dịch vụ'), findsOneWidget);

      await tester.tap(find.text('5 năm'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '5 năm')).selected, isTrue);

      await tester.tap(find.byTooltip('Xem bảng số liệu').first);
      await tester.pumpAndSettle();
      expect(find.text('Thực tế'), findsWidgets);
      expect(find.text('Đóng'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('Đóng'), findsNothing);
    });

    testWidgets('tab dự báo ghi rõ nguồn IMF và có nhãn Dự báo trong bảng số liệu', (tester) async {
      await pumpPage(tester, FakeSources());
      await tester.pumpAndSettle();
      await tester.tap(find.text('GDP'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nguồn: IMF, gồm dự báo'), findsWidgets);
      await tester.tap(find.byTooltip('Xem bảng số liệu').first);
      await tester.pumpAndSettle();
      expect(find.text('Dự báo'), findsWidgets);
    });

    testWidgets('không tải được: báo lỗi rõ ràng và cho thử lại', (tester) async {
      final src = FakeSources()..fail = (_) => true;
      await pumpPage(tester, src);
      await tester.pumpAndSettle();
      expect(find.textContaining('Không tải được ${macroDefs.length} chỉ tiêu'), findsOneWidget);
      expect(find.text('Chưa tải được số liệu này'), findsWidgets);

      src.fail = (_) => false;
      await tester.tap(find.text('Thử lại').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Không tải được'), findsNothing);
      expect(find.byType(MacroCard), findsWidgets);
    });

    testWidgets('không tràn bố cục ở điện thoại 375 px, ngang và máy tính', (tester) async {
      for (final size in const [Size(375, 812), Size(812, 375), Size(768, 1024), Size(1920, 1080)]) {
        await pumpPage(tester, FakeSources(), size: size);
        await tester.pumpAndSettle();
        for (final t in macroTabs) {
          await tester.tap(find.text(t.title));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${t.title} ở ${size.width.toInt()}x${size.height.toInt()}');
        }
      }
    });

    testWidgets('mục tiêu chạm tối thiểu 44 px: tab, nút làm mới, nút bảng số liệu, chip khoảng thời gian', (tester) async {
      await pumpPage(tester, FakeSources(), size: const Size(375, 812));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.widgetWithText(Tab, 'GDP')).height, greaterThanOrEqualTo(44), reason: 'tab');
      expect(tester.getSize(find.byTooltip('Làm mới số liệu')).shortestSide, greaterThanOrEqualTo(44), reason: 'nút làm mới');
      expect(tester.getSize(find.byTooltip('Xem bảng số liệu').first).shortestSide, greaterThanOrEqualTo(44), reason: 'nút bảng số liệu');
      expect(tester.getSize(find.widgetWithText(ChoiceChip, '10 năm')).height, greaterThanOrEqualTo(44), reason: 'chip khoảng thời gian');
    });
  });

  group('độ tương phản màu (skill: chữ ≥ 4.5:1, đồ họa ≥ 3:1), kiểm tra độc lập từng chế độ', () {
    for (final b in Brightness.values) {
      test('chế độ ${b == Brightness.dark ? 'tối' : 'sáng'}', () {
        final theme = appTheme(b);
        final cs = theme.colorScheme;
        final card = theme.cardTheme.color!;
        expect(contrast(cs.onSurface, card), greaterThanOrEqualTo(4.5), reason: 'chữ chính trên thẻ');
        expect(contrast(cs.onSurfaceVariant, card), greaterThanOrEqualTo(4.5), reason: 'chữ phụ, nhãn trục trên thẻ');
        expect(contrast(cs.inverseSurface, cs.onInverseSurface), greaterThanOrEqualTo(4.5), reason: 'chữ trong tooltip');
        expect(contrast(cs.errorContainer, cs.onErrorContainer), greaterThanOrEqualTo(4.5), reason: 'banner lỗi');
        expect(contrast(cs.primary, card), greaterThanOrEqualTo(3.0), reason: 'đường biểu đồ và viền focus');
        final bar = theme.appBarTheme;
        final titleColor = bar.titleTextStyle?.color;
        expect(titleColor, isNotNull, reason: 'tiêu đề thanh trên phải có màu chữ rõ ràng');
        expect(contrast(titleColor!, bar.backgroundColor!), greaterThanOrEqualTo(4.5), reason: 'tiêu đề thanh trên');
      });
    }
  });

  group('điều hướng', () {
    Future<AppState> pumpApp(WidgetTester tester, Size size) async {
      SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false, 'flutter.autoScale': false});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.runAsync(() => state.init(startDashboard: false));
      await tester.pumpWidget(AppScope(state: state, child: const StockApp()));
      await tester.pump(const Duration(milliseconds: 300));
      return state;
    }

    const labels = ['Tổng quan', 'Theo dõi', 'Bộ lọc', 'CFA', 'Trái phiếu', 'Chứng chỉ quỹ', 'Phái sinh'];

    testWidgets('cửa sổ vừa (900 px): thanh bên có 7 mục tài sản và menu ẩn, chọn Vĩ mô hiện trang Kinh tế vĩ mô', (tester) async {
      await pumpApp(tester, const Size(900, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      for (final l in labels) {
        expect(find.descendant(of: find.byType(NavigationRail), matching: find.text(l)), findsOneWidget, reason: l);
      }
      double y(String l) => tester.getCenter(find.descendant(of: find.byType(NavigationRail), matching: find.text(l))).dy;
      expect(y('Bộ lọc'), lessThan(y('CFA')));
      expect(y('CFA'), lessThan(y('Trái phiếu')));
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('CFA')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Phân tích theo khung CFA'), findsOneWidget);
      expect(find.text('Chọn cổ phiếu cần phân tích'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
      await tester.pump();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Vĩ mô'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Kinh tế vĩ mô'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('màn hình rộng (1400 px): menu ẩn mở Vĩ mô', (tester) async {
      await pumpApp(tester, const Size(1400, 900));
      expect(find.byType(NavigationRail), findsNothing);
      for (final l in labels) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      double x(String l) => tester.getCenter(find.text(l).first).dx;
      expect(x('Bộ lọc'), lessThan(x('CFA')));
      expect(x('CFA'), lessThan(x('Trái phiếu')));
      await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
      await tester.pump();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Vĩ mô'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Kinh tế vĩ mô'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('điện thoại: thanh dưới tối đa 5 mục có CFA, Vĩ mô, Tin tức và Cài đặt nằm trong "Thêm"', (tester) async {
      await pumpApp(tester, const Size(375, 812));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations.length, lessThanOrEqualTo(5));

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('CFA')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Phân tích theo khung CFA'), findsOneWidget);

      Future<void> openMore() async {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Thêm')));
        // Hoạt ảnh hộp thoại chỉ bắt đầu ở khung hình sau khi dựng, nên cần hai lần pump (spinner của trang Tổng quan chạy mãi nên không dùng pumpAndSettle)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }

      await openMore();
      expect(find.widgetWithText(ListTile, 'Vĩ mô'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Vĩ mô'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Kinh tế vĩ mô'), findsOneWidget);

      await openMore();
      expect(find.widgetWithText(ListTile, 'Tin tức'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Cài đặt'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(ListTile, 'Cài đặt')).height, greaterThanOrEqualTo(48), reason: 'mục trong "Thêm"');
      await tester.tap(find.widgetWithText(ListTile, 'Cài đặt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Giao diện'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
