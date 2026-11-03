// Đo thời gian dựng + bố cục mỗi khung khi đổi tab, ở kiểu Cổ điển và Liquid Glass (blur 100%).
// Lưu ý: flutter test không có bước raster/GPU, nên đây là chi phí build + layout trên CPU, không phải FPS thật.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart';
import 'package:vn_stock_insight/state.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test';
}

void main() {
  final rows = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    print('\n| Kiểu | Tab | khung max (ms) | trung bình (ms) |\n|---|---|---|---|\n${rows.join('\n')}');
  });

  for (final style in UiStyle.values.reversed) {
    testWidgets('đổi tab ở kiểu ${style.name}', (tester) async {
      SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false, 'flutter.uiStyle': style.name, 'flutter.glassBlur': 1.0});
      FlutterSecureStorage.setMockInitialValues({});
      PackageInfo.setMockInitialValues(appName: 'a', packageName: 'b', version: '3.0.0', buildNumber: '1', buildSignature: '');
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.runAsync(() => state.init(startDashboard: false));
      await tester.pumpWidget(AppScope(state: state, child: const StockApp()));
      for (final tab in ['Bộ lọc', 'CFA', 'Theo dõi', 'Tổng quan']) {
        await tester.tap(find.text(tab).first);
        final times = <double>[];
        for (var i = 0; i < 16; i++) {
          final sw = Stopwatch()..start();
          await tester.pump(const Duration(milliseconds: 16));
          times.add(sw.elapsedMicroseconds / 1000);
        }
        final max = times.reduce((a, b) => a > b ? a : b);
        final avg = times.reduce((a, b) => a + b) / times.length;
        rows.add('| ${style.name} | $tab | ${max.toStringAsFixed(1)} | ${avg.toStringAsFixed(2)} |');
      }
    });
  }
}
