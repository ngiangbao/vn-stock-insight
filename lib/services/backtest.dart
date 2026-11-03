// Kiểm định lịch sử điểm sức khỏe và tính độ rộng thị trường, chạy trong app, kết quả lưu theo ngày (giờ Việt Nam) nên mỗi ngày chỉ tính lại một lần.
//
// Kiểm định: với từng mã, lùi về quá khứ cứ 5 phiên tính lại điểm sức khỏe đúng như thời điểm đó (chỉ dùng dữ liệu đến hôm đó), rồi xem
// lợi suất 20 phiên sau của từng nhóm Mạnh / Trung tính / Yếu. Nếu nhóm Mạnh không hơn nhóm Yếu thì điểm không có giá trị dự báo.
// Mẫu cách nhau 5 phiên nhưng nhìn trước 20 phiên nên chồng lấp, không độc lập; đây là bằng chứng tham khảo, không phải lời khuyên.
//
// Độ rộng: tỷ lệ mã HOSE đóng cửa trên MA50 từng phiên; "hồi từ dưới 20%" = trong 30 phiên gần nhất từng xuống dưới 20% và nay đã trên 20%.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'board.dart';
import 'indicators.dart';
import 'insight.dart';
import 'market.dart';

const _prefsKey = 'backtest_v1';
const backtestVersion = 1; // đổi khi sửa thuật toán điểm hoặc cách kiểm định để bỏ kết quả cũ
const backtestHorizon = 20; // số phiên nhìn trước
const backtestStep = 5; // cách nhau bao nhiêu phiên giữa hai mẫu
const _labels = ['Mạnh', 'Trung tính', 'Yếu'];

/// Thống kê lợi suất [backtestHorizon] phiên sau của một nhóm điểm.
class BucketStat {
  final int n, wins;
  final double sumRet; // tổng lợi suất (%)
  const BucketStat(this.n, this.wins, this.sumRet);
  const BucketStat.empty() : this(0, 0, 0);
  double? get avg => n == 0 ? null : sumRet / n;
  double? get winRate => n == 0 ? null : wins / n * 100;
  BucketStat plus(BucketStat o) => BucketStat(n + o.n, wins + o.wins, sumRet + o.sumRet);
  Map<String, dynamic> toJson() => {'n': n, 'w': wins, 's': sumRet};
  factory BucketStat.fromJson(Map j) => BucketStat((j['n'] as num).toInt(), (j['w'] as num).toInt(), (j['s'] as num).toDouble());
}

/// Kết quả kiểm định điểm sức khỏe: thống kê từng nhóm nhãn.
class HealthBacktest {
  final Map<String, BucketStat> buckets;
  const HealthBacktest(this.buckets);

  BucketStat bucket(String label) => buckets[label] ?? const BucketStat.empty();
  int get samples => buckets.values.fold(0, (a, b) => a + b.n);

  HealthBacktest plus(HealthBacktest o) => HealthBacktest({for (final l in _labels) l: bucket(l).plus(o.bucket(l))});

  /// 'ok': nhóm Mạnh hơn nhóm Yếu rõ rệt; 'fail': nhóm Mạnh không hơn; 'weak': chưa đủ mẫu hoặc chênh lệch nhỏ.
  String get verdict {
    final strong = bucket('Mạnh'), weak = bucket('Yếu');
    if (strong.n < 8 || weak.n < 8) return 'weak';
    final d = strong.avg! - weak.avg!;
    if (d >= 1) return 'ok';
    if (d <= 0) return 'fail';
    return 'weak';
  }

  Map<String, dynamic> toJson() => {for (final e in buckets.entries) e.key: e.value.toJson()};
  factory HealthBacktest.fromJson(Map j) => HealthBacktest({
    for (final l in _labels)
      if (j[l] is Map) l: BucketStat.fromJson(j[l] as Map),
  });
}

