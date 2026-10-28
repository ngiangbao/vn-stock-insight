// Chuỗi chỉ báo kỹ thuật theo từng phiên, dùng cho biểu đồ. Phần tử null khi chưa đủ dữ liệu.

import 'dart:math' as math;

import 'market.dart' show Bar;

List<double?> smaSeries(List<double> xs, int n) {
  final out = List<double?>.filled(xs.length, null);
  var sum = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sum += xs[i];
    if (i >= n) sum -= xs[i - n];
    if (i >= n - 1) out[i] = sum / n;
  }
  return out;
}

List<double?> emaSeries(List<double> xs, int n) {
  final out = List<double?>.filled(xs.length, null);
  if (xs.length < n) return out;
  final k = 2 / (n + 1);
  var ema = xs.take(n).reduce((a, b) => a + b) / n;
  out[n - 1] = ema;
  for (var i = n; i < xs.length; i++) {
    ema = xs[i] * k + ema * (1 - k);
    out[i] = ema;
  }
  return out;
}

/// Dải Bollinger (20, 2): (giữa, trên, dưới).
(List<double?>, List<double?>, List<double?>) bollinger(List<double> xs, {int n = 20, double k = 2}) {
  final mid = smaSeries(xs, n);
  final up = List<double?>.filled(xs.length, null), lo = List<double?>.filled(xs.length, null);
  for (var i = n - 1; i < xs.length; i++) {
    final m = mid[i]!;
    var v = 0.0;
    for (var j = i - n + 1; j <= i; j++) {
      v += (xs[j] - m) * (xs[j] - m);
    }
    final sd = math.sqrt(v / n);
    up[i] = m + k * sd;
    lo[i] = m - k * sd;
  }
  return (mid, up, lo);
}

List<double?> rsiSeries(List<double> xs, {int n = 14}) {
  final out = List<double?>.filled(xs.length, null);
  if (xs.length <= n) return out;
  var gain = 0.0, loss = 0.0;
  for (var i = 1; i <= n; i++) {
    final d = xs[i] - xs[i - 1];
    gain += math.max(d, 0);
    loss += math.max(-d, 0);
  }
  gain /= n;
  loss /= n;
  out[n] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
  for (var i = n + 1; i < xs.length; i++) {
    final d = xs[i] - xs[i - 1];
    gain = (gain * (n - 1) + math.max(d, 0)) / n;
    loss = (loss * (n - 1) + math.max(-d, 0)) / n;
    out[i] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
  }
  return out;
}

/// MACD (12, 26, 9): (đường MACD, đường tín hiệu, histogram).
(List<double?>, List<double?>, List<double?>) macdSeries(List<double> xs) {
  final fast = emaSeries(xs, 12), slow = emaSeries(xs, 26);
  final macd = [for (var i = 0; i < xs.length; i++) fast[i] != null && slow[i] != null ? fast[i]! - slow[i]! : null];
  final start = macd.indexWhere((x) => x != null);
  final signal = List<double?>.filled(xs.length, null);
  if (start >= 0) {
    final sig = emaSeries([for (final x in macd.skip(start)) x!], 9);
    for (var i = 0; i < sig.length; i++) {
      signal[start + i] = sig[i];
    }
  }
  final hist = [for (var i = 0; i < xs.length; i++) macd[i] != null && signal[i] != null ? macd[i]! - signal[i]! : null];
  return (macd, signal, hist);
}

/// Stochastic (14, 3): (%K, %D).
(List<double?>, List<double?>) stochasticSeries(List<Bar> bars, {int n = 14, int d = 3}) {
  final k = List<double?>.filled(bars.length, null);
  for (var i = n - 1; i < bars.length; i++) {
    var hh = -double.infinity, ll = double.infinity;
    for (var j = i - n + 1; j <= i; j++) {
      hh = math.max(hh, bars[j].h);
      ll = math.min(ll, bars[j].l);
    }
    k[i] = hh == ll ? 50 : (bars[i].c - ll) / (hh - ll) * 100;
  }
  final dLine = List<double?>.filled(bars.length, null);
  for (var i = n - 1 + d - 1; i < bars.length; i++) {
    dLine[i] = (k[i]! + k[i - 1]! + k[i - 2]!) / 3;
  }
  return (k, dLine);
}

/// Nến Heikin-Ashi.
List<Bar> heikinAshi(List<Bar> bars) {
  final out = <Bar>[];
  for (final (i, b) in bars.indexed) {
    final c = (b.o + b.h + b.l + b.c) / 4;
    final o = i == 0 ? (b.o + b.c) / 2 : (out[i - 1].o + out[i - 1].c) / 2;
    out.add(Bar(b.t, o, math.max(b.h, math.max(o, c)), math.min(b.l, math.min(o, c)), c, b.v));
  }
  return out;
}
