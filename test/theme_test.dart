import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart';
import 'package:vn_stock_insight/state.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test';
}

void main() {
  testWidgets('bấm Sáng/Tối trong Cài đặt đổi giao diện ngay', (tester) async {
    SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState();
    await state.init();
    await tester.pumpWidget(AppScope(state: state, child: const StockApp()));
    await tester.tap(find.text('Cài đặt').first);
    await tester.pumpAndSettle();

    Brightness brightness() => Theme.of(tester.element(find.text('Giao diện'))).brightness;
    await tester.tap(find.text('Tối'));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.dark);
    expect(brightness(), Brightness.dark);
    await tester.tap(find.text('Sáng'));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
  });
}
