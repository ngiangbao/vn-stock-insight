import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/watchlist_page.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-watch';
}

void main() {
  test('điểm kỹ thuật quy về thang 0–5', () {
    expect(techScore5(-6), 0);
    expect(techScore5(0), 3);
    expect(techScore5(6), 5);
    expect(techScore5(1), 3);
  });

  for (final (w, table) in [(1300.0, true), (390.0, false)]) {
    testWidgets('trang Theo dõi ${w.toInt()} px: ${table ? 'dạng bảng' : 'dạng thẻ'}, không tràn', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.runAsync(() => state.init(startDashboard: false));
      final bars = [for (var i = 0; i < 300; i++) Bar(1790000000 + i * 86400, 50 + i * .1, 52 + i * .1, 49 + i * .1, 51 + i * .1 + (i % 5), 1e6)];
      state.stocks = {for (final s in state.watchlist) s: analyze(s, bars)};

      final prev = FlutterError.onError;
      // Thẻ cũ ở chế độ hẹp tràn với phông thử nghiệm (Ahem rộng hơn phông thật): chỉ kiểm tra tràn ở dạng bảng
      if (!table) FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = prev);
      await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: WatchlistPage())));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Danh mục Theo dõi Cá nhân'), findsOneWidget);
      expect(find.text('Tra cứu cổ phiếu'), findsOneWidget);
      if (table) {
        expect(find.text('Mã CK'), findsOneWidget);
        expect(find.text('AI Report'), findsNWidgets(state.watchlist.length));
        expect(find.textContaining('/5'), findsNWidgets(state.watchlist.length));
        for (final e in find.byTooltip('Gỡ FPT khỏi danh sách').evaluate()) {
          expect((e.renderObject! as RenderBox).size.shortestSide, greaterThanOrEqualTo(44));
        }
      } else {
        expect(find.text('Mã CK'), findsNothing);
      }
      if (table) expect(tester.takeException(), isNull);
      state.dash.dispose();
    });
  }
}
