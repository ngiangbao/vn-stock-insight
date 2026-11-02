// Lệnh khớp từng giao dịch của cổ phiếu từ Vietcap (kèm phân loại mua chủ động, bán chủ động, ATO/ATC) và tổng hợp dòng tiền.
//
// Nguồn: POST trading.vietcap.com.vn/api/market-watch/LEData/getAll {symbol, limit, truncTime}. Mỗi lần gọi chỉ trả tối đa 100 lệnh gần nhất
// trước mốc truncTime, nên cả phiên được tải bằng nhiều lượt chạy song song theo từng khoảng thời gian (xem [loadSessionTicks]).
// Đây là API nội bộ của web Vietcap, không có tài liệu chính thức; khi lỗi, giao diện báo rõ và không làm hỏng trang.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market.dart' show vnDate;

class Tick {
  final int id, t; // t: giây epoch
  final String side; // 'b' mua chủ động, 's' bán chủ động, 'u' không phân loại (ATO/ATC...)
  final double vol, price; // price: đồng
  final String size; // sheep (nhỏ), wolf, shark (lớn) theo phân loại của nguồn
  const Tick(this.id, this.t, this.side, this.vol, this.price, this.size);
  double get value => vol * price; // đồng
}

List<Tick> parseTicks(String body) {
  final out = <Tick>[];
  try {
    for (final r in (jsonDecode(body) as List).cast<Map>()) {
      final t = int.tryParse('${r['truncTime']}');
      final vol = double.tryParse('${r['matchVol']}'), price = double.tryParse('${r['matchPrice']}');
      final id = (r['id'] as num?)?.toInt();
      if (t == null || vol == null || price == null || id == null) continue;
      final m = '${r['matchType']}';
      out.add(Tick(id, t, m == 'b' ? 'b' : (m == 's' ? 's' : 'u'), vol, price, '${r['type'] ?? ''}'));
    }
  } catch (_) {}
  return out;
}

/// Khối lượng theo một khoảng thời gian (bucket): mua chủ động, bán chủ động và phần không phân loại.
class FlowBucket {
  final int start; // giây epoch
  double buy = 0, sell = 0, other = 0;
  FlowBucket(this.start);
  double get total => buy + sell + other;
}

/// Gom lệnh khớp theo khoảng [minutes] phút (theo giờ Việt Nam), sắp theo thời gian tăng dần.
List<FlowBucket> bucketize(List<Tick> ticks, int minutes) {
  final size = minutes * 60;
  final map = <int, FlowBucket>{};
  for (final k in ticks) {
    final start = k.t - (k.t + 7 * 3600) % size; // căn theo giờ Việt Nam
    final b = map.putIfAbsent(start, () => FlowBucket(start));
    switch (k.side) {
      case 'b':
        b.buy += k.vol;
      case 's':
        b.sell += k.vol;
      default:
        b.other += k.vol;
    }
  }
  return map.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

class FlowSummary {
  final int ticks;
  final double buyVol, sellVol, otherVol, buyValue, sellValue; // giá trị tính bằng đồng
  final double bigBuyValue, bigSellValue;
  final int bigBuyCount, bigSellCount;
  final double bigThreshold;
  const FlowSummary({
    required this.ticks,
    required this.buyVol,
    required this.sellVol,
    required this.otherVol,
    required this.buyValue,
    required this.sellValue,
    required this.bigBuyValue,
    required this.bigSellValue,
    required this.bigBuyCount,
    required this.bigSellCount,
    required this.bigThreshold,
  });
  double get totalVol => buyVol + sellVol + otherVol;
  double get netValue => buyValue - sellValue;
  double get bigNet => bigBuyValue - bigSellValue;
}

/// Tổng hợp mua/bán chủ động và "tiền lớn" (lệnh khớp có giá trị từ [bigValue] đồng, mặc định 1 tỷ).
FlowSummary summarize(List<Tick> ticks, {double bigValue = 1e9}) {
  double bv = 0, sv = 0, ov = 0, bval = 0, sval = 0, bigB = 0, bigS = 0;
  var bigBn = 0, bigSn = 0;
  for (final k in ticks) {
    switch (k.side) {
      case 'b':
        bv += k.vol;
        bval += k.value;
        if (k.value >= bigValue) {
          bigB += k.value;
          bigBn++;
        }
      case 's':
        sv += k.vol;
        sval += k.value;
        if (k.value >= bigValue) {
          bigS += k.value;
          bigSn++;
        }
      default:
        ov += k.vol;
    }
  }
  return FlowSummary(
    ticks: ticks.length,
    buyVol: bv,
    sellVol: sv,
    otherVol: ov,
    buyValue: bval,
    sellValue: sval,
    bigBuyValue: bigB,
    bigSellValue: bigS,
    bigBuyCount: bigBn,
    bigSellCount: bigSn,
    bigThreshold: bigValue,
  );
}

const _url = 'https://trading.vietcap.com.vn/api/market-watch/LEData/getAll';
const _headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  'Origin': 'https://trading.vietcap.com.vn',
  'Referer': 'https://trading.vietcap.com.vn/',
};

