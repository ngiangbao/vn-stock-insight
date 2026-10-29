// Khuyến nghị của các công ty chứng khoán cho một cổ phiếu: giá mục tiêu, mức khuyến nghị và ngày báo cáo.
//
// Nguồn: dữ liệu khuyến nghị tổng hợp (Bloomberg, VNDirect) tại api-finfo.vndirect.com.vn, gồm các công ty như HSC, VNDirect,
// Vietcap, VCBS, MBS, ACBS, BSI, FPTS, SSI... có công bố báo cáo cho mã đó, cộng với khuyến nghị Vietcap từ Vietcap IQ.
// Nguồn này không phủ mọi mã và mọi công ty: TCBS không công bố qua API công khai (API của TCBS yêu cầu đăng nhập) nên không có
// trong danh sách; mã nào chưa có báo cáo trong 12 tháng thì danh sách ngắn hoặc trống. Chỉ để tham chiếu, không phải lời khuyên.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market.dart' show userAgent;

class BrokerRec {
  final String firm, rating, rawRating;
  final double? target; // đồng
  final double? reportPrice; // đồng
  final DateTime date;
  final String? analyst;
  const BrokerRec({
    required this.firm,
    required this.rating,
    required this.rawRating,
    required this.target,
    required this.reportPrice,
    required this.date,
    this.analyst,
  });

  Map<String, dynamic> toJson() => {
    'firm': firm,
    'rating': rating,
    'raw': rawRating,
    'target': target,
    'report_price': reportPrice,
    'date': date.toIso8601String().substring(0, 10),
    'analyst': analyst,
  };
  factory BrokerRec.fromJson(Map j) => BrokerRec(
    firm: '${j['firm']}',
    rating: '${j['rating']}',
    rawRating: '${j['raw'] ?? j['rating']}',
    target: (j['target'] as num?)?.toDouble(),
    reportPrice: (j['report_price'] as num?)?.toDouble(),
    date: DateTime.parse('${j['date']}'),
    analyst: j['analyst'] as String?,
  );
}

const _firmNames = {
  'VND': 'VNDirect',
  'VCS': 'Vietcap',
  'FTS': 'FPTS',
  'VDS': 'Rồng Việt (VDSC)',
  'MASC': 'Mirae Asset',
  'BSI': 'BSC (BIDV)',
  'SBB': 'SBBS',
};

String firmName(String code) => _firmNames[code] ?? code;

/// Chuẩn hóa mức khuyến nghị về MUA, NẮM GIỮ, BÁN; mức lạ giữ nguyên chữ gốc.
String normalizeRating(String raw) {
  final r = raw.trim().toUpperCase();
  if (const {'BUY', 'STRONG BUY', 'OUTPERFORM', 'ADD', 'OVERWEIGHT', 'ACCUMULATE', 'TRADING BUY', 'MUA'}.contains(r)) return 'MUA';
  if (const {'HOLD', 'NEUTRAL', 'MARKET PERFORM', 'EQUAL-WEIGHT', 'EQUALWEIGHT', 'MARKET-PERFORM', 'NẮM GIỮ', 'TRUNG LẬP'}.contains(r)) {
    return 'NẮM GIỮ';
  }
  if (const {'SELL', 'STRONG SELL', 'UNDERPERFORM', 'REDUCE', 'UNDERWEIGHT', 'BÁN'}.contains(r)) return 'BÁN';
  return raw.trim().isEmpty ? '–' : r;
}

/// Đọc phản hồi của api-finfo (`{"data":[…]}`); giá trong nguồn tính theo nghìn đồng.
List<BrokerRec> parseRecommendations(String body) {
  final out = <BrokerRec>[];
  try {
    for (final r in ((jsonDecode(body) as Map)['data'] as List).cast<Map>()) {
      final date = DateTime.tryParse('${r['reportDate']}');
      if (date == null || r['firm'] == null) continue;
      final tp = (r['targetPrice'] as num?)?.toDouble(), rp = (r['reportPrice'] as num?)?.toDouble();
      out.add(
        BrokerRec(
          firm: '${r['firm']}',
          rating: normalizeRating('${r['type'] ?? ''}'),
          rawRating: '${r['type'] ?? ''}',
          target: tp == null || tp <= 0 ? null : tp * 1000,
          reportPrice: rp == null || rp <= 0 ? null : rp * 1000,
          date: date,
          analyst: r['analyst'] as String?,
        ),
      );
    }
  } catch (_) {}
  return out;
}

