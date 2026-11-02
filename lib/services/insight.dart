// Nhận định kỹ thuật tính trên máy từ nến giá: điểm sức khỏe (4 nhóm có trọng số), dấu hiệu tạo đáy, vùng giá hỗ trợ/kháng cự,
// mức Fibonacci, kịch bản theo ngưỡng và nhận định xu hướng theo khung ngày/tuần. Giá tính theo nghìn đồng.
// Đây là quy tắc kỹ thuật cố định, không phải dự báo hay lời khuyên đầu tư.

import 'dart:math' as math;

import 'indicators.dart';
import 'market.dart' show Bar, vnDate;

/// Gộp nến ngày thành nến tuần (thứ Hai đến thứ Sáu, theo ngày giao dịch giờ Việt Nam).
List<Bar> weeklyBars(List<Bar> daily) {
  final out = <Bar>[];
  String? week;
  for (final b in daily) {
    final d = DateTime.parse(vnDate(b.t));
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final key = '${monday.year}-${monday.month}-${monday.day}';
    if (key != week) {
      week = key;
      out.add(b);
    } else {
      final w = out.last;
      out[out.length - 1] = Bar(w.t, w.o, math.max(w.h, b.h), math.min(w.l, b.l), b.c, w.v + b.v);
    }
  }
  return out;
}

/// Gộp nến phút/giờ thành nến [hours] giờ trong cùng một ngày giao dịch (phiên sáng và chiều tính chung theo khung giờ cố định).
List<Bar> hourlyBars(List<Bar> src, int hours) {
  final out = <Bar>[];
  String? key;
  for (final b in src) {
    final vn = DateTime.fromMillisecondsSinceEpoch(b.t * 1000, isUtc: true).add(const Duration(hours: 7));
    final slot = hours >= 4 ? (vn.hour < 12 ? 0 : 1) : vn.hour ~/ hours;
    final k = '${vnDate(b.t)}-$slot';
    if (k != key) {
      key = k;
      out.add(b);
    } else {
      final w = out.last;
      out[out.length - 1] = Bar(w.t, w.o, math.max(w.h, b.h), math.min(w.l, b.l), b.c, w.v + b.v);
    }
  }
  return out;
}

double? _last(List<double?> s, [int back = 0]) => s.length > back ? s[s.length - 1 - back] : null;

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Một nhóm trong điểm sức khỏe: tên, trọng số (%) và điểm 0–100.
class HealthPart {
  final String name;
  final int weight, score;
  const HealthPart(this.name, this.weight, this.score);
}

class HealthScore {
  final int total;
  final String label; // Mạnh, Trung tính, Yếu
  final List<HealthPart> parts;

  /// Điểm cách đây [backSessions] phiên, null nếu chưa đủ dữ liệu.
  final int? previous;
  final int backSessions;
  const HealthScore(this.total, this.label, this.parts, this.previous, this.backSessions);
  int? get delta => previous == null ? null : total - previous!;
}

String healthLabel(int score) => score >= 67 ? 'Mạnh' : (score >= 40 ? 'Trung tính' : 'Yếu');

/// Điểm sức khỏe 0–100: xu hướng 35%, động lượng 20%, dòng tiền 25%, sức mạnh tương đối so với [index] 20%. Null nếu dưới 60 phiên.
HealthScore? healthScore(List<Bar> bars, List<Bar> index, {int backSessions = 30}) {
  final now = _score(bars, index);
  if (now == null) return null;
  final prevBars = bars.length > backSessions ? bars.sublist(0, bars.length - backSessions) : null;
  final prev = prevBars == null ? null : _score(prevBars, index.where((b) => prevBars.isNotEmpty && b.t <= prevBars.last.t).toList());
  return HealthScore(now.$1, healthLabel(now.$1), now.$2, prev?.$1, backSessions);
}

/// Điểm tổng 0–100 tại phiên cuối của [bars] (dùng cho kiểm định lịch sử), null nếu dưới 60 phiên.
int? healthTotal(List<Bar> bars, List<Bar> index) => _score(bars, index)?.$1;

