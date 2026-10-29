import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vn_stock_insight/services/brokers.dart';
import 'package:vn_stock_insight/ui/analysis_report.dart';

final _now = DateTime(2026, 10, 30);

String _feed() => jsonEncode({
  'data': [
    {
      'code': 'VCB',
      'firm': 'HSC',
      'type': 'BUY',
      'reportDate': '2026-10-23',
      'source': 'BLOOMBERG',
      'analyst': 'A',
      'reportPrice': 57.2,
      'targetPrice': 80.0,
    },
    {
      'code': 'VCB',
      'firm': 'HSC',
      'type': 'HOLD',
      'reportDate': '2026-03-01',
      'source': 'BLOOMBERG',
      'reportPrice': 60.0,
      'targetPrice': 70.0,
    },
    {
      'code': 'VCB',
      'firm': 'VND',
      'type': 'HOLD',
      'reportDate': '2026-07-20',
      'source': 'VNDIRECT',
      'reportPrice': 58.0,
      'targetPrice': 66.0,
    },
    {
      'code': 'VCB',
      'firm': 'VCS',
      'type': 'Outperform',
      'reportDate': '2026-09-01',
      'source': 'BLOOMBERG',
      'reportPrice': 59.0,
      'targetPrice': 90.0,
    },
    {
      'code': 'VCB',
      'firm': 'SSI',
      'type': 'SELL',
      'reportDate': '2026-05-04',
      'source': 'BLOOMBERG',
      'reportPrice': 61.0,
      'targetPrice': 50.0,
    },
    {
      'code': 'VCB',
      'firm': 'OLD',
      'type': 'BUY',
      'reportDate': '2024-01-01',
      'source': 'BLOOMBERG',
      'reportPrice': 50.0,
      'targetPrice': 60.0,
    },
    {'code': 'VCB', 'firm': 'BAD', 'type': 'BUY', 'reportDate': 'không phải ngày'},
  ],
});

void main() {
  test('chuẩn hóa mức khuyến nghị và đọc phản hồi (giá nghìn đồng → đồng)', () {
    expect(normalizeRating('Outperform'), 'MUA');
    expect(normalizeRating('buy'), 'MUA');
    expect(normalizeRating('Neutral'), 'NẮM GIỮ');
    expect(normalizeRating('SELL'), 'BÁN');
    expect(normalizeRating('Trading idea'), 'TRADING IDEA');
    final recs = parseRecommendations(_feed());
    expect(recs.length, 6, reason: 'dòng ngày sai bị bỏ');
    expect(recs.first.target, 80000);
    expect(recs.first.reportPrice, 57200);
    expect(parseRecommendations('không phải json'), isEmpty);
  });

  test('mỗi công ty một báo cáo mới nhất trong 12 tháng, mới nhất trước; tên công ty dễ đọc', () {
    final latest = latestPerFirm(parseRecommendations(_feed()), now: _now);
    expect(latest.map((r) => firmName(r.firm)), [
      'HSC',
      'Vietcap',
      'VNDirect',
      'SSI',
    ], reason: 'bỏ báo cáo quá 12 tháng và bản cũ của cùng công ty');
    expect(latest.first.rating, 'MUA');
    expect(latest.first.target, 80000);
    expect(firmName('FTS'), 'FPTS');
  });

  test('gộp Vietcap IQ: thay bản cũ hơn, giữ bản mới hơn trong nguồn tổng hợp', () {
    final base = latestPerFirm(parseRecommendations(_feed()), now: _now);
    final newer = withVietcap(base, rating: 'BUY', target: 95000, date: '2026-10-25');
    final vc = newer.where((r) => firmName(r.firm) == 'Vietcap').single;
    expect(vc.target, 95000);
    expect(newer.where((r) => firmName(r.firm) == 'Vietcap').length, 1);
    expect(newer.first.date, DateTime(2026, 10, 25));
    final older = withVietcap(base, rating: 'ADD', target: 70000, date: '2026-01-01');
    expect(older.where((r) => firmName(r.firm) == 'Vietcap').single.target, 90000, reason: 'bản trong nguồn tổng hợp mới hơn nên giữ');
    expect(withVietcap(base), base, reason: 'không có dữ liệu Vietcap IQ thì giữ nguyên');
  });

  test('đồng thuận: số mua/giữ/bán và giá mục tiêu trung vị', () {
    final c = consensusOf(latestPerFirm(parseRecommendations(_feed()), now: _now));
    expect((c.total, c.buy, c.hold, c.sell), (4, 2, 1, 1));
    expect(c.medianTarget, 73000, reason: 'trung vị của 50, 66, 80, 90 nghìn đồng');
    expect(consensusOf(const []).medianTarget, isNull);
  });

  test('tải qua mạng giả lập; lỗi mạng trả về rỗng thay vì ném lỗi', () async {
    final ok = MockClient((req) async {
      expect(req.url.host, 'api-finfo.vndirect.com.vn');
      expect(req.url.queryParameters['q'], 'code:VCB');
      return http.Response.bytes(utf8.encode(_feed()), 200);
    });
    expect((await fetchBrokerRecs('VCB', client: ok)).length, 6);
    expect(await fetchBrokerRecs('VCB', client: MockClient((_) async => http.Response('x', 500))), isEmpty);
    expect(await fetchBrokerRecs('VCB', client: MockClient((_) async => throw Exception('mạng'))), isEmpty);
  });

  testWidgets('bảng khuyến nghị hiển thị công ty, mức, giá mục tiêu, tiềm năng, đồng thuận và ghi chú về TCBS', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stored = [
      for (final r in latestPerFirm(parseRecommendations(_feed()), now: DateTime.now().subtract(const Duration(days: 0)), maxAgeDays: 4000))
        r.toJson(),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BrokerRecs(symbol: 'VCB', closeThousand: 57.2, saved: {'brokers': stored}, company: const {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('HSC'), findsOneWidget);
    expect(find.text('Vietcap'), findsOneWidget);
    expect(find.text('MUA'), findsWidgets);
    expect(find.text('BÁN'), findsOneWidget);
    expect(find.textContaining('công ty:'), findsOneWidget);
    expect(find.textContaining('Giá mục tiêu trung vị'), findsOneWidget);
    expect(find.textContaining('TCBS'), findsOneWidget, reason: 'ghi chú trung thực về công ty không có trong nguồn');
    expect(find.textContaining('(+39,9%)'), findsWidgets, reason: 'tiềm năng của HSC: 80.000 / 57.200');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chưa có khuyến nghị: thông báo rõ, không lỗi', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrokerRecs(symbol: 'XYZ', closeThousand: 10, saved: {'brokers': []}, company: {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Chưa có khuyến nghị công khai'), findsOneWidget);
  });
}
