import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/dashboard.dart';
import 'package:vn_stock_insight/services/board.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/overview_page.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test';
}

void main() {
  for (final (w, h) in [(1280.0, 720.0), (1920.0, 1080.0), (900.0, 640.0), (390.0, 800.0)]) {
    testWidgets('dashboard vừa khung ${w.toInt()}x${h.toInt()} không tràn', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await state.init(startDashboard: false);

      final t0 = 1793030400;
      final daily = [
        for (var i = 0; i < 300; i++)
          Bar(t0 + i * 86400, 1700 + i * 0.1, 1710 + i * 0.1, 1690, 1700 + i * 0.1 + (i % 7), 1e8),
      ];
      state.dash.quotes = {for (final m in indexMetas) m.symbol: IndexQuote(m, daily)};
      state.dash.intraday = [
        for (var i = 0; i < 240; i++)
          Bar(t0 + 299 * 86400 + (2 * 3600 + i * 60), 1, 1, 1, 1750 + (i % 17), 1000.0 * (i % 9)),
      ];
      final rows = [
        for (var i = 0; i < 120; i++)
          BoardRow(
            symbol: 'S$i',
            exchange: 'HOSE',
            ref: 100,
            ceil: 107,
            floor: 93,
            price: 100 + (i % 15) - 7,
            open: 100,
            high: 105,
            low: 95,
            volume: 1e5,
            ptVolume: 1e3,
            valueMn: 1000.0 * (120 - i),
            ptValueMn: 5,
            foreignBuy: 100,
            foreignSell: 50,
          ),
      ];
      state.dash.boards = {'HOSE': rows, 'VN30': rows.take(30).toList()};
      state.dash.sectors = {for (var i = 0; i < 100; i++) 'S$i': SectorInfo('Ngành ${i % 9}', 1)};

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(home: const OverviewPage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      if (w >= 1200) {
        expect(find.text('Dòng tiền'), findsOneWidget);
      } else if (w >= 760) {
        // Medium windows use a vertical layout; scroll to build the later card.
        await tester.scrollUntilVisible(
          find.text('Dòng tiền'),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Dòng tiền'), findsOneWidget);
      }
      expect(find.text('Biến động'), findsOneWidget);
      // Màn hình rộng: không có cuộn dọc cho cả trang
      if (w >= 900 && h >= 700) expect(find.byType(SingleChildScrollView), findsNothing);
    });
  }
}