(int, List<HealthPart>)? _score(List<Bar> bars, List<Bar> index) {
  if (bars.length < 60) return null;
  final closes = [for (final b in bars) b.c];
  final c = closes.last;
  final ma20 = _last(smaSeries(closes, 20)), ma50 = _last(smaSeries(closes, 50));
  final ma200 = closes.length >= 200 ? _last(smaSeries(closes, 200)) : null;
  final ma50Prev = _last(smaSeries(closes, 50), 10);

  // Xu hướng: vị trí giá so với các đường trung bình và độ dốc MA50
  var trend = 0.0;
  if (ma20 != null && c > ma20) trend += 15;
  if (ma50 != null && c > ma50) trend += 20;
  if (ma200 != null && c > ma200) trend += 25;
  if (ma20 != null && ma50 != null && ma20 > ma50) trend += 15;
  if (ma50 != null && ma200 != null && ma50 > ma200) trend += 15;
  if (ma50 != null && ma50Prev != null && ma50 > ma50Prev) trend += 10;
  if (ma200 == null) trend = trend / 75 * 100; // chưa đủ 200 phiên: quy về thang 100 theo các tiêu chí còn lại

  // Động lượng: RSI, MACD so với đường tín hiệu, histogram
  final rsi = _last(rsiSeries(closes)) ?? 50;
  final (macd, signal, hist) = macdSeries(closes);
  var momentum = _clamp((rsi - 30) / 40 * 60, 0, 60);
  if ((_last(hist) ?? 0) > 0) momentum += 20;
  if ((_last(macd) ?? 0) > (_last(signal) ?? 0)) momentum += 20;

  // Dòng tiền: tỷ trọng khối lượng của phiên tăng trong 20 phiên và MFI
  final recent = bars.sublist(bars.length - 20);
  final totalVol = recent.fold<double>(0, (a, b) => a + b.v);
  final upVol = recent.fold<double>(0, (a, b) => a + (b.c >= b.o ? b.v : 0));
  final mfi = _last(mfiSeries(bars)) ?? 50;
  final money = totalVol == 0 ? 50.0 : 0.6 * (upVol / totalVol * 100) + 0.4 * _clamp(mfi, 0, 100);

  // Sức mạnh tương đối: chênh lệch lợi suất 3 tháng (66 phiên) so với chỉ số, -20 điểm % đến +20 điểm %
  double ret(List<Bar> b) => b.length > 66 ? (b.last.c / b[b.length - 67].c - 1) * 100 : 0;
  final rs = index.length > 66 ? _clamp((ret(bars) - ret(index) + 20) / 40 * 100, 0, 100) : 50.0;

  final parts = [
    HealthPart('Xu hướng', 35, trend.round()),
    HealthPart('Động lượng', 20, momentum.round()),
    HealthPart('Dòng tiền', 25, money.round()),
    HealthPart('Sức mạnh tương đối', 20, rs.round()),
  ];
  final total = parts.fold<double>(0, (a, p) => a + p.score * p.weight / 100).round();
  return (total, parts);
}

/// Một dấu hiệu tạo đáy: [met] true = có, false = chưa, null = chưa đủ dữ liệu để kết luận.
class BottomSignal {
  final String label;
  final bool? met;

  /// Ghi chú ngắn dưới nhãn (ví dụ số liệu độ rộng, hoặc "đang tính").
  final String? note;
  const BottomSignal(this.label, this.met, {this.note});
}

