import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/dashboard.dart';
import 'package:vn_stock_insight/main.dart' show appTheme;
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/stock_dialog.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-dialog';
}

Future<AppState> _state(WidgetTester tester, double w, double h) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  PathProviderPlatform.instance = _FakePaths();
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState();
  await tester.runAsync(() => state.init(startDashboard: false));
  return state;
}

Future<void> _open(WidgetTester tester, AppState state, void Function(BuildContext) open, String label) async {
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: FilledButton(onPressed: () => open(c), child: Text(label)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200)); // dữ liệu nạp sau khung hình đầu
}

void main() {
  // Dữ liệu giảm dần có dao động: đủ để tính điểm sức khỏe, vùng giá và kịch bản
  List<Bar> series(double start, double step, int n, {double vol = 1e6}) => [
    for (var i = 0; i < n; i++)
      Bar(
        1760000000 + i * 86400,
        start + step * i + (i % 7),
        start + step * i + 2 + (i % 7),
        start + step * i - 1,
        start + step * i + 0.5 + (i % 5),
        vol + (i % 9) * 1e5,
      ),
  ];

  for (final (w, h) in [(1500.0, 1000.0), (1100.0, 800.0), (375.0, 760.0)]) {
    testWidgets('bấm vào cổ phiếu mở trang chi tiết đầy đủ, vừa khung ${w.toInt()}x${h.toInt()}', (tester) async {
      final state = await _state(tester, w, h);
      state.stocks = {'FPT': analyze('FPT', series(120, -0.12, 320))};
      await _open(tester, state, (c) => openStock(c, 'FPT'), 'Mở FPT');

      expect(find.text('Chi tiết cổ phiếu'), findsOneWidget);
      expect(find.text('FPT'), findsWidgets);
      for (final t in ['Điểm sức khỏe', 'Vùng giá và kịch bản', 'Kịch bản theo dõi']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.textContaining('Dấu hiệu tạo đáy ·'), findsOneWidget);
      for (final f in ['1 giờ', '4 giờ', 'Ngày', 'Tuần']) {
        expect(find.text(f), findsOneWidget, reason: 'khung $f');
      }
      for (final t in ['EMA20', 'MA50', 'MA200', 'Vùng giá', 'Fibonacci']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Phân tích AI'), findsWidgets);
      expect(find.byTooltip('Bỏ theo dõi'), findsOneWidget, reason: 'FPT có trong danh sách theo dõi mặc định');
      expect(tester.getSize(find.byTooltip('Bỏ theo dõi')).shortestSide, greaterThanOrEqualTo(44));
      // Bố cục: màn hình rộng có cột phải; màn hình hẹp xếp dọc
      final health = tester.getTopLeft(find.text('Điểm sức khỏe'));
      if (w >= 1000) {
        expect(health.dx, greaterThan(w * 0.6), reason: 'cột phải');
      } else {
        expect(health.dx, lessThan(w * 0.3), reason: 'xếp dọc');
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Chi tiết cổ phiếu'), findsNothing);
      expect(find.text('Mở FPT'), findsOneWidget, reason: 'màn hình trước vẫn còn');
      state.dash.dispose();
    });
  }

  testWidgets('đổi khung thời gian và bật tắt đường hỗ trợ/kháng cự, Fibonacci không lỗi', (tester) async {
    final state = await _state(tester, 1500, 1000);
    state.stocks = {'FPT': analyze('FPT', series(120, -0.12, 320))};
    await _open(tester, state, (c) => openStock(c, 'FPT'), 'Mở FPT');
    for (final f in ['Tuần', '4 giờ', '1 giờ', 'Ngày']) {
      await tester.tap(find.text(f));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 4 giờ / 1 giờ chưa có dữ liệu phút trong bộ test: báo rõ thay vì lỗi
    await tester.tap(find.text('1 giờ'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Chưa có đủ dữ liệu cho khung này'), findsOneWidget);
    await tester.tap(find.text('Ngày'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Fibonacci'));
    await tester.pump();
    await tester.tap(find.text('Vùng giá'));
    await tester.pump();
    await tester.tap(find.text('MACD'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    state.dash.dispose();
  });

  testWidgets('bấm vào chỉ số mở trang chi tiết chỉ số có giá, biên độ và thông tin phiên', (tester) async {
    final state = await _state(tester, 1280, 800);
    final bars = [
      for (var i = 0; i < 300; i++) Bar(1790000000 + i * 86400, 1700 + i * .1, 1710 + i * .1, 1690, 1700 + i * .1 + (i % 7), 1e8),
    ];
    state.dash.quotes = {'VNINDEX': IndexQuote(indexMetas.first, bars)};
    await _open(tester, state, (c) => openIndex(c, indexMetas.first), 'Mở chỉ số');
    expect(find.text('Chi tiết chỉ số'), findsOneWidget);
    expect(find.text('VNINDEX'), findsWidgets);
    expect(find.text('THÔNG TIN PHIÊN'), findsOneWidget);
    expect(find.text('Phân tích AI'), findsNothing, reason: 'chỉ số không có phân tích AI');
    expect(find.text('Điểm sức khỏe'), findsOneWidget);
    expect(find.textContaining('▲'), findsWidgets);
    expect(tester.takeException(), isNull);
    state.dash.dispose();
  });
}
