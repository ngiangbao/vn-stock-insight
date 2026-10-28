// Giá ngày và chỉ báo kỹ thuật. Nguồn chính DNSE, dự phòng VNDirect.
// Giá tính theo nghìn đồng (56.2 = 56.200đ).

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

const userAgent = {'User-Agent': 'Mozilla/5.0 (vn-stock-insight)'};

/// Rổ VN30 dùng cho tổng quan và bộ lọc. Rổ được điều chỉnh mỗi 6 tháng.
const vn30 = [
  'ACB', 'BCM', 'BID', 'BVH', 'CTG', 'FPT', 'GAS', 'GVR', 'HDB', 'HPG', //
  'LPB', 'MBB', 'MSN', 'MWG', 'PLX', 'SAB', 'SHB', 'SSB', 'SSI', 'STB',
  'TCB', 'TPB', 'VCB', 'VHM', 'VIB', 'VIC', 'VJC', 'VNM', 'VPB', 'VRE',
];

class Bar {
  final int t;
  final double o, h, l, c, v;
  const Bar(this.t, this.o, this.h, this.l, this.c, this.v);
}

/// Chuyển phản hồi biểu đồ của DNSE ({t, o, h, l, c, v}) thành danh sách nến.
List<Bar> parseBars(Map<String, dynamic> d) {
  final t = (d['t'] as List?) ?? const [];
  double n(String k, int i) => (d[k][i] as num).toDouble();
  return [
    for (var i = 0; i < t.length; i++)
      Bar((t[i] as num).toInt(), n('o', i), n('h', i), n('l', i), n('c', i), n('v', i)),
  ];
}

/// [kind]: 'stock' (mặc định), 'index' hoặc 'derivative' (VN30F1M). [resolution]: '1D' hoặc số phút ('1').
Future<List<Bar>> fetchBars(String symbol,
    {int days = 400, bool isIndex = false, String? kind, String resolution = '1D'}) async {
  final end = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final start = end - days * 86400;
  final k = kind ?? (isIndex ? 'index' : 'stock');
  if (k == 'world') return resolution == '1D' ? fetchWorldBars(symbol, days: days) : const [];
  final urls = [
    'https://services.entrade.com.vn/chart-api/v2/ohlcs/$k'
        '?from=$start&to=$end&symbol=$symbol&resolution=$resolution',
    if (resolution == '1D' && k != 'derivative')
      'https://dchart-api.vndirect.com.vn/dchart/history?resolution=D&symbol=$symbol&from=$start&to=$end',
  ];
  for (final url in urls) {
    try {
      final resp = await http.get(Uri.parse(url), headers: userAgent).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) continue;
      final bars = parseBars(jsonDecode(resp.body) as Map<String, dynamic>);
      if (bars.isNotEmpty) return bars;
    } catch (_) {
      // thử nguồn tiếp theo
    }
  }
  return const [];
}

/// Chỉ số thế giới từ Yahoo Finance ([symbol] là mã Yahoo như ^GSPC): nến ngày, tối đa 5 năm gần nhất.
Future<List<Bar>> fetchWorldBars(String symbol, {int days = 1900}) async {
  final range = days <= 400 ? '2y' : '5y';
  try {
    final resp = await http
        .get(Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}?range=$range&interval=1d'), headers: userAgent)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return const [];
    return parseYahooBars(jsonDecode(resp.body) as Map<String, dynamic>);
  } catch (_) {
    return const [];
  }
}

/// Chuyển phản hồi biểu đồ của Yahoo Finance thành nến ngày, bỏ các ngày thiếu giá.
List<Bar> parseYahooBars(Map<String, dynamic> json) {
  final result = ((json['chart'] as Map?)?['result'] as List?)?.firstOrNull as Map?;
  if (result == null) return const [];
  final t = (result['timestamp'] as List?) ?? const [];
  final q = (((result['indicators'] as Map?)?['quote'] as List?)?.firstOrNull as Map?) ?? const {};
  num? at(String k, int i) {
    final l = q[k];
    return l is List && i < l.length && l[i] is num ? l[i] as num : null;
  }

  return [
    for (var i = 0; i < t.length; i++)
      if (at('close', i) case final c?)
        Bar((t[i] as num).toInt(), (at('open', i) ?? c).toDouble(), (at('high', i) ?? c).toDouble(), (at('low', i) ?? c).toDouble(),
            c.toDouble(), (at('volume', i) ?? 0).toDouble()),
  ];
}