/// 6 dấu hiệu tạo đáy theo quy tắc kỹ thuật cố định. [index] là VN-Index (cho dấu hiệu xác nhận đáy toàn thị trường).
List<BottomSignal> bottomSignals(List<Bar> bars, List<Bar> index, {BottomSignal? breadthSignal}) {
  if (bars.length < 60) return [for (final l in _bottomLabels) BottomSignal(l, null)];
  final closes = [for (final b in bars) b.c];
  final n = bars.length;
  final rsi = rsiSeries(closes);
  final ma50 = smaSeries(closes, 50);
  final avgVol = bars.sublist(n - 21, n - 1).fold<double>(0, (a, b) => a + b.v) / 20;

  // 1. Phân kỳ dương: giá lập đáy thấp hơn trong 20 phiên gần nhất so với 20 phiên trước đó nhưng RSI đáy cao hơn
  int argMin(int from, int to) {
    var k = from;
    for (var i = from; i < to; i++) {
      if (bars[i].l < bars[k].l) k = i;
    }
    return k;
  }

  final a = argMin(n - 20, n), b = argMin(n - 40, n - 20);
  final r1 = rsi[a], r0 = rsi[b];
  final divergence = r1 != null && r0 != null ? (bars[a].l < bars[b].l && r1 > r0 + 1) : null;

  // 2. Phiên bán tháo: trong 10 phiên gần nhất có phiên khối lượng ≥ 2 lần trung bình và đóng cửa ở nửa trên biên độ
  final capitulation = bars
      .sublist(n - 10)
      .any((x) => avgVol > 0 && x.v >= 2 * avgVol && x.h > x.l && (x.c - x.l) / (x.h - x.l) >= 0.5 && x.c < closes[n - 20]);

  // 3. Ngày xác nhận đáy của thị trường: VN-Index tăng ≥ 1% với khối lượng trên trung bình trong 5 phiên gần nhất
  bool? followThrough;
  if (index.length > 30) {
    final iv = index.sublist(index.length - 21, index.length - 1).fold<double>(0, (s, x) => s + x.v) / 20;
    followThrough = false;
    for (var i = index.length - 5; i < index.length; i++) {
      if (index[i].c / index[i - 1].c - 1 >= 0.01 && (iv == 0 || index[i].v >= iv)) followThrough = true;
    }
  }

  // 4. Kiểm định lại đáy: đáy 30 phiên đã bật lên ≥ 5% rồi quay về trong 3% của đáy mà không thủng
  final low30 = argMin(n - 30, n);
  var retest = false;
  if (low30 < n - 3) {
    final bounce = bars.sublist(low30 + 1).map((x) => x.h).reduce(math.max) / bars[low30].l - 1;
    final nearLow = bars.last.l <= bars[low30].l * 1.03 && bars.last.l >= bars[low30].l * 0.999;
    retest = bounce >= 0.05 && nearLow;
  }

  // 5. Độ rộng thị trường hồi từ dưới 20% mã trên MA50: tính ở services/backtest.dart từ giá cả sàn HOSE, truyền vào qua [breadthSignal]

  // 6. Vượt và giữ MA50 trong 3 phiên liên tiếp
  final m50 = ma50[n - 1];
  final reclaim = m50 == null ? null : [for (var i = n - 3; i < n; i++) i].every((i) => closes[i] > (ma50[i] ?? double.infinity));

  return [
    BottomSignal(_bottomLabels[0], divergence),
    BottomSignal(_bottomLabels[1], capitulation),
    BottomSignal(_bottomLabels[2], followThrough),
    BottomSignal(_bottomLabels[3], retest),
    breadthSignal ?? BottomSignal(_bottomLabels[4], null),
    BottomSignal(_bottomLabels[5], reclaim),
  ];
}

/// Nhãn dấu hiệu độ rộng thị trường (dấu hiệu thứ 5).
const breadthLabel = 'Độ rộng hồi từ dưới 20%';

const _bottomLabels = [
  'Phân kỳ dương RSI/MACD',
  'Phiên bán tháo',
  'Ngày xác nhận đáy (VN-Index)',
  'Kiểm định lại đáy',
  'Độ rộng hồi từ dưới 20%',
  'Vượt và giữ MA50',
];

/// Một vùng giá (hỗ trợ hoặc kháng cự) gộp từ các đỉnh/đáy cục bộ gần nhau.
class PriceZone {
  final double low, high;
  final int touches;
  const PriceZone(this.low, this.high, this.touches);
  double get mid => (low + high) / 2;
}

/// Mức Fibonacci của nhịp gần nhất: [ratio] (0,382; 0,5; 0,618), [price] và vai trò hỗ trợ hay kháng cự so với giá hiện tại.
class FibLevel {
  final double ratio, price;
  final bool support;
  const FibLevel(this.ratio, this.price, this.support);
  String get label =>
      'Fibonacci ${(ratio * 100).toStringAsFixed(ratio == 0.5 ? 0 : 1).replaceAll('.', ',')}% (${support ? 'hỗ trợ' : 'kháng cự'})';
}

class PriceZones {
  final double close;
  final List<PriceZone> resistances; // gần giá nhất trước
  final List<PriceZone> supports;
  final double? ma50, ma200;
  final double? recentLow; // đáy nhịp gần (30 phiên)
  final List<FibLevel> fib;
  const PriceZones(this.close, this.resistances, this.supports, this.ma50, this.ma200, this.recentLow, this.fib);

