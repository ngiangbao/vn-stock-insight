// Nguồn giá tùy chọn từ SSI FastConnect Data (cần ConsumerID và ConsumerSecret của tài khoản SSI do người dùng tự đăng ký).
//
// Dùng để lấy nến của ngày hôm nay (mở, cao, thấp, đóng, khối lượng) cho cổ phiếu, ghi đè nến hôm nay của nguồn mặc định khi SSI trả về.
// Mọi lỗi (sai khóa, hết hạn, giới hạn yêu cầu, mạng) đều bị nuốt: app quay về nguồn mặc định, trạng thái lỗi hiện trong Cài đặt.
//
// API (theo tài liệu guide.ssi.com.vn): POST /api/v2/Market/AccessToken {consumerID, consumerSecret} → data.accessToken;
// GET /api/v2/Market/DailyOhlc?symbol&fromDate&toDate&pageIndex&pageSize&ascending với ngày dd/MM/yyyy, giá tính bằng đồng.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market.dart' show Bar;

const ssiBase = 'https://fc-data.ssi.com.vn/api/v2/Market';

/// dd/MM/yyyy theo giờ Việt Nam.
String ssiDate(DateTime t) {
  final v = t.toUtc().add(const Duration(hours: 7));
  return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
}

double? _num(dynamic x) => x == null ? null : double.tryParse('$x');

/// Chuyển phản hồi DailyOhlc thành các nến (giá đồng → nghìn đồng) theo ngày dd/MM/yyyy → nến.
Map<String, Bar> parseSsiDailyOhlc(String body) {
  final out = <String, Bar>{};
  try {
    final j = jsonDecode(body) as Map;
    for (final r in ((j['data'] as List?) ?? const []).cast<Map>()) {
      final date = '${r['TradingDate']}';
      final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(date);
      final o = _num(r['Open']), h = _num(r['High']), l = _num(r['Low']), c = _num(r['Close']), v = _num(r['Volume']);
      if (m == null || c == null || c <= 0 || o == null || h == null || l == null) continue;
      // 02:00 UTC = 09:00 giờ Việt Nam: cùng ngày giao dịch ở mọi múi giờ
      final t = DateTime.utc(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!), 2).millisecondsSinceEpoch ~/ 1000;
      out[date] = Bar(t, o / 1000, h / 1000, l / 1000, c / 1000, v ?? 0);
    }
  } catch (_) {}
  return out;
}

/// Hạn dùng (exp) của JWT, null nếu không đọc được.
DateTime? jwtExpiry(String token) {
  try {
    final p = token.split('.');
    if (p.length < 2) return null;
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(p[1])))) as Map;
    final exp = json['exp'];
    return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true) : null;
  } catch (_) {
    return null;
  }
}

class SsiTestResult {
  final bool ok;
  final String message;
  const SsiTestResult(this.ok, this.message);
}

class SsiSource {
  /// Bản dùng chung trong app (cấu hình từ Cài đặt).
  static SsiSource instance = SsiSource(); // gán lại được trong kiểm thử

  String? consumerId, consumerSecret;
  bool enabled = false;
  final http.Client? _injected;
  SsiSource({http.Client? client}) : _injected = client;

  String? _token;
  DateTime? _tokenExpiry;
  Future<String>? _tokenInFlight;
  final _cache = <String, (DateTime, Bar?)>{};
  int _fails = 0;
  DateTime? _pausedUntil;

  /// Lỗi gần nhất (null nếu lần gọi gần nhất thành công) và thời điểm thành công gần nhất, để hiện trong Cài đặt.
  String? lastError;
  DateTime? lastOk;

  bool get active => enabled && (consumerId?.isNotEmpty ?? false) && (consumerSecret?.isNotEmpty ?? false);

  void configure({String? id, String? secret, bool? enable}) {
    final changed = (id != null && id != consumerId) || (secret != null && secret != consumerSecret);
    if (id != null) consumerId = id.trim();
    if (secret != null) consumerSecret = secret.trim();
    if (enable != null) enabled = enable;
    if (changed) {
      _token = null;
      _tokenExpiry = null;
      _cache.clear();
      _fails = 0;
      _pausedUntil = null;
    }
  }

  Future<T> _withClient<T>(Future<T> Function(http.Client c) f) async {
    final c = _injected ?? http.Client();
    try {
      return await f(c);
    } finally {
      if (_injected == null) c.close();
    }
  }

