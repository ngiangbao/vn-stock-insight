import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/dashboard.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/stock_dialog.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-dialog';
}

void main() {
  indexDialogTest();
  for (final (w, h) in [(1280.0, 800.0), (375.0, 760.0)]) {
    testWidgets('pop-up cổ phiếu hiện trên màn hình cũ, vừa khung ${w.toInt()}x${h.toInt()}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.runAsync(() => state.init(startDashboard: false));
      final bars = [for (var i = 0; i < 300; i++) Bar(1790000000 + i * 86400, 50 + i * .1, 52 + i * .1, 49 + i * .1, 51 + i * .1 + (i % 5), 1e6)];
      state.stocks = {'FPT': analyze('FPT', bars)};

      await tester.pumpWidget(AppScope(
        state: state,
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => openStock(c, 'FPT'), child: const Text('Mở FPT')))),
          ),
        ),
      ));
      await tester.tap(find.text('Mở FPT'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100)); // dữ liệu nạp sau khung hình đầu
      expect(find.text('FPT'), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
      final size = tester.getSize(find.byType(Dialog));
      expect(size.width, greaterThan(w * 0.9), reason: 'pop-up gần phủ hết chiều rộng cửa sổ');
      expect(size.height, greaterThan(h * 0.9), reason: 'pop-up gần phủ hết chiều cao cửa sổ');
      expect(find.byTooltip('Đóng'), findsOneWidget);
      expect(find.byTooltip('Thêm vào danh sách theo dõi'), findsNothing, reason: 'FPT đã có trong danh sách theo dõi mặc định');
      if (w > 800) {
        expect(find.text('CHỈ SỐ CƠ BẢN'), findsOneWidget);
        expect(find.text('Phân tích AI'), findsOneWidget);
      }
      expect(find.text('1D'), findsNothing);
      expect(find.text('1W'), findsNothing);
      // Nút Phân tích AI và Đóng ở góc phải trên; giá và biên độ ngang hàng nhau; tên công ty luôn hiện
      final close = tester.getTopLeft(find.byTooltip('Đóng'));
      expect(close.dx, greaterThan(w * 0.8), reason: 'nút đóng ở góc phải');
      expect(close.dy, lessThan(80));
      final ai = tester.getTopLeft(find.byTooltip('Phân tích AI').evaluate().isNotEmpty ? find.byTooltip('Phân tích AI') : find.text('Phân tích AI'));
      expect(ai.dx, lessThan(close.dx));
      expect(ai.dx, greaterThan(w * 0.6));
      final priceText = find.textContaining('.').evaluate().map((e) => e.widget).whereType<Text>().firstWhere((t) => (t.data ?? '').length >= 5 && !(t.data ?? '').contains(' '));
      final priceY = tester.getCenter(find.text(priceText.data!).first).dy;
      final ampY = tester.getCenter(find.textContaining('▲').evaluate().isNotEmpty ? find.textContaining('▲').first : find.textContaining('▼').first).dy;
      expect((priceY - ampY).abs(), lessThan(14), reason: 'giá và biên độ cùng một hàng');
      for (final t in ['Đóng', 'Bỏ theo dõi']) {
        expect(tester.getSize(find.byTooltip(t)).shortestSide, greaterThanOrEqualTo(44), reason: t);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Đóng'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Mở FPT'), findsOneWidget, reason: 'màn hình trước vẫn còn');
      state.dash.dispose();
    });
  }
}

void indexDialogTest() {
  testWidgets('bấm vào chỉ số mở pop-up chỉ số, có giá, biên độ và nút đóng ở góc phải', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState();
    await tester.runAsync(() => state.init(startDashboard: false));
    final bars = [for (var i = 0; i < 300; i++) Bar(1790000000 + i * 86400, 1700 + i * .1, 1710 + i * .1, 1690, 1700 + i * .1 + (i % 7), 1e8)];
    state.dash.quotes = {'VNINDEX': IndexQuote(indexMetas.first, bars)};
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => openIndex(c, indexMetas.first), child: const Text('Mở chỉ số')))),
        ),
      ),
    ));
    await tester.tap(find.text('Mở chỉ số'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('VNINDEX'), findsWidgets);
    expect(find.text('THÔNG TIN PHIÊN'), findsOneWidget);
    expect(find.byTooltip('Phân tích AI'), findsNothing, reason: 'chỉ số không có phân tích AI');
    expect(tester.getTopLeft(find.byTooltip('Đóng')).dx, greaterThan(1100));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Đóng'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Dialog), findsNothing);
    state.dash.dispose();
  });
}