/// Kiểm định điểm sức khỏe của [bars] so với [index] trên toàn bộ lịch sử. Null nếu chưa đủ dữ liệu (cần ít nhất 60 + [backtestHorizon] phiên).
HealthBacktest? backtestHealth(List<Bar> bars, List<Bar> index) {
  if (bars.length < 60 + backtestHorizon + backtestStep) return null;
  final acc = {for (final l in _labels) l: const BucketStat.empty()};
  for (var i = bars.length - 1 - backtestHorizon; i >= 59; i -= backtestStep) {
    final upTo = bars.sublist(0, i + 1);
    final idx = index.where((b) => b.t <= bars[i].t).toList();
    final score = healthTotal(upTo, idx);
    if (score == null || bars[i].c == 0) continue;
    final label = healthLabel(score);
    final ret = (bars[i + backtestHorizon].c / bars[i].c - 1) * 100;
    acc[label] = acc[label]!.plus(BucketStat(1, ret > 0 ? 1 : 0, ret));
  }
  final r = HealthBacktest(acc);
  return r.samples == 0 ? null : r;
}

/// Độ rộng thị trường: tỷ lệ % mã đóng cửa trên MA50 trong [days] phiên gần nhất (cũ → mới), từ giá các mã [all].
List<double> breadthSeries(Iterable<List<Bar>> all, {int days = 60}) {
  // Tập ngày lấy từ mã có nhiều phiên nhất
  final list = all.where((b) => b.length >= 55).toList();
  if (list.isEmpty) return const [];
  final ref = list.reduce((a, b) => a.length >= b.length ? a : b);
  final dates = [for (final b in ref.sublist(ref.length > days ? ref.length - days : 0)) b.t];
  final above = {for (final t in dates) t: 0}, total = {for (final t in dates) t: 0};
  for (final bars in list) {
    final ma = smaSeries([for (final b in bars) b.c], 50);
    for (var i = 0; i < bars.length; i++) {
      final m = ma[i];
      if (m == null || !total.containsKey(bars[i].t)) continue;
      total[bars[i].t] = total[bars[i].t]! + 1;
      if (bars[i].c > m) above[bars[i].t] = above[bars[i].t]! + 1;
    }
  }
  return [
    for (final t in dates)
      if (total[t]! >= 10) above[t]! / total[t]! * 100,
  ];
}

/// Như [backtestHealth] nhưng chạy trong Isolate riêng (tính cả lịch sử nhiều năm nên nặng), không làm đứng giao diện.
Future<HealthBacktest?> backtestHealthAsync(List<Bar> bars, List<Bar> index) => Isolate.run(() => backtestHealth(bars, index));

/// Như [breadthSeries] nhưng chạy trong Isolate riêng (hàng trăm mã × MA50).
Future<List<double>> breadthSeriesAsync(List<List<Bar>> all, {int days = 60}) => Isolate.run(() => breadthSeries(all, days: days));

/// Dấu hiệu "độ rộng hồi từ dưới 20%" từ chuỗi [series] (cũ → mới), null nếu chưa đủ dữ liệu.
BottomSignal breadthSignal(List<double> series, {int universe = 0}) {
  if (series.length < 30) return const BottomSignal(breadthLabel, null, note: 'chưa đủ dữ liệu thị trường');
  final recent = series.sublist(series.length - 30);
  final low = recent.reduce((a, b) => a < b ? a : b), now = series.last;
  final met = low < 20 && now > 20;
  return BottomSignal(
    breadthLabel,
    met,
    note:
        'hiện ${now.toStringAsFixed(0)}% mã trên MA50, thấp nhất 30 phiên ${low.toStringAsFixed(0)}%'
        '${universe > 0 ? ' · $universe mã HOSE' : ''}',
  );
}

enum BacktestState { none, queued, running, done, failed }

typedef BarsFetcher = Future<List<Bar>> Function(String symbol, {bool isIndex, int days});

Future<List<Bar>> _defaultFetch(String symbol, {bool isIndex = false, int days = 1500}) => fetchBars(symbol, isIndex: isIndex, days: days);