  Future<String> _accessToken({bool force = false}) {
    final valid =
        _token != null && !force && (_tokenExpiry == null || _tokenExpiry!.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 2))));
    if (valid) return Future.value(_token);
    return _tokenInFlight ??= _fetchToken().whenComplete(() => _tokenInFlight = null);
  }

  Future<String> _fetchToken() => _withClient((c) async {
    final r = await c
        .post(
          Uri.parse('$ssiBase/AccessToken'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'consumerID': consumerId, 'consumerSecret': consumerSecret}),
        )
        .timeout(const Duration(seconds: 15));
    final body = utf8.decode(r.bodyBytes);
    Map? j;
    try {
      j = jsonDecode(body) as Map;
    } catch (_) {}
    final token = (j?['data'] as Map?)?['accessToken'] as String?;
    if (r.statusCode != 200 || token == null || token.isEmpty) {
      final msg = j?['message'];
      throw SsiException(
        r.statusCode == 401 || r.statusCode == 403 || (j?['status'] != null && '${j?['status']}' != '200')
            ? 'SSI từ chối khóa: ${msg ?? 'HTTP ${r.statusCode}'}. Kiểm tra ConsumerID, ConsumerSecret, hạn dịch vụ và IP đã đăng ký.'
            : 'Không lấy được token SSI (HTTP ${r.statusCode}${msg == null ? '' : ': $msg'}).',
      );
    }
    _token = token;
    _tokenExpiry = jwtExpiry(token) ?? DateTime.now().toUtc().add(const Duration(minutes: 50));
    return token;
  });

  Future<http.Response> _get(String path, Map<String, String> query) => _withClient((c) async {
    Future<http.Response> once(String token) => c
        .get(
          Uri.parse('$ssiBase/$path').replace(queryParameters: query),
          headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    var r = await once(await _accessToken());
    if (r.statusCode == 401) r = await once(await _accessToken(force: true)); // token hết hạn sớm: lấy lại một lần
    return r;
  });

  /// Nến hôm nay của cổ phiếu [symbol] từ SSI, null nếu SSI tắt, lỗi hoặc chưa có giao dịch. Lưu đệm 20 giây mỗi mã.
  Future<Bar?> todayBar(String symbol, {DateTime? now}) async {
    if (!active) return null;
    final clock = now ?? DateTime.now();
    if (_pausedUntil != null && clock.isBefore(_pausedUntil!)) return null;
    final cached = _cache[symbol];
    if (cached != null && clock.difference(cached.$1).inSeconds < 20) return cached.$2;
    try {
      final d = ssiDate(clock);
      final r = await _get('DailyOhlc', {
        'symbol': symbol,
        'fromDate': d,
        'toDate': d,
        'pageIndex': '1',
        'pageSize': '10',
        'ascending': 'false',
      });
      if (r.statusCode != 200) {
        throw SsiException('SSI trả về HTTP ${r.statusCode}${r.statusCode == 429 ? ' (vượt giới hạn yêu cầu)' : ''}.');
      }
      final bar = parseSsiDailyOhlc(utf8.decode(r.bodyBytes))[d];
      _cache[symbol] = (clock, bar);
      _fails = 0;
      lastError = null;
      lastOk = clock;
      return bar;
    } catch (e) {
      lastError = e is SsiException ? e.message : 'Không kết nối được SSI: $e';
      if (++_fails >= 3) _pausedUntil = clock.add(const Duration(minutes: 5)); // tránh dồn yêu cầu khi SSI lỗi liên tục
      return null;
    }
  }

  /// Kiểm tra khóa: lấy token rồi đọc phiên gần nhất của [symbol] (lùi tối đa 10 ngày để qua cuối tuần/ngày lễ).
  Future<SsiTestResult> test({String symbol = 'FPT', DateTime? now}) async {
    if (!(consumerId?.isNotEmpty ?? false) || !(consumerSecret?.isNotEmpty ?? false)) {
      return const SsiTestResult(false, 'Hãy nhập ConsumerID và ConsumerSecret.');
    }
    try {
      final clock = now ?? DateTime.now();
      await _accessToken(force: true);
      final r = await _get('DailyOhlc', {
        'symbol': symbol,
        'fromDate': ssiDate(clock.subtract(const Duration(days: 10))),
        'toDate': ssiDate(clock),
        'pageIndex': '1',
        'pageSize': '10',
        'ascending': 'false',
      });
      if (r.statusCode != 200) {
        return SsiTestResult(
          false,
          'Lấy được token nhưng đọc giá lỗi (HTTP ${r.statusCode}). Dịch vụ có thể chưa bật quyền FastConnect Data.',
        );
      }
      final bars = parseSsiDailyOhlc(utf8.decode(r.bodyBytes));
      if (bars.isEmpty) return const SsiTestResult(true, 'Kết nối thành công nhưng chưa có dữ liệu giá trong 10 ngày gần đây.');
      final latest = (bars.entries.toList()..sort((a, b) => b.value.t.compareTo(a.value.t))).first;
      lastError = null;
      lastOk = clock;
      return SsiTestResult(true, 'Kết nối thành công: $symbol đóng cửa ${(latest.value.c * 1000).round()} đ ngày ${latest.key}.');
    } catch (e) {
      final msg = e is SsiException ? e.message : 'Không kết nối được SSI: $e';
      lastError = msg;
      return SsiTestResult(false, msg);
    }
  }
}

class SsiException implements Exception {
  final String message;
  SsiException(this.message);
  @override
  String toString() => message;
}
