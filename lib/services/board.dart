// Bảng giá toàn sàn (Vietcap) và phân ngành ICB cấp 2 (Vietcap IQ).
// Giá trong bảng giá tính theo đồng; giá trị khớp `va` tính theo triệu đồng.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'market.dart' show userAgent;

const _boardUrl = 'https://trading.vietcap.com.vn/api/price/v1/w/priceboard/tickers/price/group';
const _screeningUrl = 'https://iq.vietcap.com.vn/api/iq-insight-service/v1/screening/paging';

/// Nhóm bảng giá: HOSE, HNX, UPCOM, VN30.
const boardGroups = ['HOSE', 'HNX', 'UPCOM', 'VN30'];

class BoardRow {
  final String symbol, exchange;
  final double ref, ceil, floor, price, open, high, low;
  final double volume, ptVolume; // KL khớp lệnh, KL thỏa thuận
  final double valueMn, ptValueMn; // triệu đồng
  final double foreignBuy, foreignSell; // KL

  const BoardRow({
    required this.symbol,
    required this.exchange,
    required this.ref,
    required this.ceil,
    required this.floor,
    required this.price,
    required this.open,
    required this.high,
    required this.low,
    required this.volume,
    required this.ptVolume,
    required this.valueMn,
    required this.ptValueMn,
    required this.foreignBuy,
    required this.foreignSell,
  });

  double get pct => ref > 0 ? (price / ref - 1) * 100 : 0;
  bool get atCeil => ceil > 0 && price >= ceil;
  bool get atFloor => floor > 0 && price > 0 && price <= floor;
  int get dir => price > ref ? 1 : (price < ref ? -1 : 0);
}

double _d(dynamic x) => x is num ? x.toDouble() : 0;

/// Chuyển phản hồi bảng giá thành danh sách cổ phiếu (bỏ chứng chỉ quỹ, ETF, chứng quyền).
List<BoardRow> parseBoard(List<dynamic> json) {
  final out = <BoardRow>[];
  for (final e in json) {
    if (e is! Map || e['st'] != 'STOCK') continue;
    final ref = _d(e['ref']);
    if (ref <= 0) continue;
    final c = _d(e['c']);
    out.add(
      BoardRow(
        symbol: e['s'] as String,
        exchange: switch (e['bo']) {
          'HSX' => 'HOSE',
          final x => x as String? ?? '',
        },
        ref: ref,
        ceil: _d(e['cei']),
        floor: _d(e['flo']),
        price: c > 0 ? c : ref,
        open: _d(e['op']),
        high: _d(e['h']),
        low: _d(e['l']),
        volume: _d(e['vo']),
        ptVolume: _d(e['ptv']),
        valueMn: _d(e['va']),
        ptValueMn: _d(e['pta']) / 1e6,
        foreignBuy: _d(e['frbv']),
        foreignSell: _d(e['frsv']),
      ),
    );
  }
  return out;
}

Future<List<BoardRow>> fetchBoard(String group) async {
  final resp = await http
      .post(
        Uri.parse(_boardUrl),
        headers: {
          ...userAgent,
          'Content-Type': 'application/json',
          'Origin': 'https://trading.vietcap.com.vn',
          'Referer': 'https://trading.vietcap.com.vn/',
        },
        body: jsonEncode({'group': group}),
      )
      .timeout(const Duration(seconds: 25));
  if (resp.statusCode != 200) throw Exception('Bảng giá $group: HTTP ${resp.statusCode}');
  return parseBoard(jsonDecode(utf8.decode(resp.bodyBytes)) as List);
}

/// Tổng hợp bảng giá: số mã tăng/giảm/đứng, dòng tiền theo nhóm, tổng KL/giá trị, khối ngoại.
class BoardStats {
  int up = 0, down = 0, flat = 0, ceil = 0, floor = 0;
  double upValueMn = 0, downValueMn = 0, flatValueMn = 0;
  double volume = 0, ptVolume = 0, valueMn = 0, ptValueMn = 0;
  double foreignBuy = 0, foreignSell = 0;

  BoardStats(Iterable<BoardRow> rows) {
    for (final r in rows) {
      switch (r.dir) {
        case 1:
          up++;
          upValueMn += r.valueMn;
        case -1:
          down++;
          downValueMn += r.valueMn;
        default:
          flat++;
          flatValueMn += r.valueMn;
      }
      if (r.atCeil) ceil++;
      if (r.atFloor) floor++;
      volume += r.volume;
      ptVolume += r.ptVolume;
      valueMn += r.valueMn;
      ptValueMn += r.ptValueMn;
      foreignBuy += r.foreignBuy;
      foreignSell += r.foreignSell;
    }
  }