Future<List<String>> _defaultUniverse() async => [for (final r in await fetchBoard('HOSE')) r.symbol];

/// Hàng đợi kiểm định, lưu theo ngày. Mã trong danh sách theo dõi chạy trước, rồi đến mã người dùng mở xem; độ rộng thị trường chạy sau cùng.
class BacktestStore extends ChangeNotifier {
  final SharedPreferences? _prefs;
  final BarsFetcher _fetch;
  final Future<List<String>> Function() _universe;
  final DateTime Function() _now;
  final int parallel;

  /// Tắt khi không muốn tự tải dữ liệu mạng (kiểm thử).
  bool enabled;

  String _day = '';
  final Map<String, HealthBacktest?> _results = {}; // null: đã chạy nhưng chưa đủ dữ liệu
  final Map<String, BacktestState> _state = {};
  final List<String> _watch = [], _clicked = [];
  final Map<String, bool> _isIndex = {};
  List<double>? _breadth;
  int _breadthUniverse = 0;
  bool _breadthRunning = false, _breadthFailed = false, _breadthWanted = false;
  int _active = 0;
  List<Bar>? _indexBars;

  BacktestStore(
    this._prefs, {
    BarsFetcher? fetch,
    Future<List<String>> Function()? universe,
    DateTime Function()? now,
    this.parallel = 3,
    this.enabled = true,
  }) : _fetch = fetch ?? _defaultFetch,
       _universe = universe ?? _defaultUniverse,
       _now = now ?? DateTime.now {
    _load();
  }

  String get today => vnDate(_now().millisecondsSinceEpoch ~/ 1000);

