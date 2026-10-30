import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vn_stock_insight/services/corporate_bonds.dart';
import 'package:vn_stock_insight/ui/corporate_bonds_page.dart';
import 'package:vn_stock_insight/ui/widgets.dart';

Map<String, dynamic> bond(String code, {String? maturity = '2030-10-31'}) => {
  'code': code,
  'issuer': 'Doanh nghiệp $code',
  'bondType': 'CORPORATE',
  'matureDate': maturity,
  'issuedDate': '2023-01-01',
  'faceValue': 100000,
  'bondStatus': 'LISTED',
  'floor': 'HNX',
  'interestType': 'FIXED',
};
http.Response page(
  int index,
  List<Map<String, dynamic>> rows, {
  int pages = 1,
  int? total,
}) => http.Response(
  jsonEncode({
    'currentPage': index,
    'totalPages': pages,
    'totalElements': total ?? rows.length,
    'data': rows,
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'fetches every page, not just first; caches complete snapshot',
    () async {
      final dir = Directory.systemTemp.createTempSync('vnsi-bond-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final requests = <int>[];
      final repo = CorporateBondRepository(
        cacheFile: File('${dir.path}/bonds.json'),
        client: MockClient((r) async {
          final p = int.parse(r.url.queryParameters['page']!);
          requests.add(p);
          if (p > 1) {
            return http.Response(
              jsonEncode({
                'currentPage': p,
                'data': [bond('B$p')],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return page(p, [bond('B$p')], pages: 3, total: 3);
        }),
      );
      addTearDown(repo.close);
      final result = await repo.load();
      expect(requests, [1, 2, 3]);
      expect(result.bonds.map((b) => b.code), ['B1', 'B2', 'B3']);
      expect(result.sourceTotal, 3);
      final cached = await repo.load();
      expect(cached.cached, isTrue);
      expect(requests.length, 3);
    },
  );

  test('failed/missing/duplicate later page retains old data; never saves partial list', () async {
    for (final failure in ['http', 'empty', 'duplicate', 'changedTotal']) {
      final dir = Directory.systemTemp.createTempSync('vnsi-bond-test');
      final cache = File('${dir.path}/bonds.json');
      final seed = CorporateBondRepository(
        cacheFile: cache,
        client: MockClient((r) async => page(1, [bond('OLD')])),
      );
      await seed.load();
      seed.close();
      final repo = CorporateBondRepository(
        cacheFile: cache,
        client: MockClient((r) async {
          final p = int.parse(r.url.queryParameters['page']!);
          if (p == 1) return page(1, [bond('NEW')], pages: 2, total: 2);
          return switch (failure) {
            'http' => http.Response('error', 503),
            'empty' => page(2, [], pages: 2, total: 2),
            'duplicate' => page(2, [bond('NEW')], pages: 2, total: 2),
            _ => page(2, [bond('NEW2')], pages: 2, total: 3),
          };
        }),
      );
      final result = await repo.load(force: true);
      expect(result.bonds.single.code, 'OLD', reason: failure);
      expect(result.warning, isNotNull);
      repo.close();
      await dir.delete(recursive: true);
    }
  });

  test('missing values stay missing; dates strict and use Vietnam day; rate terms not inferred', () {
    final b = CorporateBond.fromJson({
      ...bond('TEST', maturity: '2026-10-31'),
      'faceValue': 0,
      'interestType': 'UNFIXED',
      'documents': [
        {'interestRateDesc': '<p>9% sau đó thả nổi &amp; theo hợp đồng</p>'},
      ],
    });
    expect(b.faceValue, isNull);
    expect(b.rateLabel, 'Thả nổi');
    expect(b.rateDescription, '9% sau đó thả nổi & theo hợp đồng');
    expect(b.remainingDays(DateTime.utc(2026, 10, 30, 18)), 0);
    expect(b.remainingDays(DateTime.utc(2026, 10, 31, 18)), -1);
    expect(
      CorporateBond.fromJson(bond('INVALID', maturity: '2026-02-30')).maturity,
      isNull,
    );
    expect(
      CorporateBond.fromJson(bond('MISSING', maturity: null))
          .remainingDays(DateTime.now()),
      isNull,
    );
  });

  testWidgets(
    'corporate table fills window, filters source catalog, shows missing date and details',
    (tester) async {
      tester.view.physicalSize = const Size(1900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = CorporateBondRepository(
        client: MockClient(
          (r) async => page(1, [
            bond('FUTURE', maturity: '2099-01-01'),
            bond('PAST', maturity: '2000-01-01'),
            bond('UNKNOWN', maturity: null),
          ]),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CorporateBondsPage(repository: repo)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('FUTURE'), findsOneWidget);
      expect(find.text('PAST'), findsOneWidget);
      await tester.tap(find.text('Chưa đáo hạn'));
      await tester.pumpAndSettle();
      expect(find.text('PAST'), findsNothing);
      expect(tester.getSize(find.byType(FlexTable)).width, closeTo(1868, .1));
      await tester.tap(find.text('Tất cả từ nguồn'));
      await tester.pumpAndSettle();
      expect(find.text('PAST'), findsOneWidget);
      expect(find.text('UNKNOWN'), findsOneWidget);
      await tester.tap(find.byTooltip('Chi tiết FUTURE'));
      await tester.pumpAndSettle();
      expect(find.text('Điều khoản lãi suất theo tài liệu nguồn: Chưa có dữ liệu'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.close();
    },
  );
}
