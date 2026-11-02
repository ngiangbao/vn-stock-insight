import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/ticks.dart';
import 'package:vn_stock_insight/ui/active_flow.dart';

void main() {
  final open = sessionOpen('2026-11-02');
  final ticks = [
    Tick(1, open + 60, 'b', 5000, 27000, 'shark'), // 135 triệu
    Tick(2, open + 120, 's', 50000, 27000, 'shark'), // 1,35 tỷ: lệnh lớn bán
    Tick(3, open + 400, 'b', 60000, 27000, 'shark'), // 1,62 tỷ: lệnh lớn mua
    Tick(4, open + 500, 'u', 1000, 27000, 'sheep'),
  ];

  Future<void> pumpFlow(WidgetTester tester, double w, {Future<TickLoad> Function(String, void Function(int, int))? loader}) async {
    tester.view.physicalSize = Size(w, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ActiveFlow('HPG', loader: loader ?? (s, p) async => TickLoad(ticks, '2026-11-02', true), refresher: (s, k) async => k),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final w in [1100.0, 375.0]) {
    testWidgets('hiện tổng mua/bán chủ động, tiền lớn và chú giải, không tràn ở ${w.toInt()} px', (tester) async {
      await pumpFlow(tester, w);
      expect(find.textContaining('Tiền lớn'), findsOneWidget);
      expect(find.text('Mua chủ động lớn'), findsOneWidget);
      expect(find.text('Bán chủ động lớn'), findsOneWidget);
      expect(find.text('1 lệnh'), findsNWidgets(2));
      expect(find.textContaining('Mua chủ động (cột lên)'), findsOneWidget);
      expect(find.textContaining('Bán chủ động (cột xuống)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('15 phút'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lỗi tải: báo lý do và có nút Thử lại', (tester) async {
    await pumpFlow(tester, 800, loader: (s, p) async => throw Exception('mất mạng'));
    expect(find.textContaining('mất mạng'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });
}