/// Một trang tối đa 100 lệnh có truncTime không lớn hơn [cursor] (null = mới nhất), mới nhất trước. Thử lại khi lỗi tạm thời.
Future<List<Tick>> fetchTickPage(String symbol, {int? cursor, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    for (var attempt = 1; ; attempt++) {
      try {
        final r = await c
            .post(Uri.parse(_url), headers: _headers, body: jsonEncode({'symbol': symbol, 'limit': 100, 'truncTime': cursor?.toString()}))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) return parseTicks(utf8.decode(r.bodyBytes));
        if (r.statusCode != 429 && r.statusCode < 500) throw TickException('Vietcap trả về HTTP ${r.statusCode}.');
      } on TickException {
        rethrow;
      } catch (_) {
        // lỗi mạng chập chờn: thử lại
      }
      if (attempt >= 3) throw TickException('Không tải được lệnh khớp từ Vietcap (mạng hoặc nguồn đang quá tải).');
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
  } finally {
    if (client == null) c.close();
  }
}

class TickException implements Exception {
  final String message;
  TickException(this.message);
  @override
  String toString() => message;
}

class TickLoad {
  final List<Tick> ticks; // tăng dần theo thời gian
  final String day; // yyyy-MM-dd của phiên
  final bool complete; // false nếu chạm giới hạn số lượt gọi nên có thể thiếu lệnh
  const TickLoad(this.ticks, this.day, this.complete);
}

/// 08:55 giờ Việt Nam của ngày [day] (yyyy-MM-dd), giây epoch: mốc đầu phiên (trước ATO).
int sessionStart(String day) {
  final d = DateTime.parse(day);
  return DateTime.utc(d.year, d.month, d.day, 1, 55).millisecondsSinceEpoch ~/ 1000;
}

/// Tải toàn bộ lệnh khớp của phiên gần nhất. Chia [0, mới nhất] thành [windows] khoảng chạy song song; mỗi khoảng phân trang lùi dần
/// (truncTime = thời điểm cũ nhất của trang trước) đến đầu khoảng. Giới hạn [maxRequests] lượt gọi để không dồn quá nhiều yêu cầu.
Future<TickLoad> loadSessionTicks(
  String symbol, {
  http.Client? client,
  int windows = 8,
  int maxRequests = 700,
  void Function(int ticks, int requests)? onProgress,
}) async {
  final first = await fetchTickPage(symbol, client: client);
  if (first.isEmpty) return const TickLoad([], '', true);
  final latest = first.map((k) => k.t).reduce((a, b) => a > b ? a : b);
  final day = vnDate(latest);
  final start = sessionStart(day);
  final byId = <int, Tick>{for (final k in first) k.id: k};
  var requests = 1;
  var truncated = false;
  final span = (latest + 1 - start);
  final step = (span / windows).ceil().clamp(1, span);

  Future<void> stream(int s, int e) async {
    var cursor = e;
    while (true) {
      if (requests >= maxRequests) {
        truncated = true;
        return;
      }
      requests++;
      final page = await fetchTickPage(symbol, cursor: cursor, client: client);
      for (final k in page) {
        if (k.t >= s && k.t <= e) byId[k.id] = k;
      }
      onProgress?.call(byId.length, requests);
      if (page.isEmpty) return;
      final minT = page.map((k) => k.t).reduce((a, b) => a < b ? a : b);
      if (minT <= s || page.length < 100) return;
      cursor = minT < cursor ? minT : cursor - 1; // cùng một giây có hơn 100 lệnh: lùi 1 giây để không lặp vô hạn
    }
  }

  await Future.wait([for (var s = start; s < latest + 1; s += step) stream(s, (s + step - 1) < latest ? s + step - 1 : latest)]);
  final ticks = byId.values.where((k) => k.t >= start).toList()..sort((a, b) => a.t != b.t ? a.t.compareTo(b.t) : a.id.compareTo(b.id));
  return TickLoad(ticks, day, !truncated);
}

/// Bổ sung các lệnh mới hơn [known] (đã tải trước đó) bằng cách lùi từ mới nhất đến lệnh đã biết. Trả về danh sách gộp.
Future<List<Tick>> refreshTicks(String symbol, List<Tick> known, {http.Client? client, int maxPages = 30}) async {
  if (known.isEmpty) return known;
  final seen = {for (final k in known) k.id: k};
  final knownMax = known.last.t;
  int? cursor;
  for (var i = 0; i < maxPages; i++) {
    final page = await fetchTickPage(symbol, cursor: cursor, client: client);
    if (page.isEmpty) break;
    for (final k in page) {
      seen[k.id] = k;
    }
    final minT = page.map((k) => k.t).reduce((a, b) => a < b ? a : b);
    if (minT <= knownMax || page.length < 100) break;
    cursor = minT;
  }
  return seen.values.toList()..sort((a, b) => a.t != b.t ? a.t.compareTo(b.t) : a.id.compareTo(b.id));
}