  PriceZone? get nearestResistance => resistances.firstOrNull;
  PriceZone? get nearestSupport => supports.firstOrNull;

  /// Đường trung bình dài còn nằm trên giá (kháng cự động) gần nhất.
  ({String name, double price})? get dynamicResistance {
    final c = <({String name, double price})>[
      if (ma50 != null && ma50! > close) (name: 'MA50', price: ma50!),
      if (ma200 != null && ma200! > close) (name: 'MA200', price: ma200!),
    ]..sort((a, b) => a.price.compareTo(b.price));
    return c.firstOrNull;
  }
}

/// Vùng giá từ đỉnh/đáy cục bộ (cửa sổ ±5 phiên) trong [lookback] phiên, gộp các mức cách nhau ≤ [tolerance] (mặc định 1,5%).
PriceZones? priceZones(List<Bar> bars, {int lookback = 250, double tolerance = 0.015}) {
  if (bars.length < 40) return null;
  final shown = bars.length > lookback ? bars.sublist(bars.length - lookback) : bars;
  final close = bars.last.c;
  final closes = [for (final b in bars) b.c];
  const w = 5;
  final highs = <double>[], lows = <double>[];
  for (var i = w; i < shown.length - w; i++) {
    final win = shown.sublist(i - w, i + w + 1);
    if (shown[i].h >= win.map((b) => b.h).reduce(math.max)) highs.add(shown[i].h);
    if (shown[i].l <= win.map((b) => b.l).reduce(math.min)) lows.add(shown[i].l);
  }
  List<PriceZone> cluster(List<double> xs) {
    final sorted = [...xs]..sort();
    final out = <List<double>>[];
    for (final x in sorted) {
      if (out.isNotEmpty && x <= out.last.first * (1 + tolerance)) {
        out.last.add(x);
      } else {
        out.add([x]);
      }
    }
    return [for (final g in out) PriceZone(g.first, g.last, g.length)];
  }

  final all = cluster([...highs, ...lows]);
  final res = all.where((z) => z.low > close * 1.003).toList()..sort((a, b) => a.low.compareTo(b.low));
  final sup = all.where((z) => z.high < close * 0.997).toList()..sort((a, b) => b.high.compareTo(a.high));

  final n = bars.length;
  final recentLow = bars.sublist(n >= 30 ? n - 30 : 0).map((b) => b.l).reduce(math.min);

  // Fibonacci trên nhịp lớn gần nhất trong 120 phiên: nhịp giảm (đỉnh trước đáy) thì các mức nằm trên đáy là kháng cự
  final span = bars.sublist(n > 120 ? n - 120 : 0);
  var hi = 0, lo = 0;
  for (var i = 0; i < span.length; i++) {
    if (span[i].h > span[hi].h) hi = i;
    if (span[i].l < span[lo].l) lo = i;
  }
  final H = span[hi].h, L = span[lo].l;
  final fib = <FibLevel>[];
  if (H > L * 1.08) {
    for (final r in const [0.382, 0.5, 0.618]) {
      final price = hi < lo ? L + (H - L) * r : H - (H - L) * r; // giảm: hồi từ đáy lên; tăng: điều chỉnh từ đỉnh xuống
      fib.add(FibLevel(r, price, price < close));
    }
  }
  return PriceZones(close, res, sup, smaSeries(closes, 50).last, closes.length >= 200 ? smaSeries(closes, 200).last : null, recentLow, fib);
}

/// Kịch bản theo ngưỡng giá và khối lượng (tính từ vùng giá); không phải dự báo.
class Scenarios {
  final String positive, negative;
  final double? positiveLevel, negativeLevel;
  const Scenarios(this.positive, this.negative, this.positiveLevel, this.negativeLevel);
}

String vnNum(double v, [int d = 0]) {
  var s = v.toStringAsFixed(d);
  final parts = s.split('.');
  final int = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return parts.length > 1 ? '$int,${parts[1]}' : int;
}

