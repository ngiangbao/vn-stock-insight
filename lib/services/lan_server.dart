// Máy chủ nội bộ: cho phép xem dữ liệu của app trên thiết bị khác cùng mạng LAN (chỉ đọc).
// Mặc định TẮT. Bảo mật: khoá truy cập ngẫu nhiên, chỉ nhận nguồn từ mạng nội bộ, kiểm tra Host,
// chặn IP sai khoá nhiều lần, chỉ GET. Không bao giờ trả API key hay đường dẫn tệp.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'market.dart' show Bar;

/// Nguồn dữ liệu máy chủ được phép công bố. Mọi trường trả ra phải được chọn tường minh (danh sách trắng).
abstract class LanData {
  /// Toàn bộ trạng thái hiển thị trên trang web (đã loại dữ liệu nhạy cảm).
  Map<String, dynamic> overview();

  /// Nến ngày đã có trong bộ nhớ; null nếu mã chưa được app tải.
  List<Bar>? bars(String symbol);

  /// Kết quả phân tích AI đã lưu (symbol, created_at, ai, result); null nếu chưa có.
  Map<String, dynamic>? analysis(String symbol);

  /// Cho phép thiết bị khác yêu cầu chạy phân tích AI (tốn API của chủ máy). Mặc định tắt.
  bool get allowRemoteAnalysis;

  Future<Map<String, dynamic>> runAnalysis(String symbol);
}

/// Địa chỉ thuộc mạng nội bộ: loopback, RFC1918, CGNAT 100.64/10 (Tailscale), link-local, IPv6 ULA/link-local.
bool isLanAddress(InternetAddress a) {
  if (a.isLoopback) return true;
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 169 && b[1] == 254);
  }
  // IPv4 ánh xạ vào IPv6 (::ffff:a.b.c.d)
  if (b.length == 16 && b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff) {
    return isLanAddress(InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))));
  }
  return (b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
}