  void _load() {
    try {
      final raw = _prefs?.getString(_prefsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['v'] != backtestVersion || m['day'] != today) return; // sang ngày mới thì tính lại
      _day = m['day'] as String;
      for (final e in (m['results'] as Map).entries) {
        _results[e.key as String] = e.value == null ? null : HealthBacktest.fromJson(e.value as Map);
        _state[e.key as String] = BacktestState.done;
      }
      final b = m['breadth'];
      if (b is Map) {
        _breadth = [for (final x in b['series'] as List) (x as num).toDouble()];
        _breadthUniverse = (b['n'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      _results.clear();
      _state.clear();
      _breadth = null;
    }
  }

  Future<void> _save() async {
    try {
      await _prefs?.setString(
        _prefsKey,
        jsonEncode({
          'v': backtestVersion,
          'day': _day.isEmpty ? today : _day,
          'results': {for (final e in _results.entries) e.key: e.value?.toJson()},
          if (_breadth != null) 'breadth': {'series': _breadth, 'n': _breadthUniverse},
        }),
      );
    } catch (_) {
      // không lưu được thì lần sau tính lại
    }
  }

  /// Sang ngày mới (app mở qua đêm): bỏ kết quả hôm qua.
  void _rollDay() {
    final t = today;
    if (_day.isNotEmpty && _day != t) {
      _results.removeWhere((k, _) => _state[k] == BacktestState.done);
      _state.removeWhere((k, v) => v == BacktestState.done || v == BacktestState.failed);
      _breadth = null;
      _breadthFailed = false;
    }
    _day = t;
  }

  BacktestState stateOf(String symbol) {
    if (_day.isNotEmpty && _day != today && _state[symbol] == BacktestState.done) return BacktestState.none;
    return _state[symbol] ?? BacktestState.none;
  }

  HealthBacktest? resultOf(String symbol) => stateOf(symbol) == BacktestState.done ? _results[symbol] : null;

  /// Gộp mọi mã đã kiểm định hôm nay: bằng chứng chung chắc hơn từng mã riêng lẻ.
  (HealthBacktest, int)? get pooled {
    var acc = const HealthBacktest({});
    var n = 0;
    for (final e in _results.entries) {
      if (e.value == null || _state[e.key] != BacktestState.done) continue;
      acc = acc.plus(e.value!);
      n++;
    }
    return n == 0 ? null : (acc, n);
  }

  List<double>? get breadth => _breadth;
  bool get breadthRunning => _breadthRunning || (_breadth == null && !_breadthFailed && _breadthWanted);
  bool get breadthFailed => _breadthFailed;

  /// Dấu hiệu độ rộng cho trang chi tiết: có số liệu thì kết luận, đang tính hoặc lỗi thì ghi chú rõ.
  BottomSignal get breadthBottomSignal {
    final b = _breadth;
    if (b != null) return breadthSignal(b, universe: _breadthUniverse);
    if (_breadthFailed) return const BottomSignal(breadthLabel, null, note: 'không tải được giá thị trường');
    return const BottomSignal(breadthLabel, null, note: 'đang tính độ rộng thị trường…');
  }

  /// Xếp danh sách theo dõi vào hàng đợi ưu tiên cao.
  void enqueueWatchlist(Iterable<String> symbols) {
    if (!enabled) return;
    _rollDay();
    for (final s in symbols) {
      _enqueue(s, _watch);
    }
    _breadthWanted = true;
    _pump();
    notifyListeners();
  }

  /// Mã người dùng mở xem: chạy sau danh sách theo dõi.
  void request(String symbol, {bool isIndex = false}) {
    if (!enabled) return;
    _rollDay();
    _isIndex[symbol] = isIndex;
    _enqueue(symbol, _clicked);
    _breadthWanted = true;
    _pump();
    notifyListeners();
  }

  void _enqueue(String s, List<String> q) {
    final st = _state[s];
    if (st == BacktestState.done || st == BacktestState.running || st == BacktestState.queued) return;
    _state[s] = BacktestState.queued;
    q.add(s);
  }

  void _pump() {
    while (_active < parallel && (_watch.isNotEmpty || _clicked.isNotEmpty)) {
      // Mã được mở xem nằm sau danh sách theo dõi, trừ khi danh sách theo dõi đã hết
      final s = _watch.isNotEmpty ? _watch.removeAt(0) : _clicked.removeAt(0);
      if (_state[s] != BacktestState.queued) continue;
      _active++;
      _state[s] = BacktestState.running;
      unawaited(_run(s));
    }
    if (_active == 0 && _watch.isEmpty && _clicked.isEmpty) _maybeBreadth();
  }

  Future<void> _run(String symbol) async {
    try {
      _indexBars ??= await _fetch('VNINDEX', isIndex: true, days: 1500);
      final bars = await _fetch(symbol, isIndex: _isIndex[symbol] ?? false, days: 1500);
      if (bars.isEmpty) throw StateError('không tải được giá');
      _results[symbol] = await backtestHealthAsync(bars, _indexBars!);
      _state[symbol] = BacktestState.done;
      await _save();
    } catch (_) {
      _state[symbol] = BacktestState.failed;
    } finally {
      _active--;
      notifyListeners();
      _pump();
    }
  }

  Future<void> _maybeBreadth() async {
    if (_breadth != null || _breadthRunning || _breadthFailed || !_breadthWanted) return;
    _breadthRunning = true;
    notifyListeners();
    try {
      final symbols = await _universe();
      final all = <List<Bar>>[];
      final queue = [...symbols];
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final s = queue.removeLast();
          try {
            final bars = await _fetch(s, isIndex: false, days: 200);
            if (bars.length >= 55) all.add(bars);
          } catch (_) {
            // bỏ qua mã lỗi
          }
        }
      }

      await Future.wait(List.generate(6, (_) => worker()));
      final series = await breadthSeriesAsync(all);
      if (series.length < 30 || all.length < 50) throw StateError('quá ít mã');
      _breadth = series;
      _breadthUniverse = all.length;
      await _save();
    } catch (_) {
      _breadthFailed = true;
    } finally {
      _breadthRunning = false;
      notifyListeners();
      _pump();
    }
  }
}