  double get totalVolume => volume + ptVolume;
  double get totalValueTy => (valueMn + ptValueMn) / 1000;
  bool get hasData => up + down + flat > 0;
}

// ---------- Phân ngành ----------

class SectorInfo {
  final String name;
  final double marketCap;
  const SectorInfo(this.name, this.marketCap);
}

/// Đọc phản hồi screening của Vietcap IQ: mã → ngành (ICB cấp 2) và vốn hóa.
Map<String, SectorInfo> parseSectors(List<dynamic> content) => {
  for (final e in content)
    if (e is Map && e['ticker'] is String)
      e['ticker'] as String: SectorInfo(
        (e['viSector'] as String?)?.trim().isNotEmpty == true ? e['viSector'] as String : 'Khác',
        _d(e['marketCap']),
      ),
};

Future<Map<String, SectorInfo>> fetchSectors() async {
  final resp = await http
      .post(
        Uri.parse(_screeningUrl),
        headers: {
          ...userAgent,
          'Content-Type': 'application/json',
          'Origin': 'https://iq.vietcap.com.vn',
          'Referer': 'https://iq.vietcap.com.vn/',
        },
        body: jsonEncode({
          'page': 0,
          'pageSize': 3000,
          'sortFields': ['marketCap'],
          'sortOrders': ['DESC'],
          'filter': [],
        }),
      )
      .timeout(const Duration(seconds: 40));
  if (resp.statusCode != 200) throw Exception('Phân ngành: HTTP ${resp.statusCode}');
  final data = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  return parseSectors(data['content'] as List);
}

const sectorMaxAge = Duration(days: 7);

/// Phân ngành lưu đệm trong [file]; tự tải lại khi quá [sectorMaxAge] (mã mới niêm yết sẽ được xếp ngành).
/// Nếu không tải được thì dùng bản đệm cũ.
Future<Map<String, SectorInfo>> loadSectors(
  File file, {
  DateTime? now,
  Future<Map<String, SectorInfo>> Function()? fetch,
}) async {
  now ??= DateTime.now();
  Map<String, SectorInfo> cached = {};
  DateTime? savedAt;
  try {
    if (file.existsSync()) {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      savedAt = DateTime.parse(j['saved_at'] as String);
      cached = {
        for (final e in (j['sectors'] as Map<String, dynamic>).entries)
          e.key: SectorInfo((e.value as List)[0] as String, ((e.value as List)[1] as num).toDouble()),
      };
    }
  } catch (_) {
    cached = {};
    savedAt = null;
  }
  if (cached.isNotEmpty && savedAt != null && now.difference(savedAt) < sectorMaxAge) return cached;
  try {
    final fresh = await (fetch ?? fetchSectors)();
    if (fresh.isNotEmpty) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'saved_at': now.toIso8601String(),
          'sectors': {
            for (final e in fresh.entries) e.key: [e.value.name, e.value.marketCap],
          },
        }),
      );
      return fresh;
    }
  } catch (_) {}
  return cached;
}

/// Một ngành trên bản đồ nhiệt: các mã đã sắp xếp lớn → bé theo trọng số.
class SectorGroup {
  final String name;
  final List<BoardRow> rows;
  final double weight;
  SectorGroup(this.name, this.rows, this.weight);
}

/// Gom các mã vào ngành theo [sectors] (mã chưa có ngành → "Khác"), trọng số = giá trị giao dịch.
/// Nếu cả sàn chưa có giao dịch thì dùng vốn hóa. Kết quả sắp xếp ngành lớn → bé.
List<SectorGroup> groupBySector(List<BoardRow> rows, Map<String, SectorInfo> sectors) {
  double byValue(BoardRow r) => r.valueMn + r.ptValueMn;
  var weight = byValue;
  if (rows.every((r) => byValue(r) <= 0)) weight = (r) => sectors[r.symbol]?.marketCap ?? 0;
  final map = <String, List<BoardRow>>{};
  for (final r in rows) {
    if (weight(r) <= 0) continue;
    (map[sectors[r.symbol]?.name ?? 'Khác'] ??= []).add(r);
  }
  final groups = [
    for (final e in map.entries)
      SectorGroup(
        e.key,
        e.value..sort((a, b) => weight(b).compareTo(weight(a))),
        e.value.fold(0.0, (s, r) => s + weight(r)),
      ),
  ]..sort((a, b) => b.weight.compareTo(a.weight));
  return groups;
}

double rowWeight(BoardRow r, bool useValue, Map<String, SectorInfo> sectors) =>
    useValue ? r.valueMn + r.ptValueMn : (sectors[r.symbol]?.marketCap ?? 0);
