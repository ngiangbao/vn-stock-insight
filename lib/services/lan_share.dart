// Nối máy chủ nội bộ với trạng thái app: bật/tắt, cổng, khoá truy cập (lưu trong SharedPreferences)
// và danh sách dữ liệu được công bố. Chỉ chọn các trường an toàn; không đọc API key hay đường dẫn tệp.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../dashboard.dart';
import '../state.dart';
import 'lan_server.dart';
import 'macro.dart';
import 'market.dart';

const lanDefaultPort = 8787;

class AppLanData implements LanData {
  final AppState state;
  final MacroRepository macro;
  MacroSnapshot? _macro;
  DateTime? _macroAt;
  bool _macroLoading = false;

  @override
  bool allowRemoteAnalysis = false;

  AppLanData(this.state, this.macro);

  void _loadMacro() {
    final at = _macroAt;
    if (_macroLoading || (at != null && DateTime.now().difference(at) < const Duration(minutes: 30))) return;
    _macroLoading = true;
    macro.load().then((s) {
      _macro = s;
      _macroAt = DateTime.now();
    }).catchError((_) {}).whenComplete(() => _macroLoading = false);
  }

  Map<String, dynamic> _snap(Snapshot s) => {
        'symbol': s.symbol,
        'close': s.close,
        'change_1d': s.data['change_1d'],
        'change_1w': s.data['change_1w'],
        'change_1m': s.data['change_1m'],
        'change_3m': s.data['change_3m'],
        'rsi14': s.data['rsi14'],
        'ma20': s.data['ma20'],
        'ma50': s.data['ma50'],
        'vol_ratio': s.data['vol_ratio'],
        'volume': s.data['volume'],
        'date': s.data['date'],
        'tech_score': s.techScore,
        'signals': s.signals,
        'spark': s.spark,
      };

  static bool _http(String link) => link.startsWith('https://') || link.startsWith('http://');

  @override
  Map<String, dynamic> overview() {
    _loadMacro();
    final dash = state.dash;
    final macroSnap = _macro;
    return {
      'updatedAt': state.updatedAt?.toIso8601String(),
      'dashUpdatedAt': dash.updatedAt?.toIso8601String(),
      'serverTime': DateTime.now().toIso8601String(),
      'canRunAnalysis': allowRemoteAnalysis,
      'indices': [
        for (final m in indexMetas)
          if (dash.quotes[m.symbol] case final q? when q.last != null)
            {
              'symbol': m.symbol,
              'name': m.name,
              'desc': m.desc,
              'last': q.last,
              'change': q.change,
              'pct': q.pct,
              'spark': q.spark,
            },
      ],
      'watchlist': [for (final s in state.watchlist) if (state.stocks[s] case final snap?) _snap(snap)],
      'vn30': [for (final s in state.vn30Stocks) _snap(s)],
      'news': [
        for (final n in state.news.take(60))
          {
            'title': n.title,
            'summary': n.summary,
            'source': n.source,
            'published': n.published.toIso8601String(),
            'tickers': n.tickers.toList(),
            if (_http(n.link)) 'link': n.link,
          },
      ],
      'analyses': [
        for (final e in state.analyses.entries)
          {'symbol': e.key, 'created_at': e.value['created_at']},
      ],
      'marketBrief': state.marketBrief,
      'macro': macroSnap == null
          ? null
          : {
              'fetchedAt': macroSnap.fetchedAt.toIso8601String(),
              'tabs': [for (final t in macroTabs) {'title': t.title, 'ids': t.ids}],
              'series': [
                for (final s in macroSnap.series.values)
                  {
                    'id': s.def.id,
                    'title': s.def.title,
                    'unit': s.def.unit,
                    'frequency': s.def.frequency,
                    'source': s.def.sourceName,
                    'decimals': s.def.decimals,
                    'points': [for (final p in s.points) [p.period, p.value, p.forecast ? 1 : 0]],
                  },
              ],
            },
    };
  }

  @override
  List<Bar>? bars(String symbol) =>
      state.stocks[symbol]?.bars ?? state.dash.quotes[symbol]?.bars ?? (symbol == 'VNINDEX' ? state.index?.bars : null);

