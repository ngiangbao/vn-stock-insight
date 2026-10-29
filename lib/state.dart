// Trạng thái chung của app: cài đặt, dữ liệu thị trường, danh sách theo dõi, kết quả phân tích.
// Mọi thứ lưu trên máy người dùng; API key lưu trong kho bảo mật của hệ điều hành.

import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/prompts.dart';
import 'dashboard.dart';
import 'ai/providers.dart';
import 'services/fundamentals.dart';
import 'services/lan_share.dart';
import 'services/macro.dart';
import 'services/llama_runtime.dart';
import 'services/market.dart';
import 'services/news.dart';
import 'ui/chart.dart' show ChartType, Indicator;

const defaultWatchlist = ['FPT', 'VCB', 'HPG', 'MWG', 'TCB', 'SSI'];

String _vietnamDayKey(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 7));
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage();
  bool secureStorageOk = true;

  // ---------- Cài đặt ----------
  ThemeMode themeMode = ThemeMode.system;
  String providerId = 'anthropic';
  String effort = 'medium';
  bool autoCheckUpdates = true;
  bool autoScale = true;
  final Map<String, String> _baseUrls = {}, _models = {}, _keys = {};

  ProviderPreset get provider => presetById(providerId);
  String baseUrlOf(String id) => _baseUrls[id] ?? presetById(id).baseUrl;
  String modelOf(String id) => _models[id] ?? presetById(id).defaultModel;
  String keyOf(String id) => _keys[id] ?? '';

  AiConfig get aiConfig => AiConfig(provider, baseUrlOf(providerId), modelOf(providerId), keyOf(providerId), effort: effort);
  String get aiLabel => providerId == 'embedded'
      ? '${provider.name} · ${embeddedModel == null ? 'chưa chọn model' : embeddedModel!.split(Platform.pathSeparator).last}'
      : '${provider.name} · ${modelOf(providerId).isEmpty ? 'chưa chọn model' : modelOf(providerId)}';

  // ---------- Biểu đồ ----------
  ChartType chartType = ChartType.candle;
  Set<Indicator> chartIndicators = {Indicator.ma20, Indicator.ma50, Indicator.volume};

  void setChartType(ChartType t) {
    chartType = t;
    _prefs.setString('chartType', t.name);
    notifyListeners();
  }

  void toggleIndicator(Indicator i) {
    chartIndicators = chartIndicators.contains(i) ? ({...chartIndicators}..remove(i)) : {...chartIndicators, i};
    _prefs.setStringList('chartIndicators', [for (final x in chartIndicators) x.name]);
    notifyListeners();
  }

  // ---------- Model chạy trong app ----------
  late final Directory dataDir;
  late final LlamaRuntime runtime;
  late final MarketDashboard dash;
  late final LanShare lan;
  String? embeddedModel; // đường dẫn file GGUF đang dùng
  String? engineStatus;
  double? engineProgress;

  Directory get modelsDir => Directory('${dataDir.path}${Platform.pathSeparator}models');

  void setEmbeddedModel(String? path) {
    embeddedModel = path;
    path == null ? _prefs.remove('embeddedModel') : _prefs.setString('embeddedModel', path);
    notifyListeners();
  }

  void _engine(String? status, double? progress) {
    engineStatus = status;
    engineProgress = progress;
    notifyListeners();
  }

  /// Cấu hình AI để gọi. Với model chạy trong app: tự cài/cập nhật engine và nạp model nếu cần.
  Future<AiConfig> resolveAiConfig() async {
    if (providerId != 'embedded') return aiConfig;
    final model = embeddedModel;
    if (model == null || !File(model).existsSync()) {
      throw AiException('Chưa chọn model chạy trong app. Vào Cài đặt → Model trên máy để tải và chọn model.');
    }
    try {
      final url = await runtime.start(model, onStatus: _engine);
      return AiConfig(provider, url, 'local', '');
    } finally {
      _engine(null, null);
    }
  }

  /// Kiểm tra và cập nhật engine ở chế độ nền (khi đã từng cài).
  Future<void> _autoUpdateEngine() async {
    try {
      if (!embeddedSupported || await runtime.installed() == null) return;
      if (await runtime.needsUpdate()) {
        await runtime.ensureInstalled(onStatus: _engine);
        _engine(null, null);
      }
    } catch (_) {
      _engine(null, null);
    }
  }

  // ---------- Dữ liệu ----------
  List<String> watchlist = [...defaultWatchlist];
  Snapshot? index;
  Map<String, Snapshot> stocks = {};
  List<NewsItem> news = [];
  bool loading = false;
  String? loadError;
  DateTime? updatedAt;

  Map<String, dynamic>? marketBrief;
  bool briefLoading = false;
  String? briefError;

  /// Kết quả phân tích chuyên sâu đã lưu: mã → {created_at, ai, inputs, result}
  Map<String, Map<String, dynamic>> analyses = {};

  Timer? _liveTimer;

  Future<void> init({bool startDashboard = true}) async {
    _prefs = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.byName(_prefs.getString('theme') ?? 'system');
    providerId = _prefs.getString('provider') ?? 'anthropic';
    effort = _prefs.getString('effort') ?? 'medium';
    autoCheckUpdates = _prefs.getBool('autoUpdate') ?? true;
    autoScale = _prefs.getBool('autoScale') ?? true;
    uiScale = _prefs.getDouble('uiScale');
    for (final p in providers) {
      final url = _prefs.getString('url_${p.id}');
      final model = _prefs.getString('model_${p.id}');
      if (url != null) _baseUrls[p.id] = url;
      if (model != null) _models[p.id] = model;
      final key = await _readKey(p.id);
      if (key != null) _keys[p.id] = key;
    }
    watchlist = _prefs.getStringList('watchlist') ?? [...defaultWatchlist];
    chartType = ChartType.values.asNameMap()[_prefs.getString('chartType')] ?? ChartType.candle;
    final inds = _prefs.getStringList('chartIndicators');
    if (inds != null) chartIndicators = {for (final n in inds) ?Indicator.values.asNameMap()[n]};
    embeddedModel = _prefs.getString('embeddedModel');
    dataDir = await getApplicationSupportDirectory();
    dash = MarketDashboard(File('${dataDir.path}${Platform.pathSeparator}sectors.json'));
    dash.addListener(notifyListeners);
    runtime = LlamaRuntime(dataDir, () => rootBundle.loadString('assets/runtime.json'));
    lan = LanShare(this, _prefs, MacroRepository(cacheFile: File('${dataDir.path}${Platform.pathSeparator}macro_cache.json')));
    _autoUpdateEngine();
    if (startDashboard) {
      dash.start();
      // Giá cổ phiếu/chỉ số theo dõi cập nhật trong phiên (bảng giá đã tự làm mới ở dash)
      _liveTimer ??= Timer.periodic(const Duration(seconds: 90), (_) {
        if (isTradingTime(DateTime.now())) refresh();
      });
    }
    await _loadAnalyses();
    if (startDashboard) lan.restore();
    notifyListeners();
  }

  // Một số máy Linux không có dịch vụ keyring: khi đó lưu tạm trong cài đặt của app.
  Future<String?> _readKey(String id) async {
    try {
      return await _secure.read(key: 'key_$id');
    } catch (_) {
      secureStorageOk = false;
      return _prefs.getString('key_$id');
    }
  }

  Future<void> _writeKey(String id, String value) async {
    try {
      await _secure.write(key: 'key_$id', value: value);
    } catch (_) {
      secureStorageOk = false;
      await _prefs.setString('key_$id', value);
    }
  }

  void setTheme(ThemeMode mode) {
    themeMode = mode;
    _prefs.setString('theme', mode.name);
    notifyListeners();
  }

  void setProvider(String id) {
    providerId = id;
    _prefs.setString('provider', id);
    notifyListeners();
  }

  void setEffort(String value) {
    effort = value;
    _prefs.setString('effort', value);
    notifyListeners();
  }

  void setAutoScale(bool value) {
    autoScale = value;
    _prefs.setBool('autoScale', value);
    notifyListeners();
  }

  /// Cỡ giao diện chọn tay (0.8 = 80%); null = tự động theo cửa sổ.
  double? uiScale;

  void setUiScale(double? value) {
    uiScale = value?.clamp(0.6, 1.6).toDouble();
    uiScale == null ? _prefs.remove('uiScale') : _prefs.setDouble('uiScale', uiScale!);
    notifyListeners();
  }

  void setAutoCheckUpdates(bool value) {
    autoCheckUpdates = value;
    _prefs.setBool('autoUpdate', value);
    notifyListeners();
  }

  Future<void> setProviderConfig(String id, {String? baseUrl, String? model, String? apiKey}) async {
    if (baseUrl != null) {
      _baseUrls[id] = baseUrl.trim();
      await _prefs.setString('url_$id', baseUrl.trim());
    }
    if (model != null) {
      _models[id] = model.trim();
      await _prefs.setString('model_$id', model.trim());
    }
    if (apiKey != null) {
      _keys[id] = apiKey.trim();
      await _writeKey(id, apiKey.trim());
    }
    notifyListeners();
  }

  // ---------- Danh sách theo dõi ----------
  static final symbolPattern = RegExp(r'^[A-Z0-9]{3,10}$');

  Future<void> addWatch(String symbol) async {
    if (watchlist.contains(symbol)) return;
    watchlist = [...watchlist, symbol];
    await _prefs.setStringList('watchlist', watchlist);
    notifyListeners();
    if (!stocks.containsKey(symbol)) {
      final bars = await fetchBars(symbol);
      if (bars.length >= 2) {
        stocks = {...stocks, symbol: analyze(symbol, bars)};
        notifyListeners();
      }
    }
  }

  Future<void> removeWatch(String symbol) async {
    watchlist = watchlist.where((s) => s != symbol).toList();
    await _prefs.setStringList('watchlist', watchlist);
    notifyListeners();
  }

  // ---------- Dữ liệu thị trường ----------
  Future<void> refresh() async {
    if (loading) return;
    dash.refresh();
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final symbols = {...vn30, ...watchlist};
      final results = await Future.wait([
        fetchMany(symbols),
        fetchBars('VNINDEX', isIndex: true),
        fetchNews(symbols),
      ]);
      stocks = results[0] as Map<String, Snapshot>;
      final idx = results[1] as List<Bar>;
      index = idx.length >= 2 ? analyze('VNINDEX', idx) : null;
      news = results[2] as List<NewsItem>;
      updatedAt = DateTime.now();
      if (stocks.isEmpty) loadError = 'Không lấy được dữ liệu giá. Kiểm tra kết nối mạng.';
    } catch (e) {
      loadError = 'Lỗi tải dữ liệu: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<Snapshot> get vn30Stocks => [for (final s in vn30) ?stocks[s]];

  // ---------- AI ----------
  Map<String, dynamic>? analysisForToday(String symbol, {DateTime? now}) {
    final record = analyses[symbol];
    final created = DateTime.tryParse(record?['created_at']?.toString() ?? '');
    if (record == null || created == null || _vietnamDayKey(created) != _vietnamDayKey(now ?? DateTime.now())) return null;
    return record;
  }

  Future<void> _loadAnalyses() async {
    final file = File('${dataDir.path}${Platform.pathSeparator}analyses.json');
    try {
      if (await file.exists()) {
        analyses = _decodeAnalyses(await file.readAsString());
        return;
      }
    } catch (_) {
      // A damaged local cache falls back to the previous preferences store.
    }
    final legacy = _prefs.getString('analyses');
    if (legacy != null) {
      try {
        analyses = _decodeAnalyses(legacy);
      } catch (_) {
        analyses = {};
      }
    }
  }

  Map<String, Map<String, dynamic>> _decodeAnalyses(String source) =>
      (jsonDecode(source) as Map<String, dynamic>).map((key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)));

  Future<void> _saveAnalyses() async {
    final encoded = jsonEncode(analyses);
    final file = File('${dataDir.path}${Platform.pathSeparator}analyses.json');
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
      await _prefs.remove('analyses');
    } catch (_) {
      // Preserve the old storage path as a fallback if the support directory is unavailable.
      await _prefs.setString('analyses', encoded);
    }
  }

  Future<void> runMarketBrief() async {
    if (index == null) return;
    briefLoading = true;
    briefError = null;
    notifyListeners();
    try {
      final movers = vn30Stocks
          .map((s) => '${s.symbol}: ${s.close} (${s.data['change_1d']}% hôm nay, ${s.data['change_1m']}% 1 tháng)'
              '${s.signals.isEmpty ? '' : ', tín hiệu: ${s.signals.join(', ')}'}')
          .join('\n');
      marketBrief = await generateJson(
        await resolveAiConfig(),
        system: marketSystem,
        prompt: marketPrompt(index!.toPromptJson(), movers, news.take(30).map((n) => n.toPromptJson()).toList()),
        schema: marketSchema,
        schemaName: 'market_brief',
      );
    } catch (e) {
      briefError = e.toString();
    } finally {
      briefLoading = false;
      notifyListeners();
    }
  }

  /// Phân tích chuyên sâu một mã. Ném lỗi để giao diện hiển thị.
  Future<Map<String, dynamic>> analyzeStock(String symbol, {bool force = false}) async {
    final cached = analysisForToday(symbol);
    if (!force && cached != null) return cached;
    final bars = await fetchBars(symbol);
    if (bars.length < 30) throw AiException('Không tìm thấy dữ liệu giá cho mã $symbol.');
    final snap = analyze(symbol, bars);
    stocks = {...stocks, symbol: snap};
    final inputs = {
      'technicals': snap.toPromptJson(),
      'fundamentals': await fetchFundamentals(symbol),
      'news': newsFor(news, symbol).map((n) => n.toPromptJson()).toList(),
    };
    final result = await generateJson(
      await resolveAiConfig(),
      system: stockSystem,
      prompt: stockPrompt(symbol, inputs),
      schema: stockSchema,
      schemaName: 'stock_analysis',
    );
    final record = {
      'symbol': symbol,
      'created_at': DateTime.now().toIso8601String(),
      'ai': aiLabel,
      'inputs': inputs,
      'result': result,
    };
    analyses = {...analyses, symbol: record};
    // Giữ tối đa 100 mã gần nhất; các kết quả được lưu riêng theo người dùng.
    if (analyses.length > 100) {
      final keep = analyses.entries.toList()
      ..sort((a, b) => (b.value['created_at'] as String).compareTo(a.value['created_at'] as String));
      analyses = Map.fromEntries(keep.take(100));
    }
    await _saveAnalyses();
    notifyListeners();
    return record;
  }
}

/// Đưa AppState xuống cây widget.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
