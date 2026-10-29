import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/main.dart' show appTheme;
import 'package:vn_stock_insight/services/rates.dart';
import 'package:vn_stock_insight/state.dart';
import 'package:vn_stock_insight/ui/rates_tab.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-rates';
}

const _cafef = {
  'Data': [
    {
      'name': 'AAA',
      'interestRates': [
        {'time': '6T', 'deposit': 6, 'value': 5.0},
        {'time': '12T', 'deposit': 12, 'value': 6.0},
        {'time': '0T', 'deposit': 0, 'value': 0.1},
      ],
    },
    {
      'name': 'BBB',
      'interestRates': [
        {'time': '6T', 'deposit': 6, 'value': 5.4},
        {'time': '12T', 'deposit': 12, 'value': 6.6},
        {'time': '24T', 'deposit': 24, 'value': null},
      ],
    },
  ],
};

http.Client _client({bool tvOk = true, bool cafefOk = true}) => MockClient((req) async {
  if (req.url.host == 'scanner.tradingview.com') {
    if (!tvOk) return http.Response('x', 500);
    final sym = req.url.queryParameters['symbol']!;
    final v = switch (sym) {
      'TVC:VN10Y' => 4.58,
      'TVC:VN01Y' => 3.68,
      'ECONOMICS:VNINTR' => 4.5,
      'ECONOMICS:VNINBR' => 7.43,
      'ECONOMICS:VNIRYY' => 5.08,
      _ => null,
    };
    if (v == null) return http.Response('{"code":"symbol_not_exists"}', 200);
    return http.Response(jsonEncode({'close': v, 'time': 1793059200}), 200);
  }
  return cafefOk ? http.Response.bytes(utf8.encode(jsonEncode(_cafef)), 200) : http.Response('x', 500);
});

void main() {
  test('đọc phản hồi TradingView và bảng lãi suất tiền gửi CafeF', () {
    final r = parseScannerSymbol('{"close":4.581,"time":1793221200}')!;
    expect(r.value, 4.581);
    expect(r.date, '2026-10-28');
    expect(parseScannerSymbol('{"code":"symbol_not_exists"}'), isNull);
    expect(parseScannerSymbol('không phải json'), isNull);

    final d = parseDeposits(jsonEncode(_cafef));
    expect(d[12]!.avg, closeTo(6.3, 1e-9));
    expect(d[12]!.min, 6.0);
    expect(d[12]!.max, 6.6);
    expect(d[12]!.bestBank, 'BBB');
    expect(d[6]!.banks, 2);
    expect(d.containsKey(24), isFalse, reason: 'giá trị trống bị bỏ');
    expect(d.containsKey(1), isFalse);
  });

  test('lãi suất thực = lãi suất danh nghĩa trừ CPI; lưu bản đã dùng khi mạng lỗi; lịch sử theo ngày', () async {
    final dir = await Directory.systemTemp.createTemp('rates');
    RatesRepository repo(http.Client c) =>
        RatesRepository(cacheFile: File('${dir.path}/c.json'), historyFile: File('${dir.path}/h.json'), client: c, maxAge: Duration.zero);

    final s = await repo(_client()).load(force: true);
    expect(s.y10, 4.58);
    expect(s.cpiYoy, 5.08);
    expect(s.real10y, closeTo(-0.5, 1e-9));
    expect(s.realDeposit12, closeTo(6.3 - 5.08, 1e-9));
    expect(s.realPolicy, closeTo(4.5 - 5.08, 1e-9));
    expect(s.interbank, 7.43);
    expect(s.interbankDate, '2026-10-27');
    expect(s.failed, contains('Lợi suất 2N'), reason: 'kỳ hạn không có dữ liệu được báo là không tải được');

    // Mạng lỗi toàn bộ: giữ nguyên số liệu đã lưu, không ghi đè bằng rỗng
    final offline = await repo(_client(tvOk: false, cafefOk: false)).load(force: true);
    expect(offline.y10, 4.58);
    expect(offline.dep12, closeTo(6.3, 1e-9));
    expect(offline.real10y, closeTo(-0.5, 1e-9));

    // Lịch sử có số liệu hôm nay, chưa có "ngày trước"
    final h = await repo(_client()).history();
    expect(h.values.single['y10'], 4.58);
    expect(await repo(_client()).previousDay(), isNull);
    await dir.delete(recursive: true);
  });

  testWidgets('tab Lãi suất hằng ngày: thẻ cùng kích thước, lãi suất thực, ghi chú lãi suất cho vay', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    final state = AppState();
    await tester.runAsync(() => state.init(startDashboard: false));
    final repo = RatesRepository(client: _client(), maxAge: Duration.zero);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: ThemeMode.dark,
          home: Scaffold(body: RatesTab(repository: repo)),
        ),
      ),
    );
    for (var i = 0; i < 20 && find.text('Đang tải lãi suất…').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Đường cong lợi suất trái phiếu chính phủ'), findsOneWidget);
    expect(find.text('Lãi suất thực (tự tính)'), findsOneWidget);
    expect(find.text('Lãi suất cho vay'), findsOneWidget);
    expect(find.textContaining('Chưa có nguồn công khai cập nhật hằng ngày'), findsOneWidget);
    expect(find.text('−0,5%'), findsWidgets, reason: 'lãi suất thực 10 năm âm hiển thị dấu trừ');
    final cards = find.byType(Card);
    expect(cards, findsNWidgets(7));
    final sizes = {for (var i = 0; i < 7; i++) tester.getSize(cards.at(i))};
    expect(sizes.length, 1, reason: 'mọi thẻ cùng kích thước');
    expect(tester.getSize(find.byTooltip('Làm mới lãi suất')).shortestSide, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
