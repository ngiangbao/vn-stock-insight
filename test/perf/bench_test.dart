// Đo thời gian luồng giao diện bị chặn bởi các việc nặng: chạy tại chỗ (cách cũ) so với Isolate (cách mới).
// Chỉ số "đứng" là khoảng trễ lớn nhất của một bộ hẹn giờ 2 ms trong lúc việc chạy: càng nhỏ giao diện càng mượt (khung 60 Hz = 16,7 ms).
// Chạy: flutter test test/perf/bench_test.dart   (số liệu in ra console, phụ thuộc máy)
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_stock_insight/services/backtest.dart';
import 'package:vn_stock_insight/services/board.dart';
import 'package:vn_stock_insight/services/market.dart';

List<Bar> _bars(int n, int seed, {int start = 1500000000}) {
  final r = math.Random(seed);
  var p = 20.0;
  return [
    for (var i = 0; i < n; i++)
      () {
        p = math.max(1, p * (1 + (r.nextDouble() - 0.49) * 0.03));
        return Bar(start + i * 86400, p, p * 1.01, p * 0.99, p, 1e5 + r.nextDouble() * 1e6);
      }(),
  ];
}

List<Map<String, dynamic>> _boardJson(int n) => [
  for (var i = 0; i < n; i++)
    {
      's': 'T${i.toString().padLeft(4, '0')}',
      'st': 'STOCK',
      'bo': i % 3 == 0 ? 'HSX' : 'HNX',
      'orgn': 'Công ty cổ phần số $i',
      'ref': 20000 + i,
      'cei': 21400 + i,
      'flo': 18600 + i,
      'c': 20100 + i,
      'op': 20000,
      'h': 20300,
      'l': 19900,
      'avgp': 20100,
      'vo': 123456 + i,
      'ptv': 0,
      'va': 2480.5,
      'pta': 0,
      'frbv': 1000,
      'frsv': 900,
      for (var k = 1; k <= 3; k++) ...{'bp$k': 20000 - k * 50, 'bv$k': 1000 * k, 'ap$k': 20100 + k * 50, 'av$k': 900 * k},
    },
];

/// Chạy [job] và trả (độ đứng lớn nhất ms, tổng ms).
Future<(double, double)> _stall(Future<void> Function() job) async {
  final sw = Stopwatch()..start();
  var last = sw.elapsedMicroseconds, worst = 0;
  final t = Timer.periodic(const Duration(milliseconds: 2), (_) {
    final now = sw.elapsedMicroseconds;
    worst = math.max(worst, now - last);
    last = now;
  });
  await job();
  final total = sw.elapsedMicroseconds;
  worst = math.max(worst, total - last);
  t.cancel();
  return (worst / 1000, total / 1000);
}

void main() {
  final rows = <String>[];
  void report(String name, (double, double) before, (double, double) after) {
    rows.add('| $name | ${before.$1.toStringAsFixed(1)} | ${after.$1.toStringAsFixed(1)} | ${after.$2.toStringAsFixed(1)} |');
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('\n| Việc | Đứng cũ (ms) | Đứng mới (ms) | Tổng mới (ms) |\n|---|---|---|---|\n${rows.join('\n')}');
  });

  test('bảng giá 1500 mã: giải mã JSON + dựng hàng', () async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(_boardJson(1500))));
    await parseBoardBytes(bytes); // khởi động nóng
    final before = await _stall(() async {
      parseBoard(jsonDecode(utf8.decode(bytes)) as List);
    });
    final after = await _stall(() async {
      expect((await parseBoardBytes(bytes)).length, 1500);
    });
    report('Bảng giá 1.500 mã (giải mã + dựng)', before, after);
    expect(after.$1, lessThan(before.$1));
  });

  test('kiểm định điểm sức khỏe một mã 1500 phiên', () async {
    final bars = _bars(1500, 1), index = _bars(1500, 2);
    await backtestHealthAsync(bars, index);
    final before = await _stall(() async {
      backtestHealth(bars, index);
    });
    final after = await _stall(() async {
      await backtestHealthAsync(bars, index);
    });
    report('Kiểm định sức khỏe 1 mã (1.500 phiên)', before, after);
  });

  test('độ rộng thị trường 400 mã × 200 phiên', () async {
    final all = [for (var i = 0; i < 400; i++) _bars(200, i)];
    await breadthSeriesAsync(all);
    final before = await _stall(() async {
      breadthSeries(all);
    });
    final after = await _stall(() async {
      await breadthSeriesAsync(all);
    });
    report('Độ rộng thị trường (400 mã × 200 phiên)', before, after);
  });

  test('giải mã lịch sử giá 1500 phiên', () async {
    final b = _bars(1500, 3);
    final body = jsonEncode({
      't': [for (final x in b) x.t],
      'o': [for (final x in b) x.o],
      'h': [for (final x in b) x.h],
      'l': [for (final x in b) x.l],
      'c': [for (final x in b) x.c],
      'v': [for (final x in b) x.v],
    });
    final before = await _stall(() async {
      parseBars(jsonDecode(body) as Map<String, dynamic>);
    });
    final after = await _stall(() async {
      expect((await decodeBars(body)).length, 1500);
    });
    report('Giải mã lịch sử giá 1.500 phiên (${(body.length / 1024).round()} KB)', before, after);
  });
}
