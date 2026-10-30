import 'dart:math' as math;

import '../dashboard.dart' show indexMetas;
import 'board.dart';
import 'market.dart';

/// Named examples, not an exhaustive or periodically maintained fund universe.
const listedFundExamples = ['E1VFVN30', 'FUEVFVND', 'FUEVN100'];

class InstrumentQuote {
  final String symbol;
  final List<Bar> bars;
  final bool derivative;
  const InstrumentQuote(this.symbol, this.bars, {this.derivative = false});
  double get price => bars.last.c;
  double? get change => bars.length < 2 || bars[bars.length - 2].c == 0
      ? null
      : (price / bars[bars.length - 2].c - 1) * 100;
  String get date => vnDate(bars.last.t);
}

Future<List<InstrumentQuote>> loadFundQuotes() async {
  final symbols = <String>{...listedFundExamples};
  // Discover listed ETFs from the same board source as equities. Historical
  // quotes remain usable when discovery is unavailable; no fabricated NAV.
  try {
    final boards = await Future.wait([
      for (final group in ['HOSE', 'HNX'])
        fetchBoard(group, securityTypes: const {'ETF', 'FUND'}),
    ]);
    symbols.addAll(boards.expand((b) => b).map((r) => r.symbol));
  } catch (_) {
    /* Historical source below can still be available. */
  }
  return loadInstrumentQuotes(symbols);
}

Future<List<InstrumentQuote>> loadInstrumentQuotes(
  Iterable<String> symbols, {
  bool derivative = false,
}) async {
  final results = await Future.wait([
    for (final symbol in symbols)
      fetchBars(symbol, kind: derivative ? 'derivative' : 'stock').then(
        (bars) => bars.isEmpty
            ? null
            : InstrumentQuote(symbol, bars, derivative: derivative),
      ),
  ]);
  return results.whereType<InstrumentQuote>().toList();
}

Future<List<InstrumentQuote>> loadDerivativeQuotes() => loadInstrumentQuotes(
  indexMetas.where((m) => m.kind == 'derivative').map((m) => m.symbol),
  derivative: true,
);

/// Basis is meaningful only when both series refer to the same session.
double? sameSessionBasis(InstrumentQuote future, List<Bar> spot) =>
    spot.isEmpty || future.date != vnDate(spot.last.t)
    ? null
    : future.price - spot.last.c;

/// Annual coupon, redemption at par; price per 100 face, on a coupon date.
/// This is a scenario tool, not a dirty price including accrued interest.
double bondPrice({
  required double coupon,
  required double yieldPercent,
  required int years,
}) {
  if (!coupon.isFinite ||
      !yieldPercent.isFinite ||
      coupon < 0 ||
      yieldPercent < 0 ||
      years < 1 ||
      years > 100) {
    throw ArgumentError(
      'Coupon/lợi suất phải không âm; kỳ hạn từ 1 đến 100 năm.',
    );
  }
  final rate = yieldPercent / 100;
  return [for (var t = 1; t <= years; t++) coupon / math.pow(1 + rate, t)]
          .fold<double>(0, (a, b) => a + b) +
      100 / math.pow(1 + rate, years);
}
