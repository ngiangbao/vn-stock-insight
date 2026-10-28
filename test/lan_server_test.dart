// Kiểm thử máy chủ nội bộ bằng socket thật (không dùng widget test).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vn_stock_insight/dashboard.dart';
import 'package:vn_stock_insight/services/lan_server.dart';
import 'package:vn_stock_insight/services/lan_share.dart';
import 'package:vn_stock_insight/services/macro.dart';
import 'package:vn_stock_insight/services/market.dart';
import 'package:vn_stock_insight/services/news.dart';
import 'package:vn_stock_insight/state.dart';

class _FakePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/tmp/vnsi-test-secret-dir';
}

const _secretKey = 'sk-ant-SECRET-API-KEY-1234567890';
const _accessKey = 'abcdefghijklmnopqrstuv';

class _Reply {
  final int status;
  final String body;
  final HttpHeaders headers;
  _Reply(this.status, this.body, this.headers);
  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

Future<_Reply> _get(int port, String path, {String? key, String? host, String method = 'GET', bool bearer = false}) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (host != null) req.headers.set(HttpHeaders.hostHeader, host);
    if (key != null) bearer ? req.headers.set('Authorization', 'Bearer $key') : req.headers.set('X-Access-Key', key);
    final r = await req.close();
    final body = await utf8.decodeStream(r);
    return _Reply(r.statusCode, body, r.headers);
  } finally {
    c.close(force: true);
  }
}

List<Bar> _bars(int n) => [
      for (var i = 0; i < n; i++) Bar(1790000000 + i * 86400, 50 + i * .1, 52 + i * .1, 49 + i * .1, 51 + i * .1 + (i % 5), 1e6 + i),
    ];