/// Báo cáo mới nhất của từng công ty trong vòng [maxAgeDays] ngày, mới nhất trước.
List<BrokerRec> latestPerFirm(List<BrokerRec> all, {DateTime? now, int maxAgeDays = 365}) {
  final n = now ?? DateTime.now();
  final best = <String, BrokerRec>{};
  for (final r in all) {
    if (n.difference(r.date).inDays > maxAgeDays) continue;
    final key = firmName(r.firm).toLowerCase();
    final cur = best[key];
    if (cur == null || r.date.isAfter(cur.date)) best[key] = r;
  }
  return best.values.toList()..sort((a, b) => b.date.compareTo(a.date));
}

/// Gộp khuyến nghị Vietcap IQ (nếu có) vào danh sách: giữ bản mới hơn nếu Vietcap đã có trong nguồn tổng hợp.
List<BrokerRec> withVietcap(List<BrokerRec> recs, {String? rating, num? target, String? date}) {
  if (rating == null && target == null) return recs;
  final d = DateTime.tryParse(date ?? '') ?? DateTime.now();
  final iq = BrokerRec(
    firm: 'VCS',
    rating: normalizeRating(rating ?? ''),
    rawRating: rating ?? '',
    target: target?.toDouble(),
    reportPrice: null,
    date: d,
  );
  final others = recs.where((r) => firmName(r.firm) != 'Vietcap').toList();
  final existing = recs.where((r) => firmName(r.firm) == 'Vietcap').firstOrNull;
  if (existing != null && existing.date.isAfter(iq.date)) return recs;
  return [...others, iq]..sort((a, b) => b.date.compareTo(a.date));
}

class BrokerConsensus {
  final int total, buy, hold, sell;
  final double? medianTarget; // đồng
  const BrokerConsensus(this.total, this.buy, this.hold, this.sell, this.medianTarget);
}

BrokerConsensus consensusOf(List<BrokerRec> recs) {
  final targets = [
    for (final r in recs)
      if (r.target != null) r.target!,
  ]..sort();
  double? median;
  if (targets.isNotEmpty) {
    median = targets.length.isOdd ? targets[targets.length ~/ 2] : (targets[targets.length ~/ 2 - 1] + targets[targets.length ~/ 2]) / 2;
  }
  return BrokerConsensus(
    recs.length,
    recs.where((r) => r.rating == 'MUA').length,
    recs.where((r) => r.rating == 'NẮM GIỮ').length,
    recs.where((r) => r.rating == 'BÁN').length,
    median,
  );
}

const _headers = {
  ...userAgent,
  'Origin': 'https://dstock.vndirect.com.vn',
  'Referer': 'https://dstock.vndirect.com.vn/',
  'Accept': 'application/json',
};

/// Tải khuyến nghị của một mã; trả về danh sách rỗng nếu nguồn lỗi (không làm hỏng báo cáo).
Future<List<BrokerRec>> fetchBrokerRecs(String symbol, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(
          Uri.parse('https://api-finfo.vndirect.com.vn/v4/recommendations?q=code:$symbol&sort=reportDate:desc&size=100'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return const [];
    return parseRecommendations(utf8.decode(r.bodyBytes));
  } catch (_) {
    return const [];
  } finally {
    if (client == null) c.close();
  }
}

/// Khuyến nghị mới nhất của từng công ty cho [symbol] (nguồn tổng hợp) cộng khuyến nghị Vietcap IQ từ thông tin công ty [company].
Future<List<BrokerRec>> brokerSummary(String symbol, {Map? company, http.Client? client}) async {
  final feed = latestPerFirm(await fetchBrokerRecs(symbol, client: client));
  return withVietcap(
    feed,
    rating: company?['vietcap_khuyen_nghi'] as String?,
    target: company?['vietcap_gia_muc_tieu'] as num?,
    date: company?['vietcap_ngay_khuyen_nghi'] as String?,
  );
}
