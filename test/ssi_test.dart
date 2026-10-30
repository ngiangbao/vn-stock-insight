import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/ssi.dart';
import 'package:vn_stock_insight/state.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-ssi';
}

// Thứ Sáu 30/10/2026, 10:00 giờ Việt Nam = 03:00 UTC
final _now = DateTime.utc(2026, 10, 30, 3);

String _jwt(DateTime exp) {
  String b(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b({'alg': 'none'})}.${b({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

http.Response _json(Object o, [int code = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(o)), code, headers: {'content-type': 'application/json'});

Map<String, dynamic> _ohlc(String date, {String close = '52500'}) => {
  'data': [
    {
      'Symbol': 'FPT',
      'Market': 'HOSE',
      'TradingDate': date,
      'Open': '51800',
      'High': '52800',
      'Low': '51600',
      'Close': close,
      'Volume': '3200100',
      'Value': '1',
    },
  ],
  'message': 'Success',
  'status': 'Success',
  'totalRecord': 1,
};

void main() {
  test('đọc DailyOhlc: giá đồng → nghìn đồng, ngày dd/MM/yyyy, bỏ dòng hỏng', () {
    final m = parseSsiDailyOhlc(
      jsonEncode({
        'data': [
          {'TradingDate': '30/10/2026', 'Open': '51800', 'High': '52800', 'Low': '51600', 'Close': '52500', 'Volume': '3200100'},
          {'TradingDate': 'sai', 'Open': '1', 'High': '1', 'Low': '1', 'Close': '1'},
          {'TradingDate': '29/10/2026', 'Open': '1', 'High': '1', 'Low': '1', 'Close': '0'},
        ],
      }),
    );
    expect(m.keys, ['30/10/2026']);
    final b = m['30/10/2026']!;
    expect((b.o, b.h, b.l, b.c, b.v), (51.8, 52.8, 51.6, 52.5, 3200100));
    expect(vnDate(b.t), '2026-10-30');
    expect(parseSsiDailyOhlc('không phải json'), isEmpty);
    expect(ssiDate(_now), '30/10/2026');
  });

  test('hạn dùng của JWT', () {
    final exp = DateTime.utc(2026, 10, 30, 12);
    expect(jwtExpiry(_jwt(exp)), exp);
    expect(jwtExpiry('khong-phai-jwt'), isNull);
  });

  group('SsiSource', () {
    late int tokenCalls, dataCalls;
    late List<http.Request> reqs;

    SsiSource make({int Function(http.Request)? status, String Function()? tokenBuilder}) {
      tokenCalls = 0;
      dataCalls = 0;
      reqs = [];
      return SsiSource(
        client: MockClient((req) async {
          reqs.add(req);
          if (req.url.path.endsWith('/AccessToken')) {
            tokenCalls++;
            final body = jsonDecode(req.body) as Map;
            if (body['consumerSecret'] != 'good-secret') return _json({'message': 'Invalid consumer', 'status': 401}, 401);
            return _json({
              'message': 'Success',
              'status': 200,
              'data': {'accessToken': tokenBuilder?.call() ?? _jwt(DateTime.now().toUtc().add(const Duration(hours: 8)))},
            });
          }
          dataCalls++;
          final code = status?.call(req) ?? 200;
          if (code != 200) return _json({'message': 'lỗi'}, code);
          return _json(_ohlc('30/10/2026'));
        }),
      )..configure(id: 'cid', secret: 'good-secret', enable: true);
    }

    test('lấy token rồi nến hôm nay, gửi Bearer và ngày dd/MM/yyyy; token và kết quả được lưu đệm', () async {
      final s = make();
      final bar = await s.todayBar('FPT', now: _now);
      expect(bar!.c, 52.5);
      final data = reqs.firstWhere((r) => r.url.path.endsWith('/DailyOhlc'));
      expect(data.headers['Authorization'], startsWith('Bearer '));
      expect(data.url.queryParameters['fromDate'], '30/10/2026');
      expect(data.url.queryParameters['toDate'], '30/10/2026');
      expect(data.url.queryParameters['symbol'], 'FPT');
      expect(s.lastError, isNull);
      expect(s.lastOk, isNotNull);
      // Gọi lại trong 20 giây: dùng bộ nhớ đệm; mã khác: dùng lại token
      await s.todayBar('FPT', now: _now.add(const Duration(seconds: 5)));
      expect(dataCalls, 1);
      await s.todayBar('VNM', now: _now.add(const Duration(seconds: 5)));
      expect(tokenCalls, 1);
      expect(dataCalls, 2);
    });

    test('tắt hoặc thiếu khóa: không gọi mạng', () async {
      final s = make()..configure(enable: false);
      expect(await s.todayBar('FPT', now: _now), isNull);
      final t = make()..configure(secret: '');
      expect(await t.todayBar('FPT', now: _now), isNull);
      expect(tokenCalls + dataCalls, 0);
    });

    test('sai khóa: trả null, ghi lỗi rõ; lỗi liên tục thì tạm dừng 5 phút', () async {
      final s = make()..configure(secret: 'sai');
      expect(await s.todayBar('A', now: _now), isNull);
      expect(s.lastError, contains('SSI từ chối khóa'));
      await s.todayBar('B', now: _now);
      await s.todayBar('C', now: _now);
      final calls = tokenCalls;
      expect(calls, 3);
      await s.todayBar('D', now: _now.add(const Duration(minutes: 1)));
      expect(tokenCalls, calls, reason: 'đang tạm dừng, không dồn yêu cầu');
      await s.todayBar('E', now: _now.add(const Duration(minutes: 6)));
      expect(tokenCalls, calls + 1, reason: 'hết 5 phút thì thử lại');
    });

    test('token hết hạn sớm (401): lấy token mới và thử lại đúng một lần', () async {
      var first = true;
      final s = make(
        status: (r) {
          if (first) {
            first = false;
            return 401;
          }
          return 200;
        },
      );
      final bar = await s.todayBar('FPT', now: _now);
      expect(bar, isNotNull);
      expect(tokenCalls, 2);
      expect(dataCalls, 2);
    });

    test('429: không có nến, ghi lỗi giới hạn yêu cầu', () async {
      final s = make(status: (_) => 429);
      expect(await s.todayBar('FPT', now: _now), isNull);
      expect(s.lastError, contains('429'));
    });

    test('kiểm tra kết nối: thành công đọc phiên gần nhất; sai khóa báo rõ', () async {
      final ok = await make().test(now: _now);
      expect(ok.ok, isTrue);
      expect(ok.message, allOf(contains('Kết nối thành công'), contains('52500'), contains('30/10/2026')));
      final bad = await make().test(now: _now).then((_) => make()..configure(secret: 'sai')).then((s) => s.test(now: _now));
      expect(bad.ok, isFalse);
      expect(bad.message, contains('từ chối'));
      final none = await SsiSource().test();
      expect(none.ok, isFalse);
      expect(none.message, contains('nhập ConsumerID'));
    });

    test('withToday ưu tiên nến SSI: thay nến hôm nay của nguồn khác hoặc thêm mới', () async {
      final old = SsiSource.instance;
      addTearDown(() => SsiSource.instance = old);
      SsiSource.instance = make();
      final yesterday = Bar(DateTime.utc(2026, 10, 29, 2).millisecondsSinceEpoch ~/ 1000, 50, 51, 49, 50.5, 1000);
      final todayOther = Bar(DateTime.utc(2026, 10, 30, 2).millisecondsSinceEpoch ~/ 1000, 1, 1, 1, 1, 1);
      final appended = await withToday([yesterday], 'FPT', 'stock', now: _now);
      expect(appended.length, 2);
      expect(appended.last.c, 52.5);
      final replaced = await withToday([yesterday, todayOther], 'FPT', 'stock', now: _now.add(const Duration(minutes: 1)));
      expect(replaced.length, 2);
      expect(replaced.last.c, 52.5, reason: 'nến hôm nay của nguồn khác bị thay bằng SSI');
      // Cuối tuần (thứ Bảy 31/10): không gọi SSI, giữ nguyên dữ liệu
      final before = dataCalls;
      final weekend = await withToday([yesterday], 'FPT', 'stock', now: DateTime.utc(2026, 10, 31, 3));
      expect(weekend.length, 1);
      expect(dataCalls, before);
    });
  });

  group('lưu khóa SSI trong AppState', () {
    test('lưu, làm sạch và nạp lại; bật tắt được nhớ', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      PathProviderPlatform.instance = _FakePaths();
      final old = SsiSource.instance;
      addTearDown(() => SsiSource.instance = old);
      SsiSource.instance = SsiSource();
      final s = AppState();
      await s.init(startDashboard: false);
      expect(s.ssiEnabled, isFalse);
      await s.setSsi(id: ' abc-123 \n', secret: 'sec​ret');
      await s.setSsi(enabled: true);
      expect((s.ssiId, s.ssiSecret, s.ssiEnabled), ('abc-123', 'secret', true));
      // Mở lại app: nạp từ kho khóa và cài đặt
      SsiSource.instance = SsiSource();
      final s2 = AppState();
      await s2.init(startDashboard: false);
      expect((s2.ssiId, s2.ssiSecret, s2.ssiEnabled), ('abc-123', 'secret', true));
    });
  });
}
