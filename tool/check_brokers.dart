// Chạy thử nguồn khuyến nghị với mạng thật: dart run tool/check_brokers.dart VCB
import 'package:vn_stock_insight/services/brokers.dart';

Future<void> main(List<String> args) async {
  final symbol = args.isEmpty ? 'VCB' : args.first.toUpperCase();
  final recs = await brokerSummary(symbol, company: {'vietcap_khuyen_nghi': 'BUY', 'vietcap_gia_muc_tieu': 90000, 'vietcap_ngay_khuyen_nghi': '2026-10-01'});
  final c = consensusOf(recs);
  print('$symbol: ${recs.length} công ty, mua ${c.buy}, giữ ${c.hold}, bán ${c.sell}, trung vị ${c.medianTarget}');
  for (final r in recs) {
    print('  ${firmName(r.firm).padRight(18)} ${r.rating.padRight(8)} ${r.target?.toStringAsFixed(0) ?? '-'} ${r.date.toIso8601String().substring(0, 10)}');
  }
}
