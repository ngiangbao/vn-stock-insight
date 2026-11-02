import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vn_stock_insight/services/ticks.dart';

// Phiên 30/10/2026: 09:00 VN = 02:00 UTC
final _open = DateTime.utc(2026, 10, 30, 2).millisecondsSinceEpoch ~/ 1000;

List<Map<String, dynamic>> _dataset(int n, {int seed = 5, int? burstAt, int burst = 0}) {
  final rnd = math.Random(seed);
  final rows = <Map<String, dynamic>>[];
  var id = 1000;
  for (var i = 0; i < n; i++) {
    // rải đều 09:15–14:45, thưa dần để mật độ không đều
    final t = _open + 900 + (i * 19800 ~/ n);
    final side = rnd.nextInt(10) == 0 ? 'unknown' : (rnd.nextBool() ? 'b' : 's');
    rows.add({
      'id': id++,
      'symbol': 'HPG',
      'truncTime': '$t',
      'matchType': side,
      'matchVol': '${100 * (1 + rnd.nextInt(30))}.0',
      'matchPrice': '20400.0',
      'type': 'sheep',
    });
  }
  if (burstAt != null) {
    for (var i = 0; i < burst; i++) {
      rows.add({
        'id': id++,
        'symbol': 'HPG',
        'truncTime': '${_open + burstAt}',
        'matchType': 'b',
        'matchVol': '100.0',
        'matchPrice': '20400.0',
        'type': 'sheep',
      });
    }
  }
  return rows;
}

MockClient _server(List<Map<String, dynamic>> rows, {void Function()? onCall, int failFirst = 0}) {
  var failures = 0;
  return MockClient((req) async {
    onCall?.call();
    if (failures < failFirst) {
      failures++;
      return http.Response('lỗi tạm', 503);
    }
    expect(req.url.host, 'trading.vietcap.com.vn');
    final body = jsonDecode(req.body) as Map;
    expect(body['limit'], 100);
    final cursor = body['truncTime'] == null ? null : int.parse('${body['truncTime']}');
    final sel = rows.where((r) => cursor == null || int.parse(r['truncTime'] as String) <= cursor).toList()
      ..sort((a, b) {
        final c = int.parse(b['truncTime'] as String).compareTo(int.parse(a['truncTime'] as String));
        return c != 0 ? c : (b['id'] as int).compareTo(a['id'] as int);
      });
    return http.Response.bytes(utf8.encode(jsonEncode(sel.take(100).toList())), 200, headers: {'content-type': 'application/json'});
  });
}