void main() {
  late AppState state;
  late LanShare share;
  late LanServer server;
  late int port;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // dùng socket thật thay vì HttpClient giả của flutter_test
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePaths();
    state = AppState();
    await state.init(startDashboard: false);
    await state.setProviderConfig('anthropic', apiKey: _secretKey, baseUrl: 'https://api.example.com');
    final bars = _bars(300);
    state.stocks = {'FPT': analyze('FPT', bars), 'VCB': analyze('VCB', bars)};
    state.watchlist = ['FPT', 'VCB'];
    state.index = analyze('VNINDEX', bars);
    state.news = [
      NewsItem('FPT lãi lớn', 'Tóm tắt', 'https://cafef.vn/a.html', 'CafeF', DateTime.utc(2026, 10, 29), {'FPT'}),
      NewsItem('Tin xấu', 'x', 'javascript:alert(1)', 'Nguồn', DateTime.utc(2026, 10, 29), {}),
    ];
    state.updatedAt = DateTime.utc(2026, 10, 29, 3);
    state.dash.quotes = {for (final m in indexMetas) m.symbol: IndexQuote(m, bars)};
    state.marketBrief = {'summary': 'Thị trường đi ngang', 'outlook': 'Trung lập'};
    state.analyses = {
      'FPT': {
        'symbol': 'FPT',
        'created_at': '2026-10-29T02:00:00.000Z',
        'ai': 'Anthropic · claude-test',
        'inputs': {'x': 1},
        'result': {'signal': 'hold', 'summary': 'Giữ'},
      },
    };
    share = LanShare(state, await SharedPreferences.getInstance(), MacroRepository());
    server = LanServer(
      data: share.data,
      accessKey: _accessKey,
      loadAsset: (n) => File('assets/web/$n').readAsString(),
      maxFailures: 3,
    );
    port = await server.start(preferredPort: 0, address: InternetAddress.loopbackIPv4);
  });

  tearDownAll(() async {
    await server.stop();
    share.dispose();
    state.dash.dispose();
  });

  test('phân loại địa chỉ mạng nội bộ', () {
    bool ok(String a) => isLanAddress(InternetAddress(a));
    for (final a in ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.0.234', '100.64.0.1', '100.127.9.9', '169.254.1.1', '::1', 'fe80::1', 'fd12::1', '::ffff:192.168.1.5']) {
      expect(ok(a), isTrue, reason: a);
    }
    for (final a in ['8.8.8.8', '172.32.0.1', '172.15.0.1', '100.63.0.1', '100.128.0.1', '11.0.0.1', '192.169.0.1', '2001:4860:4860::8888', '::ffff:8.8.8.8']) {
      expect(ok(a), isFalse, reason: a);
    }
  });

  test('so sánh khoá và tạo khoá 128 bit', () {
    expect(constantTimeEquals('abc', 'abc'), isTrue);
    expect(constantTimeEquals('abc', 'abd'), isFalse);
    expect(constantTimeEquals('abc', 'abcd'), isFalse);
    final k = generateAccessKey();
    expect(k.length, 22); // 16 byte base64url
    expect(generateAccessKey(), isNot(k));
  });

  test('trang chủ và tài nguyên tĩnh không cần khoá, kèm header bảo mật', () async {
    for (final p in ['/', '/app.js', '/app.css', '/favicon.svg']) {
      final r = await _get(port, p);
      expect(r.status, 200, reason: p);
      expect(r.headers.value('x-content-type-options'), 'nosniff');
      expect(r.headers.value('x-frame-options'), 'DENY');
      expect(r.headers.value('referrer-policy'), 'no-referrer');
      expect(r.headers.value('content-security-policy'), allOf(contains("default-src 'none'"), contains("frame-ancestors 'none'")));
    }
    expect((await _get(port, '/')).headers.contentType?.mimeType, 'text/html');
    expect((await _get(port, '/khong-co')).status, 404);
  });

  test('API cần khoá: thiếu hoặc sai là 401, đúng là 200', () async {
    expect((await _get(port, '/api/state')).status, 401);
    expect((await _get(port, '/api/state', key: 'sai-khoa')).status, 401);
    expect((await _get(port, '/api/state', key: _accessKey)).status, 200);
    expect((await _get(port, '/api/state', key: _accessKey, bearer: true)).status, 200);
    expect((await _get(port, '/api/state?key=$_accessKey')).status, 200);
  });

  test('chỉ cho phép GET', () async {
    for (final m in ['POST', 'PUT', 'DELETE', 'PATCH']) {
      final r = await _get(port, '/api/state', key: _accessKey, method: m);
      expect(r.status, 405, reason: m);
      expect(r.headers.value('allow'), 'GET');
    }
  });

  test('kiểm tra Host chống DNS rebinding', () async {
    expect((await _get(port, '/api/state', key: _accessKey, host: 'evil.example.com')).status, 403);
    expect((await _get(port, '/', host: 'attacker.com:8787')).status, 403);
    expect((await _get(port, '/', host: '8.8.8.8')).status, 403);
    expect((await _get(port, '/', host: '192.168.0.234:$port')).status, 200);
    expect((await _get(port, '/', host: 'localhost:$port')).status, 200);
    expect((await _get(port, '/', host: 'may-tinh.local')).status, 200);
  });

  test('hình dạng JSON của /api/state', () async {
    final j = (await _get(port, '/api/state', key: _accessKey)).json;
    expect(j['indices'], isA<List>());
    expect((j['indices'] as List).length, indexMetas.length);
    expect((j['indices'] as List).first, containsPair('symbol', 'VNINDEX'));
    expect((j['watchlist'] as List).map((e) => e['symbol']), ['FPT', 'VCB']);
    expect((j['vn30'] as List), isNotEmpty);
    final news = j['news'] as List;
    expect(news.first['link'], 'https://cafef.vn/a.html');
    expect(news[1].containsKey('link'), isFalse, reason: 'link không phải http(s) bị bỏ');
    expect(j['marketBrief'], containsPair('summary', 'Thị trường đi ngang'));
    expect(j['analyses'], [containsPair('symbol', 'FPT')]);
    expect(j['canRunAnalysis'], false);
    expect(j.containsKey('updatedAt'), isTrue);
  });

  test('/api/bars, /api/analysis và mã không hợp lệ', () async {
    final bars = (await _get(port, '/api/bars?symbol=fpt', key: _accessKey)).json;
    expect(bars['symbol'], 'FPT');
    expect((bars['bars'] as List).length, 300);
    expect((bars['bars'] as List).first, hasLength(6));
    expect((await _get(port, '/api/bars?symbol=ZZZ', key: _accessKey)).status, 404);
    expect((await _get(port, '/api/bars?symbol=../etc/passwd', key: _accessKey)).status, 404);
    expect((await _get(port, '/api/bars', key: _accessKey)).status, 404);
    final a = (await _get(port, '/api/analysis/FPT', key: _accessKey)).json;
    expect(a.keys.toSet(), {'symbol', 'created_at', 'ai', 'result'});
    expect((await _get(port, '/api/analysis/VCB', key: _accessKey)).status, 404);
  });

  test('chạy phân tích AI từ thiết bị khác bị tắt mặc định', () async {
    final r = await _get(port, '/api/analysis/VCB?run=1', key: _accessKey);
    expect(r.status, 403);
  });

  test('không có API key hay đường dẫn tệp trong bất kỳ phản hồi nào', () async {
    final paths = [
      '/', '/app.js', '/app.css', '/favicon.svg', '/khong-co',
      '/api/state', '/api/bars?symbol=FPT', '/api/analysis/FPT', '/api/analysis/VCB', '/api/analysis/VCB?run=1', '/api/loi',
    ];
    for (final p in paths) {
      for (final key in [_accessKey, null, 'sai']) {
        final r = await _get(port, p, key: key);
        for (final bad in [_secretKey, 'SECRET-API-KEY', '/tmp/vnsi', 'secret-dir', state.dataDir.path, '/home/']) {
          expect(r.body.contains(bad), isFalse, reason: '$p chứa "$bad"');
        }
        expect(r.headers.toString().contains(_secretKey), isFalse);
      }
    }
    expect(state.keyOf('anthropic'), _secretKey, reason: 'phép thử có thật sự đặt khoá');
  });

  test('danh sách thiết bị ghi nhận yêu cầu có khoá đúng', () async {
    await _get(port, '/api/state', key: _accessKey);
    expect(server.clients.map((c) => c.ip), contains('127.0.0.1'));
  });

  test('từ chối nguồn không phải mạng nội bộ', () async {
    final strict = LanServer(
      data: share.data,
      accessKey: _accessKey,
      loadAsset: (n) async => 'x',
      allowSource: (a) => !a.isLoopback && isLanAddress(a),
    );
    final p = await strict.start(preferredPort: 0, address: InternetAddress.loopbackIPv4);
    try {
      expect((await _get(p, '/')).status, 403);
      expect((await _get(p, '/api/state', key: _accessKey)).status, 403);
    } finally {
      await strict.stop();
    }
  });

  test('chặn IP sau nhiều lần sai khoá rồi mở lại khi hết hạn', () async {
    var now = DateTime.utc(2026, 10, 29, 3);
    final s = LanServer(data: share.data, accessKey: _accessKey, loadAsset: (n) async => 'x', now: () => now, maxFailures: 3);
    final p = await s.start(preferredPort: 0, address: InternetAddress.loopbackIPv4);
    try {
      for (var i = 0; i < 3; i++) {
        expect((await _get(p, '/api/state', key: 'sai$i')).status, 401);
      }
      final blocked = await _get(p, '/api/state', key: _accessKey);
      expect(blocked.status, 429, reason: 'khoá đúng cũng bị chặn khi IP đang bị khoá');
      expect(blocked.headers.value('retry-after'), isNotNull);
      now = now.add(const Duration(minutes: 16));
      expect((await _get(p, '/api/state', key: _accessKey)).status, 200);
    } finally {
      await s.stop();
    }
  });

  test('đổi khoá làm khoá cũ mất hiệu lực', () async {
    final s = LanServer(data: share.data, accessKey: 'khoa-cu-khoa-cu-khoa-cu', loadAsset: (n) async => 'x');
    final p = await s.start(preferredPort: 0, address: InternetAddress.loopbackIPv4);
    try {
      expect((await _get(p, '/api/state', key: 'khoa-cu-khoa-cu-khoa-cu')).status, 200);
      s.accessKey = 'khoa-moi-khoa-moi-khoa-moi';
      expect((await _get(p, '/api/state', key: 'khoa-cu-khoa-cu-khoa-cu')).status, 401);
      expect((await _get(p, '/api/state', key: 'khoa-moi-khoa-moi-khoa-moi')).status, 200);
    } finally {
      await s.stop();
    }
  });

  test('cổng bận thì thử cổng kế tiếp', () async {
    final busy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final s = LanServer(data: share.data, accessKey: _accessKey, loadAsset: (n) async => 'x');
    try {
      final p = await s.start(preferredPort: busy.port, address: InternetAddress.loopbackIPv4);
      expect(p, isNot(busy.port));
    } finally {
      await s.stop();
      await busy.close();
    }
  });
}