/// Ngày giao dịch (giờ Việt Nam) của một nến: yyyy-MM-dd.
String vnDate(int t) =>
    DateTime.fromMillisecondsSinceEpoch((t + 7 * 3600) * 1000, isUtc: true).toIso8601String().substring(0, 10);

/// Nến 1 phút của phiên gần nhất (ngoài giờ giao dịch là phiên đã đóng cửa gần nhất).
Future<List<Bar>> fetchIntraday(String symbol, {String kind = 'index'}) async {
  final bars = await fetchBars(symbol, days: 5, kind: kind, resolution: '1');
  return lastSession(bars);
}

List<Bar> lastSession(List<Bar> bars) {
  if (bars.isEmpty) return bars;
  final day = vnDate(bars.last.t);
  return bars.where((b) => vnDate(b.t) == day).toList();
}

double _avg(Iterable<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

double? _sma(List<double> xs, int n) => xs.length >= n ? _avg(xs.sublist(xs.length - n)) : null;

double? _round(double? x, [int d = 2]) {
  if (x == null || !x.isFinite) return null;
  final p = math.pow(10, d);
  return (x * p).round() / p;
}

double? _pct(double? a, double? b) => (a == null || b == null || b == 0) ? null : _round((a / b - 1) * 100);

List<double> _ema(List<double> xs, int n) {
  final k = 2 / (n + 1);
  final out = [xs.first];
  for (final x in xs.skip(1)) {
    out.add(x * k + out.last * (1 - k));
  }
  return out;
}

double? _rsi(List<double> closes, [int n = 14]) {
  if (closes.length <= n) return null;
  var gain = 0.0, loss = 0.0;
  for (var i = 1; i <= n; i++) {
    final d = closes[i] - closes[i - 1];
    gain += math.max(d, 0);
    loss += math.max(-d, 0);
  }
  gain /= n;
  loss /= n;
  for (var i = n + 1; i < closes.length; i++) {
    final d = closes[i] - closes[i - 1];
    gain = (gain * (n - 1) + math.max(d, 0)) / n;
    loss = (loss * (n - 1) + math.max(-d, 0)) / n;
  }
  return loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
}

/// Ảnh chụp kỹ thuật của một mã ở phiên gần nhất.
class Snapshot {
  final String symbol;
  final Map<String, dynamic> data; // các chỉ số, dùng chung cho giao diện và prompt AI
  final List<String> signals;
  final int techScore;
  final List<double> spark; // giá đóng cửa 60 phiên
  final List<Bar> bars; // dữ liệu ngày đã tải, dùng cho biểu đồ

  Snapshot(this.symbol, this.data, this.signals, this.techScore, this.spark, this.bars);

  double get close => (data['close'] as num).toDouble();
  double? num_(String k) => (data[k] as num?)?.toDouble();

  Map<String, dynamic> toPromptJson() => {...data, 'signals': signals, 'tech_score': techScore};
}

Snapshot analyze(String symbol, List<Bar> bars) {
  final closes = bars.map((b) => b.c).toList();
  final vols = bars.map((b) => b.v).toList();
  final last = closes.last;
  double? back(int n) => closes.length > n ? closes[closes.length - 1 - n] : null;

  final ma20 = _sma(closes, 20), ma50 = _sma(closes, 50), ma200 = _sma(closes, 200);
  final rsi14 = _rsi(closes);
  final ema26 = _ema(closes, 26);
  final macd = [for (final (i, x) in _ema(closes, 12).indexed) x - ema26[i]];
  final signal = _ema(macd, 9);
  final hist = macd.last - signal.last;
  final histPrev = closes.length > 1 ? macd[macd.length - 2] - signal[signal.length - 2] : hist;
  final std20 = ma20 == null
      ? null
      : math.sqrt(_avg(closes.sublist(closes.length - 20).map((c) => (c - ma20) * (c - ma20))));
  final recent = bars.sublist(math.max(0, bars.length - 14));
  final hh = recent.map((b) => b.h).reduce(math.max);
  final ll = recent.map((b) => b.l).reduce(math.min);
  final trs = [
    for (var i = 1; i < bars.length; i++)
      math.max(bars[i].h - bars[i].l,
          math.max((bars[i].h - bars[i - 1].c).abs(), (bars[i].l - bars[i - 1].c).abs())),
  ];
  final atr14 = trs.length >= 14 ? _avg(trs.sublist(trs.length - 14)) : null;
  final avgVol20 = vols.length > 20 ? _sma(vols.sublist(0, vols.length - 1), 20) : null;
  final volRatio = avgVol20 == null || avgVol20 == 0 ? null : _round(vols.last / avgVol20);
  final year = bars.sublist(math.max(0, bars.length - 250));
  final high52 = year.map((b) => b.h).reduce(math.max);
  final low52 = year.map((b) => b.l).reduce(math.min);
  final change1d = _pct(last, back(1));

  final signals = <String>[];
  var score = 0;
  if (ma20 != null && ma50 != null) {
    if (last > ma20 && ma20 > ma50) {
      signals.add('Xu hướng tăng (giá > MA20 > MA50)');
      score += 2;
    } else if (last < ma20 && ma20 < ma50) {
      signals.add('Xu hướng giảm (giá < MA20 < MA50)');
      score -= 2;
    }
  }
  if (ma200 != null) score += last > ma200 ? 1 : -1;
  if (rsi14 != null && rsi14 >= 70) {
    signals.add('RSI quá mua (${rsi14.round()})');
    score -= 1;
  } else if (rsi14 != null && rsi14 <= 30) {
    signals.add('RSI quá bán (${rsi14.round()})');
    score += 1;
  }
  if (hist > 0 && histPrev <= 0) {
    signals.add('MACD cắt lên đường tín hiệu');
    score += 1;
  } else if (hist < 0 && histPrev >= 0) {
    signals.add('MACD cắt xuống đường tín hiệu');
    score -= 1;
  }
  if (volRatio != null && volRatio >= 1.8) {
    final up = (change1d ?? 0) >= 0;
    signals.add('Khối lượng đột biến x$volRatio kèm giá ${up ? 'tăng' : 'giảm'}');
    score += up ? 1 : -1;
  }
  if (last >= high52 * 0.98) signals.add('Sát đỉnh 52 tuần');
  if (last <= low52 * 1.02) signals.add('Sát đáy 52 tuần');

  final date = DateTime.fromMillisecondsSinceEpoch((bars.last.t + 7 * 3600) * 1000, isUtc: true);
  return Snapshot(
    symbol,
    {
      'date': date.toIso8601String().substring(0, 10),
      'close': last,
      'change_1d': change1d,
      'change_1w': _pct(last, back(5)),
      'change_1m': _pct(last, back(20)),
      'change_3m': _pct(last, back(60)),
      'change_1y': _pct(last, back(250)),
      'ma20': _round(ma20),
      'ma50': _round(ma50),
      'ma200': _round(ma200),
      'rsi14': _round(rsi14, 1),
      'macd': _round(macd.last, 3),
      'macd_signal': _round(signal.last, 3),
      'bollinger_upper': _round(ma20 != null && std20 != null ? ma20 + 2 * std20 : null),
      'bollinger_lower': _round(ma20 != null && std20 != null ? ma20 - 2 * std20 : null),
      'stochastic_k': _round(hh == ll ? 50 : (last - ll) / (hh - ll) * 100, 1),
      'atr14_pct': _round(atr14 == null ? null : atr14 / last * 100),
      'volume': vols.last,
      'vol_ratio': volRatio,
      'high_52w': high52,
      'low_52w': low52,
      'from_high_52w': _pct(last, high52),
    },
    signals,
    score,
    closes.sublist(math.max(0, closes.length - 60)),
    bars,
  );
}

/// Lấy và phân tích nhiều mã, giới hạn số yêu cầu chạy song song.
Future<Map<String, Snapshot>> fetchMany(Iterable<String> symbols, {int parallel = 6}) async {
  final out = <String, Snapshot>{};
  final queue = symbols.toList();
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final s = queue.removeLast();
      final bars = await fetchBars(s);
      if (bars.length >= 2) out[s] = analyze(s, bars);
    }
  }

  await Future.wait(List.generate(parallel, (_) => worker()));
  return out;
}
