import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/stock_dialog.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-dialog';
}

void main() {
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
      expect(find.text('FPT'), findsWidgets);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byTooltip('Đóng'), findsOneWidget);
      expect(find.byTooltip('Thêm vào danh sách theo dõi'), findsNothing, reason: 'FPT đã có trong danh sách theo dõi mặc định');
      if (w > 800) {
        expect(find.text('CHỈ SỐ CƠ BẢN'), findsOneWidget);
        expect(find.text('Phân tích AI'), findsOneWidget);
      }
      for (final t in ['Đóng', 'Bỏ theo dõi']) {
        expect(tester.getSize(find.byTooltip(t)).shortestSide, greaterThanOrEqualTo(44), reason: t);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Mở FPT'), findsOneWidget, reason: 'màn hình trước vẫn còn');
      state.dash.dispose();
    });
  }
}
