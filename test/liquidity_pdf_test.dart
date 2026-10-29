import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/pdf_export.dart';
import 'package:vn_stock_insight/ui/liquidity_chart.dart';

// 09:00 giờ Việt Nam = 02:00 UTC
int _t(int day, int hour, int minute) => DateTime.utc(2026, 10, day, hour - 7, minute).millisecondsSinceEpoch ~/ 1000;

void main() {
  test('gộp nến 1 phút thành khối lượng cộng dồn của hai phiên cuối', () {
    final bars = [
      for (final day in [27, 28, 29])
        for (var m = 0; m < 3; m++) Bar(_t(day, 9, m), 1, 1, 1, 1, 100.0 * (day - 26)),
    ];
    final s = sessionsOf(bars)!;
    expect(s.$1.day, '2026-10-28');
    expect(s.$2.day, '2026-10-29');
    expect(s.$1.total, 600);
    expect(s.$2.total, 900);
    expect(s.$2.at(9 * 60 + 1), 600);
    expect(s.$2.at(9 * 60 + 5), isNull);
    expect(sessionsOf(bars.take(3).toList()), isNull);
  });

  testWidgets('biểu đồ thanh khoản không tràn ở 340 px và 900 px', (tester) async {
    for (final w in [340.0, 900.0]) {
      tester.view.physicalSize = Size(w, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LiquidityChart('FPT')))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('THANH KHOẢN TRONG PHIÊN'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('xuất PDF nhiều trang từ ảnh dài', (tester) async {
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 800, 3000), ui.Paint()..color = Colors.teal);
      final img = await rec.endRecording().toImage(800, 3000);
      final bytes = await pdfFromImage(img, title: 'thử');
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final dir = await Directory.systemTemp.createTemp('pdf');
      final f = await savePdf(bytes, 'a.pdf', dir: dir);
      expect(await f.length(), bytes.length);
      final counts = RegExp(r'/Count (\d+)').allMatches(String.fromCharCodes(bytes)).map((m) => int.parse(m[1]!));
      expect(counts.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(3));
      await dir.delete(recursive: true);
    });
  });
}
