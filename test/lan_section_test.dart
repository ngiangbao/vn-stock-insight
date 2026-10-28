import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/lan_section.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-lan';
}

void main() {
  for (final w in [375.0, 900.0]) {
    testWidgets('mục Chia sẻ trong mạng nội bộ vừa khung ${w.toInt()} px, nút chạm >= 44 px', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      tester.view.physicalSize = Size(w, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.runAsync(() => state.init(startDashboard: false));
      state.lan.preferredPort = 0; // cổng tự chọn để không đụng app đang chạy
      expect(state.lan.enabled, isFalse, reason: 'mặc định tắt');

      await tester.pumpWidget(AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LanSection()))),
      ));
      expect(find.text('Bật máy chủ nội bộ'), findsOneWidget);
      expect(find.byType(QrView), findsNothing);

      await tester.runAsync(() => state.lan.setEnabled(true));
      await tester.runAsync(() => state.lan.refreshAddresses());
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.lan.enabled, isTrue);
      if (state.lan.addresses.isNotEmpty) {
        expect(find.byType(QrView), findsOneWidget);
        expect(find.text('Sao chép link'), findsOneWidget);
        for (final label in ['Sao chép link', 'Tạo lại khoá', 'Tự kiểm tra kết nối']) {
          final h = tester.getSize(find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first).height;
          expect(h, greaterThanOrEqualTo(44), reason: label);
        }
        expect(find.textContaining(state.lan.key), findsNothing, reason: 'khoá bị ẩn mặc định');
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => state.lan.setEnabled(false));
      state.dash.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => await Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(File('/nonexistent').existsSync(), isFalse);
    });
  }
}
