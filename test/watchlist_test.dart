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

  for (final w in [1900.0, 1300.0, 700.0, 390.0]) {
    testWidgets('trang Theo dõi ${w.toInt()} px: bảng ngang thẳng hàng, không tràn, các hàng không chồng nhau', (tester) async {
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

      await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: WatchlistPage())));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Danh mục Theo dõi Cá nhân'), findsOneWidget);
      expect(find.text('Tra cứu cổ phiếu'), findsOneWidget);
      expect(find.text('Mã CK'), findsOneWidget);
      expect(find.text('AI Report'), findsNWidgets(state.watchlist.length));
      expect(find.textContaining('/5'), findsNWidgets(state.watchlist.length));
      // Các hàng xếp dọc đều nhau, không chồng lên nhau
      final tops = [for (final sym in state.watchlist) tester.getTopLeft(find.text(sym).first).dy]..sort();
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i] - tops[i - 1], greaterThanOrEqualTo(60), reason: 'hàng ${i + 1} không được chen vào hàng trước');
      }
      // Ở cửa sổ rộng, bảng chiếm gần hết chiều ngang (không bị giới hạn 1100 px)
      if (w >= 1300) expect(tester.getSize(find.byType(Card).first).width, greaterThan(w - 40));
      expect(tester.takeException(), isNull);
      state.dash.dispose();
    });
  }
}
