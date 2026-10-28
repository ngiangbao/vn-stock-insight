import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/services/indicators.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/chart.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test';
}

void main() {
  final rnd = math.Random(1);
  var p = 50.0;
  final bars = [
    for (var i = 0; i < 600; i++)
      () {
        final o = p;
        p = math.max(5, p + rnd.nextDouble() * 2 - 1);
        return Bar(1700000000 + i * 86400, o, math.max(o, p) + 0.5, math.min(o, p) - 0.5, p, 1e6 + rnd.nextDouble() * 1e6);
      }(),
  ];

  test('chỉ báo: MACD, Stochastic, Heikin-Ashi đủ độ dài', () {
    final closes = bars.map((b) => b.c).toList();
    final (m, s, h) = macdSeries(closes);
    expect([m.length, s.length, h.length], [600, 600, 600]);
    expect(h.last, closeTo(m.last! - s.last!, 1e-9));
    final (k, d) = stochasticSeries(bars);
    expect(k.last, inInclusiveRange(0, 100));
    expect(d.last, isNotNull);
    expect(heikinAshi(bars).length, 600);
  });

  testWidgets('biểu đồ vẽ được mọi dạng với mọi chỉ báo, rê chuột, cuộn để phóng to', (tester) async {
    SharedPreferences.setMockInitialValues({'flutter.autoUpdate': false});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState();
    await state.init();
    for (final i in Indicator.values) {
      if (!state.chartIndicators.contains(i)) state.toggleIndicator(i);
    }
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(home: Scaffold(body: StockChart('TEST', bars, height: 600))),
    ));
    for (final t in ChartType.values) {
      state.setChartType(t);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: t.label);
    }
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(600, 300));
    await gesture.moveTo(const Offset(700, 350));
    await tester.pump();
    await tester.sendEventToBinding(const PointerScrollEvent(position: Offset(700, 350), scrollDelta: Offset(0, -300)));
    await tester.pump();
    await tester.drag(find.byType(CustomPaint).last, const Offset(200, 0));
    await tester.pump(const Duration(seconds: 1)); // chờ hết thời gian nhận diện nhấp đúp
    expect(tester.takeException(), isNull);
  });
}