Scenarios scenarios(List<Bar> bars, PriceZones z) {
  final n = bars.length;
  final avg = n > 21 ? bars.sublist(n - 21, n - 1).fold<double>(0, (a, b) => a + b.v) / 20 : bars.last.v;
  final r =
      z.nearestResistance ?? (z.dynamicResistance == null ? null : PriceZone(z.dynamicResistance!.price, z.dynamicResistance!.price, 1));
  final posLevel = r == null ? null : r.high * 1.02;
  final s = z.nearestSupport;
  final negLevel = s == null ? null : s.low * 0.98;
  return Scenarios(
    posLevel == null
        ? 'Giá đang ở vùng cao nhất của phạm vi đã xét, chưa có kháng cự gần để đặt mốc.'
        : 'Đóng cửa từ ${vnNum(posLevel * 1000)} (vượt kháng cự gần 2%), khối lượng từ ${vnNum(avg * 1.2, 0)} cp.',
    negLevel == null
        ? 'Chưa có hỗ trợ gần để đặt mốc.'
        : 'Đóng cửa dưới ${vnNum(negLevel * 1000)} (thủng hỗ trợ gần 2%) làm yếu kịch bản hồi phục.',
    posLevel,
    negLevel,
  );
}

/// Nhận định xu hướng của một khung nến: hướng và số phiếu đồng thuận trên tổng 3 tiêu chí (giá so MA20, MA20 so MA50, độ dốc MA20).
class TrendFrame {
  final String direction; // Tăng, Giảm, Đi ngang
  final int votes;
  const TrendFrame(this.direction, this.votes);
  String get text => '$direction · $votes/3 phiếu';
}

TrendFrame? trendFrame(List<Bar> bars) {
  if (bars.length < 55) return null;
  final closes = [for (final b in bars) b.c];
  final ma20 = smaSeries(closes, 20), ma50 = smaSeries(closes, 50);
  final c = closes.last, m20 = ma20.last!, m50 = ma50.last!;
  final slope = m20 - (ma20[ma20.length - 6] ?? m20);
  final up = [c > m20, m20 > m50, slope > 0].where((x) => x).length;
  final down = 3 - up;
  if (up == 3) return const TrendFrame('Tăng', 3);
  if (down == 3) return const TrendFrame('Giảm', 3);
  return up > down ? TrendFrame('Tăng', up) : (down > up ? TrendFrame('Giảm', down) : const TrendFrame('Đi ngang', 1));
}

/// Tóm tắt xu hướng: tiêu đề một dòng, đoạn mô tả và các thẻ (hướng, mức sức khỏe).
class TrendSummary {
  final String headline, detail, direction;
  final String healthTag;
  final TrendFrame? week, day;
  const TrendSummary(this.headline, this.detail, this.direction, this.healthTag, this.week, this.day);
}

TrendSummary? trendSummary(String symbol, List<Bar> daily, HealthScore? health, PriceZones? zones, Scenarios? sc) {
  final day = trendFrame(daily);
  if (day == null) return null;
  final week = trendFrame(weeklyBars(daily));
  final closes = [for (final b in daily) b.c];
  final ma200 = closes.length >= 200 ? smaSeries(closes, 200).last : null;
  final c = closes.last;
  final dir = day.direction == 'Giảm' ? 'Đang giảm' : (day.direction == 'Tăng' ? 'Đang tăng' : 'Đi ngang');
  final money = health?.parts.firstWhere((p) => p.name == 'Dòng tiền').score;
  final bits = <String>[
    dir,
    if (ma200 != null) (c < ma200 ? 'dưới MA200' : 'trên MA200'),
    if (money != null) (money < 40 ? 'dòng tiền yếu' : (money >= 60 ? 'dòng tiền tốt' : 'dòng tiền trung tính')),
  ];
  final head = bits.first + (bits.length > 1 ? ' ${bits.sublist(1).join(', ')}' : '');
  final detail = [
    if (week != null) 'Khung tuần ${week.direction.toLowerCase()}',
    'khung ngày ${day.direction.toLowerCase()}',
    if (ma200 != null) 'giá ${c < ma200 ? 'dưới' : 'trên'} MA200 (${vnNum(ma200 * 1000)})',
  ].join(', ');
  final level = sc?.positiveLevel;
  final tail = level == null ? '' : ' Kịch bản tích cực mở ra khi đóng cửa từ ${vnNum(level * 1000)}.';
  return TrendSummary(
    '$symbol $head'.replaceFirst('  ', ' '),
    '${detail[0].toUpperCase()}${detail.substring(1)}.$tail',
    day.direction,
    health?.label ?? '–',
    week,
    day,
  );
}