  @override
  Map<String, dynamic>? analysis(String symbol) {
    final r = state.analyses[symbol];
    if (r == null) return null;
    return {'symbol': symbol, 'created_at': r['created_at'], 'ai': r['ai'], 'result': r['result']};
  }

  @override
  Future<Map<String, dynamic>> runAnalysis(String symbol) async {
    await state.analyzeStock(symbol);
    return analysis(symbol)!;
  }
}

/// Bộ điều khiển dùng ở màn hình Cài đặt: lưu lựa chọn của người dùng và quản lý vòng đời máy chủ.
class LanShare extends ChangeNotifier {
  final SharedPreferences _prefs;
  final AppLanData data;
  late final LanServer server;

  bool enabled = false;
  int preferredPort = lanDefaultPort;
  String? error;
  List<(String, String)> addresses = const [];

  LanShare(AppState state, this._prefs, MacroRepository macro) : data = AppLanData(state, macro) {
    preferredPort = _prefs.getInt('lanPort') ?? lanDefaultPort;
    data.allowRemoteAnalysis = _prefs.getBool('lanAnalysis') ?? false;
    var key = _prefs.getString('lanKey');
    if (key == null || key.length < 20) {
      key = generateAccessKey();
      _prefs.setString('lanKey', key);
    }
    server = LanServer(
      data: data,
      accessKey: key,
      loadAsset: (name) => rootBundle.loadString('assets/web/$name'),
    )..addListener(notifyListeners);
  }

  /// Tự mở lại nếu lần trước người dùng đã bật.
  Future<void> restore() async {
    if (_prefs.getBool('lanEnabled') ?? false) await setEnabled(true);
  }

  String get key => server.accessKey;
  int? get port => server.port;
  bool get allowAnalysis => data.allowRemoteAnalysis;

  Future<void> setEnabled(bool on) async {
    error = null;
    try {
      if (on) {
        await server.start(preferredPort: preferredPort);
        addresses = await lanAddresses();
      } else {
        await server.stop();
      }
      enabled = on;
      await _prefs.setBool('lanEnabled', on);
    } catch (e) {
      enabled = false;
      error = 'Không mở được máy chủ: ${e is SocketException ? e.osError?.message ?? e.message : e}';
      await _prefs.setBool('lanEnabled', false);
    }
    notifyListeners();
  }

  Future<void> setPort(int port) async {
    preferredPort = port.clamp(1024, 65535);
    await _prefs.setInt('lanPort', preferredPort);
    if (enabled) {
      await server.stop();
      await setEnabled(true);
    }
    notifyListeners();
  }

  Future<void> setAllowAnalysis(bool value) async {
    data.allowRemoteAnalysis = value;
    await _prefs.setBool('lanAnalysis', value);
    notifyListeners();
  }

  Future<void> regenerateKey() async {
    final key = generateAccessKey();
    await _prefs.setString('lanKey', key);
    server.accessKey = key;
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    addresses = await lanAddresses();
    notifyListeners();
  }

  /// Link đầy đủ cho một địa chỉ. Khoá nằm trong phần #, trình duyệt không gửi phần này lên máy chủ.
  String urlFor(String ip) => 'http://$ip:${port ?? preferredPort}/#key=$key';

  /// Tự kiểm tra: thử kết nối tới chính IP mạng LAN của máy rồi hỏi một API có khoá.
  Future<String> selfTest(String ip) async {
    final p = port;
    if (p == null) return 'Máy chủ đang tắt.';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:$p/api/state'));
      req.headers.set('X-Access-Key', key);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      await resp.drain<void>();
      return resp.statusCode == 200
          ? 'Kết nối tới $ip:$p thành công.'
          : 'Máy chủ trả mã ${resp.statusCode} khi truy cập $ip:$p.';
    } catch (_) {
      return 'Không kết nối được tới $ip:$p. Có thể tường lửa đang chặn cổng $p.';
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    server.stop().whenComplete(server.dispose);
    super.dispose();
  }
}