/// So sánh chuỗi không phụ thuộc thời gian (không dừng sớm khi gặp ký tự khác).
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  final n = math.max(x.length, y.length);
  for (var i = 0; i < n; i++) {
    diff |= (i < x.length ? x[i] : 0) ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

/// Khoá ngẫu nhiên 128 bit, mã hoá base64url (22 ký tự).
String generateAccessKey([math.Random? random]) {
  final r = random ?? math.Random.secure();
  return base64Url.encode([for (var i = 0; i < 16; i++) r.nextInt(256)]).replaceAll('=', '');
}

class LanClient {
  final String ip;
  final DateTime firstSeen;
  DateTime lastSeen;
  int requests = 0;
  String userAgent = '';
  LanClient(this.ip, this.firstSeen) : lastSeen = firstSeen;
}

class _Failures {
  final List<DateTime> times = [];
  DateTime? blockedUntil;
}

typedef AssetLoader = Future<String> Function(String name);

class LanServer extends ChangeNotifier {
  LanServer({
    required this.data,
    required String accessKey,
    required this.loadAsset,
    bool Function(InternetAddress)? allowSource,
    DateTime Function()? now,
    this.maxFailures = 8,
    this.failureWindow = const Duration(minutes: 10),
    this.blockFor = const Duration(minutes: 15),
  })  : _key = accessKey,
        allowSource = allowSource ?? isLanAddress,
        _now = now ?? DateTime.now;

  final LanData data;
  final AssetLoader loadAsset;
  final bool Function(InternetAddress) allowSource;
  final DateTime Function() _now;
  final int maxFailures;
  final Duration failureWindow, blockFor;

  String _key;
  HttpServer? _server;
  final _failures = <String, _Failures>{};
  final _clients = <String, LanClient>{};
  final _assets = <String, String>{};
  bool _analysing = false;

  String get accessKey => _key;
  set accessKey(String value) {
    _key = value;
    _clients.clear();
    notifyListeners();
  }

  bool get running => _server != null;
  int? get port => _server?.port;
  List<LanClient> get clients {
    final cutoff = _now().subtract(const Duration(minutes: 2));
    return [for (final c in _clients.values) if (c.lastSeen.isAfter(cutoff)) c]
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  }

  /// Mở máy chủ ở cổng [preferredPort]; nếu bận thì thử các cổng kế tiếp. Trả về cổng thực tế.
  Future<int> start({int preferredPort = 8787, InternetAddress? address}) async {
    if (_server != null) return _server!.port;
    Object? last;
    for (var i = 0; i < 20; i++) {
      final p = preferredPort == 0 ? 0 : preferredPort + i;
      try {
        final s = await HttpServer.bind(address ?? InternetAddress.anyIPv4, p);
        s.idleTimeout = const Duration(seconds: 15);
        _server = s;
        s.listen((req) => _handle(req).catchError((_) {}), onError: (_) {});
        notifyListeners();
        return s.port;
      } on SocketException catch (e) {
        last = e;
        if (preferredPort == 0) break;
      }
    }
    throw last ?? StateError('Không mở được cổng');
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _clients.clear();
    await s?.close(force: true);
    notifyListeners();
  }

  // ---------- Xử lý yêu cầu ----------

  static const _types = {
    'index.html': 'text/html; charset=utf-8',
    'app.js': 'text/javascript; charset=utf-8',
    'app.css': 'text/css; charset=utf-8',
    'favicon.svg': 'image/svg+xml',
  };

  void _secure(HttpResponse r) {
    r.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()')
      ..set('Cache-Control', 'no-store')
      ..set(
        'Content-Security-Policy',
        "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
            "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      );
  }

  Future<void> _send(HttpResponse r, int status, String body, {String type = 'text/plain; charset=utf-8'}) async {
    r.statusCode = status;
    r.headers.contentType = ContentType.parse(type);
    r.write(body);
    await r.close();
  }

  Future<void> _json(HttpResponse r, int status, Object? body) async {
    var text = '{}';
    try {
      text = jsonEncode(_finite(body));
    } catch (_) {
      status = 500;
      text = '{"error":"Không tạo được dữ liệu"}';
    }
    await _send(r, status, text, type: 'application/json; charset=utf-8');
  }

  /// JSON không chấp nhận NaN/Infinity: đổi thành null.
  static Object? _finite(Object? v) => switch (v) {
        double d when !d.isFinite => null,
        Map m => {for (final e in m.entries) e.key.toString(): _finite(e.value)},
        Iterable l => [for (final x in l) _finite(x)],
        _ => v,
      };

  /// Host hợp lệ: IP nội bộ, localhost, hoặc tên *.local / *.ts.net. Chặn tên miền lạ (DNS rebinding).
  bool hostAllowed(String? header) {
    if (header == null || header.isEmpty) return false;
    final uri = Uri.tryParse('http://$header');
    final host = uri?.host.toLowerCase();
    if (host == null || host.isEmpty) return false;
    final ip = InternetAddress.tryParse(host);
    if (ip != null) return isLanAddress(ip);
    return host == 'localhost' || host.endsWith('.local') || host.endsWith('.ts.net');
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    _secure(res);
    final remote = req.connectionInfo?.remoteAddress;
    if (remote == null || !allowSource(remote)) {
      return _send(res, 403, 'Chỉ nhận yêu cầu từ mạng nội bộ.');
    }
    if (!hostAllowed(req.headers.value(HttpHeaders.hostHeader))) {
      return _send(res, 403, 'Host không hợp lệ.');
    }
    if (req.method != 'GET') {
      res.headers.set(HttpHeaders.allowHeader, 'GET');
      return _send(res, 405, 'Chỉ cho phép GET.');
    }
    final path = req.uri.path;
    if (path == '/favicon.ico') {
      res.statusCode = 204;
      return res.close();
    }
    if (path.startsWith('/api/')) return _api(req, remote);
    final name = switch (path) {
      '/' || '/index.html' => 'index.html',
      '/app.js' => 'app.js',
      '/app.css' => 'app.css',
      '/favicon.svg' => 'favicon.svg',
      _ => null,
    };
    if (name == null) return _send(res, 404, 'Không tìm thấy.');
    try {
      final body = _assets[name] ??= await loadAsset(name);
      await _send(res, 200, body, type: _types[name]!);
    } catch (_) {
      await _send(res, 500, 'Không đọc được trang.');
    }
  }

  Future<void> _api(HttpRequest req, InternetAddress remote) async {
    final res = req.response;
    final ip = remote.address;
    final failure = _failures[ip];
    final now = _now();
    if (failure?.blockedUntil != null) {
      if (now.isBefore(failure!.blockedUntil!)) {
        res.headers.set(HttpHeaders.retryAfterHeader, failure.blockedUntil!.difference(now).inSeconds.toString());
        return _json(res, 429, {'error': 'Sai khoá quá nhiều lần. Thử lại sau.'});
      }
      _failures.remove(ip);
    }
    final auth = req.headers.value('authorization');
    final given = req.headers.value('x-access-key') ??
        (auth != null && auth.startsWith('Bearer ') ? auth.substring(7) : null) ??
        req.uri.queryParameters['key'];
    if (given == null || given.isEmpty) {
      return _json(res, 401, {'error': 'Cần khoá truy cập.'});
    }
    if (!constantTimeEquals(given, _key)) {
      final f = _failures.putIfAbsent(ip, _Failures.new);
      f.times
        ..removeWhere((t) => now.difference(t) > failureWindow)
        ..add(now);
      if (f.times.length >= maxFailures) f.blockedUntil = now.add(blockFor);
      return _json(res, 401, {'error': 'Khoá truy cập không đúng.'});
    }
    _failures.remove(ip);
    final client = _clients.putIfAbsent(ip, () => LanClient(ip, now));
    final firstContact = client.requests == 0;
    client
      ..lastSeen = now
      ..requests += 1
      ..userAgent = _short(req.headers.value('user-agent'));
    if (firstContact) notifyListeners();

    final segments = req.uri.pathSegments;
    try {
      if (segments.length == 2 && segments[1] == 'state') {
        return await _json(res, 200, data.overview());
      }
      if (segments.length == 2 && segments[1] == 'bars') {
        final symbol = _symbol(req.uri.queryParameters['symbol']);
        final bars = symbol == null ? null : data.bars(symbol);
        if (bars == null) return await _json(res, 404, {'error': 'Không có dữ liệu cho mã này.'});
        final tail = bars.length > 400 ? bars.sublist(bars.length - 400) : bars;
        return await _json(res, 200, {
          'symbol': symbol,
          'bars': [for (final b in tail) [b.t, b.o, b.h, b.l, b.c, b.v]],
        });
      }
      if (segments.length == 3 && segments[1] == 'analysis') {
        final symbol = _symbol(segments[2]);
        if (symbol == null) return await _json(res, 404, {'error': 'Mã không hợp lệ.'});
        if (req.uri.queryParameters['run'] == '1') {
          if (!data.allowRemoteAnalysis) {
            return await _json(res, 403, {'error': 'Chủ máy chưa cho phép chạy phân tích AI từ thiết bị khác.'});
          }
          if (_analysing) return await _json(res, 429, {'error': 'Đang có một phân tích khác chạy. Thử lại sau.'});
          _analysing = true;
          try {
            return await _json(res, 200, await data.runAnalysis(symbol));
          } catch (e) {
            return await _json(res, 502, {'error': 'Phân tích không thành công.'});
          } finally {
            _analysing = false;
          }
        }
        final record = data.analysis(symbol);
        if (record == null) return await _json(res, 404, {'error': 'Chưa có phân tích đã lưu cho mã này.'});
        return await _json(res, 200, record);
      }
      return await _json(res, 404, {'error': 'Không tìm thấy.'});
    } catch (_) {
      return await _json(res, 500, {'error': 'Lỗi máy chủ.'});
    }
  }

  static String _short(String? s) => s == null ? '' : (s.length > 120 ? s.substring(0, 120) : s);

  static final _symbolPattern = RegExp(r'^[A-Z0-9]{3,10}$');
  static String? _symbol(String? raw) {
    final s = raw?.toUpperCase();
    return s != null && _symbolPattern.hasMatch(s) ? s : null;
  }
}

/// Địa chỉ IPv4 của từng giao diện mạng (bỏ loopback), dùng để dựng link cho thiết bị khác.
Future<List<(String name, String ip)>> lanAddresses() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    return [
      for (final i in list)
        for (final a in i.addresses)
          if (isLanAddress(a)) (i.name, a.address),
    ];
  } catch (_) {
    return const [];
  }
}
