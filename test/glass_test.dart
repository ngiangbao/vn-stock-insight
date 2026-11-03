import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/glass.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test';
}

Future<AppState> _boot(WidgetTester tester, [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false, ...prefs});
  FlutterSecureStorage.setMockInitialValues({});
  PackageInfo.setMockInitialValues(appName: 'VN Stock Insight', packageName: 'vn', version: '3.0.0', buildNumber: '1', buildSignature: '');
  PathProviderPlatform.instance = _FakePaths();
  final state = AppState();
  await tester.runAsync(() => state.init(startDashboard: false));
  return state;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Thêm'));
  await tester.pump();
  await tester.tap(find.widgetWithText(MenuItemButton, 'Cài đặt'));
  await tester.pumpAndSettle();
}

void main() {
  test('tương phản chữ ≥ 4,5:1 trên kính ở mọi mức blur 0–100%, sáng và tối', () {
    for (final b in Brightness.values) {
      for (var i = 0; i <= 100; i++) {
        final g = GlassTokens.of(b, i / 100);
        expect(GlassTokens.worstContrast(b, g.cardAlpha), greaterThanOrEqualTo(4.5), reason: '$b $i%');
        expect(GlassTokens.worstContrast(b, g.panelAlpha), greaterThanOrEqualTo(4.5), reason: '$b panel $i%');
        expect(GlassTokens.worstContrast(b, g.overlayAlpha), greaterThanOrEqualTo(4.5), reason: '$b overlay $i%');
      }
      // Giảm trong suốt (tương phản cao) cũng đạt
      final r = GlassTokens.of(b, 1, reduceTransparency: true);
      expect(r.sigma, 0);
      expect(GlassTokens.worstContrast(b, r.cardAlpha), greaterThanOrEqualTo(4.5));
    }
  });

  test('thanh trượt đổi sigma và độ đục đúng chiều, 0% tắt blur', () {
    for (final b in Brightness.values) {
      expect(GlassTokens.of(b, 0).sigma, 0);
      expect(GlassTokens.of(b, 1).sigma, GlassTokens.maxSigma);
      var prevSigma = -1.0, prevAlpha = 0.0;
      for (var i = 0; i <= 100; i += 5) {
        final g = GlassTokens.of(b, i / 100);
        expect(g.sigma, greaterThanOrEqualTo(prevSigma));
        expect(g.cardAlpha, greaterThanOrEqualTo(prevAlpha));
        prevSigma = g.sigma;
        prevAlpha = g.cardAlpha;
      }
      expect(GlassTokens.of(b, 1).cardAlpha, greaterThan(GlassTokens.of(b, 0).cardAlpha));
      expect(GlassTokens.of(b, 1, reduceMotion: true).sigma, lessThan(GlassTokens.maxSigma));
    }
  });

  test('chữ và màu nhấn của theme Cổ điển và Liquid Glass đạt ≥ 4,5:1 trên thẻ', () {
    for (final b in Brightness.values) {
      for (final style in UiStyle.values) {
        for (final blur in [0.0, 0.25, 0.6, 1.0]) {
          final t = appTheme(b, style: style, blur: blur);
          final card = t.cardTheme.color!;
          final bg = style == UiStyle.liquidGlass ? GlassPalette.samples(b) : [Ds.lightBg.first, Ds.darkBg.first];
          for (final back in bg) {
            final surface = Color.alphaBlend(card, back);
            for (final ink in [t.colorScheme.onSurface, t.colorScheme.onSurfaceVariant, t.colorScheme.primary]) {
              expect(contrastRatio(ink, surface), greaterThanOrEqualTo(4.5), reason: '$style $b $blur');
            }
          }
        }
      }
    }
  });

  testWidgets('mặc định là Liquid Glass; đổi sang Cổ điển, đổi lại và lưu qua lần mở sau', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = await _boot(tester);
    expect(state.uiStyle, UiStyle.liquidGlass);
    await tester.pumpWidget(AppScope(state: state, child: const StockApp()));
    expect(find.byType(GlassBackground), findsOneWidget);
    await _openSettings(tester);
    await tester.tap(find.text('Cổ điển'));
    await tester.pumpAndSettle();
    expect(state.uiStyle, UiStyle.classic);
    expect(find.byType(GlassBackground), findsNothing);
    // Cổ điển: thanh trượt bị vô hiệu
    expect(tester.widget<Slider>(find.byKey(const Key('glassBlurSlider'))).onChanged, isNull);

    final again = AppState();
    await tester.runAsync(() => again.init(startDashboard: false));
    expect(again.uiStyle, UiStyle.classic);

    await tester.tap(find.text('Liquid Glass'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassBackground), findsOneWidget);
    final third = AppState();
    await tester.runAsync(() => third.init(startDashboard: false));
    expect(third.uiStyle, UiStyle.liquidGlass);
  });

  testWidgets('thanh trượt độ blur: kéo đổi ngay, lưu, nạp lại, đặt lại, phím mũi tên và Semantics', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final state = await _boot(tester);
    expect(state.glassBlur, closeTo(0.6, 1e-9));
    await tester.pumpWidget(AppScope(state: state, child: const StockApp()));
    await _openSettings(tester);
    expect(find.text('60%'), findsOneWidget);
    final sem = tester.getSemantics(find.byKey(const Key('glassBlurSlider')));
    expect(sem.label, contains('Độ blur kính'));
    expect(sem.value, contains('60'));
    expect(tester.getSize(find.byKey(const Key('glassBlurSlider'))).height, greaterThanOrEqualTo(48));

    final slider = find.byKey(const Key('glassBlurSlider'));
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy)); // chạm mép trái
    await tester.pumpAndSettle();
    expect(state.glassBlur, lessThan(0.05));
    expect(GlassTokens.of(Brightness.light, state.glassBlur).sigma, lessThan(2));

    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect(state.glassBlur, greaterThan(0.95));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('glassBlur'), greaterThan(0.95));

    // Phím mũi tên: lấy tiêu điểm rồi bấm trái giảm 1%
    final before = state.glassBlur;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.glassBlur, lessThanOrEqualTo(before));

    final reloaded = AppState();
    await tester.runAsync(() => reloaded.init(startDashboard: false));
    expect(reloaded.glassBlur, closeTo(state.glassBlur, 1e-9));

    await tester.tap(find.text('Đặt lại'));
    await tester.pumpAndSettle();
    expect(state.glassBlur, closeTo(0.6, 1e-9));
    handle.dispose();
  });

  for (final style in UiStyle.values) {
    testWidgets('điện thoại 375 px không tràn ở kiểu ${style.name}, mọi tab chính và Cài đặt', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = await _boot(tester, {'flutter.uiStyle': style.name, 'flutter.glassBlur': 1.0});
      await tester.pumpWidget(AppScope(state: state, child: const StockApp()));
      expect(find.byType(NavigationBar), findsOneWidget);
      for (final tab in ['Theo dõi', 'Bộ lọc', 'CFA', 'Tổng quan']) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Thêm'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Cài đặt'));
      await tester.pumpAndSettle();
      expect(find.text('Độ blur kính'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