void main() {
  test('đọc lệnh khớp: phân loại mua/bán/không phân loại, bỏ dòng hỏng', () {
    final ticks = parseTicks(
      jsonEncode([
        {'id': 1, 'truncTime': '1793605500', 'matchType': 'unknown', 'matchVol': '2039100.0', 'matchPrice': '20400.0', 'type': 'shark'},
        {'id': 2, 'truncTime': '1793604599', 'matchType': 'b', 'matchVol': '500.0', 'matchPrice': '20500.0', 'type': 'sheep'},
        {'id': 3, 'truncTime': '1793604595', 'matchType': 's', 'matchVol': '100.0', 'matchPrice': '20500.0', 'type': 'wolf'},
        {'id': 4, 'truncTime': 'hỏng'},
      ]),
    );
    expect(ticks.map((k) => k.side), ['u', 'b', 's']);
    expect(ticks[1].value, 500 * 20500);
    expect(ticks.length, 3);
    expect(parseTicks('không phải json'), isEmpty);
  });

  test('tổng hợp: mua/bán chủ động, ròng, tiền lớn từ 1 tỷ và số lệnh lớn', () {
    final ticks = [
      const Tick(1, 100, 'b', 10000, 20000, 'shark'), // 200 triệu
      const Tick(2, 101, 'b', 60000, 20000, 'shark'), // 1,2 tỷ: lệnh lớn
      const Tick(3, 102, 's', 100000, 20000, 'shark'), // 2 tỷ: lệnh lớn
      const Tick(4, 103, 's', 5000, 20000, 'sheep'),
      const Tick(5, 104, 'u', 1000000, 20000, 'shark'), // ATC không tính mua/bán
    ];
    final s = summarize(ticks);
    expect(s.buyVol, 70000);
    expect(s.sellVol, 105000);
    expect(s.otherVol, 1000000);
    expect(s.buyValue, 1.4e9);
    expect(s.sellValue, 2.1e9);
    expect(s.netValue, closeTo(-0.7e9, 1));
    expect((s.bigBuyCount, s.bigSellCount), (1, 1));
    expect(s.bigBuyValue, 1.2e9);
    expect(s.bigNet, closeTo(-0.8e9, 1));
    expect(s.totalVol, 1175000);
    expect(summarize(const []).ticks, 0);
  });

  test('gom theo khoảng thời gian căn theo giờ Việt Nam', () {
    final t0 = _open + 15 * 60; // 09:15
    final b = bucketize([
      Tick(1, t0, 'b', 100, 1, ''),
      Tick(2, t0 + 120, 's', 50, 1, ''),
      Tick(3, t0 + 320, 'b', 10, 1, ''), // 09:20:20 sang bucket 5 phút kế tiếp
      Tick(4, t0 + 330, 'u', 7, 1, ''),
    ], 5);
    expect(b.length, 2);
    expect((b[0].buy, b[0].sell, b[0].other), (100, 50, 0));
    expect((b[1].buy, b[1].other), (10, 7));
    expect(b[0].start, t0);
    expect(bucketize([Tick(1, t0, 'b', 100, 1, ''), Tick(2, t0 + 400, 'b', 100, 1, '')], 15).length, 1);
  });

  test('tải cả phiên bằng nhiều lượt song song: đủ mọi lệnh, không trùng, đúng thứ tự', () async {
    final rows = _dataset(1250);
    var calls = 0;
    final load = await loadSessionTicks(
      'HPG',
      client: _server(rows, onCall: () => calls++),
      onProgress: (a, b) {},
    );
    expect(load.complete, isTrue);
    expect(load.day, '2026-10-30');
    expect(load.ticks.length, 1250, reason: 'không thiếu, không trùng');
    expect({for (final k in load.ticks) k.id}.length, 1250);
    for (var i = 1; i < load.ticks.length; i++) {
      expect(load.ticks[i].t, greaterThanOrEqualTo(load.ticks[i - 1].t));
    }
    expect(calls, lessThan(60), reason: '1250 lệnh tương ứng khoảng 13 trang cộng phần dư ở biên khoảng');
    final s = summarize(load.ticks);
    expect(s.buyVol + s.sellVol + s.otherVol, closeTo(rows.fold<double>(0, (a, r) => a + double.parse(r['matchVol'] as String)), 1e-6));
  });

  test('hơn 100 lệnh trong cùng một giây: kết thúc (không lặp vô hạn) và báo đủ phần còn lại', () async {
    final rows = _dataset(300, burstAt: 6000, burst: 250);
    final load = await loadSessionTicks('HPG', client: _server(rows)).timeout(const Duration(seconds: 20));
    expect(load.ticks.length, greaterThanOrEqualTo(300), reason: 'các lệnh rải đều vẫn đủ');
    expect(load.ticks.length, lessThanOrEqualTo(550));
  });

  test('giới hạn số lượt gọi: dừng và đánh dấu chưa đầy đủ', () async {
    final load = await loadSessionTicks('HPG', client: _server(_dataset(1250)), maxRequests: 6);
    expect(load.complete, isFalse);
    expect(load.ticks, isNotEmpty);
  });

  test('lỗi tạm thời được thử lại; lỗi kéo dài báo rõ; mã 4xx không thử lại', () async {
    final load = await loadSessionTicks('HPG', client: _server(_dataset(150), failFirst: 2));
    expect(load.ticks.length, 150);
    await expectLater(
      loadSessionTicks('HPG', client: _server(_dataset(50), failFirst: 99)),
      throwsA(isA<TickException>().having((e) => e.message, 'message', contains('Không tải được'))),
    );
    var calls = 0;
    await expectLater(
      fetchTickPage(
        'HPG',
        client: MockClient((_) async {
          calls++;
          return http.Response('x', 404);
        }),
      ),
      throwsA(isA<TickException>().having((e) => e.message, 'message', contains('HTTP 404'))),
    );
    expect(calls, 1);
    expect((await loadSessionTicks('HPG', client: _server(const []))).ticks, isEmpty);
  });

  test('làm mới: chỉ bổ sung lệnh mới, không trùng', () async {
    final rows = _dataset(400);
    final first = await loadSessionTicks('HPG', client: _server(rows));
    // thêm 120 lệnh mới
    final more = [...rows];
    var id = 5000;
    for (var i = 0; i < 120; i++) {
      more.add({
        'id': id++,
        'symbol': 'HPG',
        'truncTime': '${_open + 21000 + i}',
        'matchType': 'b',
        'matchVol': '100.0',
        'matchPrice': '20400.0',
        'type': 'sheep',
      });
    }
    final merged = await refreshTicks('HPG', first.ticks, client: _server(more));
    expect(merged.length, 520);
    expect({for (final k in merged) k.id}.length, 520);
    expect((await refreshTicks('HPG', merged, client: _server(more))).length, 520, reason: 'làm mới lần nữa không đổi');
  });
}
