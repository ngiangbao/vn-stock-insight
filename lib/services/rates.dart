// Lãi suất hằng ngày: lợi suất trái phiếu chính phủ theo kỳ hạn, lãi suất điều hành, lãi suất liên ngân hàng, CPI và lãi suất
// tiền gửi từng ngân hàng; lãi suất thực tự tính (lãi suất danh nghĩa trừ CPI cùng kỳ).
//
// Nguồn (đều công khai, không cần key):
//  - TradingView scanner (dữ liệu gốc của TradingEconomics): lợi suất TPCP, lãi suất điều hành, liên ngân hàng, CPI. Điểm cuối này
//    không có tài liệu chính thức nên có thể thay đổi; khi lỗi, app dùng lại số liệu đã lưu.
//  - CafeF: bảng lãi suất tiền gửi của các ngân hàng theo kỳ hạn.
// Lãi suất cho vay không có nguồn miễn phí cập nhật hằng ngày; Ngân hàng Nhà nước chỉ công bố bình quân hằng tháng.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const yieldTenors = [
  ('1N', 1, 'TVC:VN01Y'),
  ('2N', 2, 'TVC:VN02Y'),
  ('3N', 3, 'TVC:VN03Y'),
  ('5N', 5, 'TVC:VN05Y'),
  ('7N', 7, 'TVC:VN07Y'),
  ('10N', 10, 'TVC:VN10Y'),
  ('15N', 15, 'TVC:VN15Y'),
  ('20N', 20, 'TVC:VN20Y'),
  ('30N', 30, 'TVC:VN30Y'),
];

const depositTerms = [1, 3, 6, 9, 12, 18, 24];

const _tvHeaders = {
  'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  'Referer': 'https://www.tradingview.com/',
  'Accept': 'application/json',
};
const _cafefUrl = 'https://cafefnew.mediacdn.vn/Images/Uploaded/DuLieuDownload/Liveboard/all_banks_interest_rates.json';

/// Thống kê lãi suất tiền gửi của một kỳ hạn qua các ngân hàng.
class DepositStat {
  final double avg, min, max;
  final int banks;
  final String? bestBank;
  const DepositStat(this.avg, this.min, this.max, this.banks, this.bestBank);

  Map<String, dynamic> toJson() => {'avg': avg, 'min': min, 'max': max, 'n': banks, 'best': bestBank};
  factory DepositStat.fromJson(Map m) => DepositStat(
    (m['avg'] as num).toDouble(),
    (m['min'] as num).toDouble(),
    (m['max'] as num).toDouble(),
    (m['n'] as num).toInt(),
    m['best'] as String?,
  );
}

class RatesSnapshot {
  final DateTime fetchedAt;

  /// Lợi suất TPCP theo số năm kỳ hạn (%).
  final Map<int, double> yields;
  final double? policy, interbank, cpiYoy, coreCpi;

  /// Ngày của số liệu liên ngân hàng và kỳ CPI (yyyy-MM-dd) theo nguồn.
  final String? interbankDate, cpiPeriod;
  final Map<int, DepositStat> deposits;

  /// Chỉ tiêu không tải được và cũng chưa có bản lưu.
  final Set<String> failed;
  final bool fromCache;
  const RatesSnapshot({
    required this.fetchedAt,
    this.yields = const {},
    this.policy,
    this.interbank,
    this.cpiYoy,
    this.coreCpi,
    this.interbankDate,
    this.cpiPeriod,
    this.deposits = const {},
    this.failed = const {},
    this.fromCache = false,
  });

  double? get y10 => yields[10];
  double? get dep12 => deposits[12]?.avg;

  // Lãi suất thực = lãi suất danh nghĩa trừ CPI cùng kỳ (nhìn lại, vì CPI là số đã qua).
  double? get real10y => y10 == null || cpiYoy == null ? null : y10! - cpiYoy!;
  double? get realDeposit12 => dep12 == null || cpiYoy == null ? null : dep12! - cpiYoy!;
  double? get realPolicy => policy == null || cpiYoy == null ? null : policy! - cpiYoy!;

  Map<String, dynamic> toJson() => {
    'fetchedAt': fetchedAt.toIso8601String(),
    'yields': {for (final e in yields.entries) '${e.key}': e.value},
    'policy': policy,
    'interbank': interbank,
    'cpiYoy': cpiYoy,
    'coreCpi': coreCpi,
    'interbankDate': interbankDate,
    'cpiPeriod': cpiPeriod,
    'deposits': {for (final e in deposits.entries) '${e.key}': e.value.toJson()},
  };

  factory RatesSnapshot.fromJson(Map<String, dynamic> j, {bool fromCache = true}) => RatesSnapshot(
    fetchedAt: DateTime.parse(j['fetchedAt'] as String),
    yields: {for (final e in ((j['yields'] as Map?) ?? const {}).entries) int.parse('${e.key}'): (e.value as num).toDouble()},
    policy: (j['policy'] as num?)?.toDouble(),
    interbank: (j['interbank'] as num?)?.toDouble(),
    cpiYoy: (j['cpiYoy'] as num?)?.toDouble(),
    coreCpi: (j['coreCpi'] as num?)?.toDouble(),
    interbankDate: j['interbankDate'] as String?,
    cpiPeriod: j['cpiPeriod'] as String?,
    deposits: {for (final e in ((j['deposits'] as Map?) ?? const {}).entries) int.parse('${e.key}'): DepositStat.fromJson(e.value as Map)},
    fromCache: fromCache,
  );
}

/// Chuyển phản hồi của điểm cuối /symbol thành (giá trị, ngày yyyy-MM-dd) hoặc null.
({double value, String date})? parseScannerSymbol(String body) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final close = (j['close'] as num?)?.toDouble();
    final t = (j['time'] as num?)?.toInt();
    if (close == null) return null;
    final date = t == null ? '' : DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true).toIso8601String().substring(0, 10);
    return (value: close, date: date);
  } catch (_) {
    return null;
  }
}

/// Thống kê lãi suất tiền gửi theo kỳ hạn từ file JSON của CafeF; bỏ giá trị trống hoặc bằng 0.
Map<int, DepositStat> parseDeposits(String body) {
  final out = <int, DepositStat>{};
  try {
    final data = ((jsonDecode(body) as Map)['Data'] as List).cast<Map>();
    for (final term in depositTerms) {
      final vals = <(String, double)>[];
      for (final b in data) {
        for (final r in ((b['interestRates'] as List?) ?? const []).cast<Map>()) {
          final v = r['value'];
          if (r['deposit'] == term && v is num && v > 0) vals.add(('${b['name']}', v.toDouble()));
        }
      }
      if (vals.isEmpty) continue;
      final nums = [for (final v in vals) v.$2];
      final best = vals.reduce((a, b) => b.$2 > a.$2 ? b : a);
      out[term] = DepositStat(
        nums.reduce((a, b) => a + b) / nums.length,
        nums.reduce((a, b) => a < b ? a : b),
        nums.reduce((a, b) => a > b ? a : b),
        nums.length,
        best.$1,
      );
    }
  } catch (_) {}
  return out;
}

String _today() => DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);

class RatesRepository {
  final File? cacheFile, historyFile;
  final http.Client _client;
  final Duration maxAge;
  static const keepDays = 400;
  RatesRepository({this.cacheFile, this.historyFile, http.Client? client, this.maxAge = const Duration(minutes: 30)})
    : _client = client ?? http.Client();

  Future<String?> _get(String url, {Map<String, String>? headers}) async {
    try {
      final r = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 20));
      return r.statusCode == 200 ? utf8.decode(r.bodyBytes) : null;
    } catch (_) {
      return null;
    }
  }

  Future<({double value, String date})?> _symbol(String symbol) async {
    final body = await _get(
      'https://scanner.tradingview.com/symbol?symbol=${Uri.encodeComponent(symbol)}&fields=close,description,time',
      headers: _tvHeaders,
    );
    return body == null ? null : parseScannerSymbol(body);
  }

  Future<RatesSnapshot?> cached() async {
    try {
      if (cacheFile != null && await cacheFile!.exists()) {
        return RatesSnapshot.fromJson(jsonDecode(await cacheFile!.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  Future<RatesSnapshot> load({bool force = false}) async {
    final old = await cached();
    if (!force && old != null && DateTime.now().difference(old.fetchedAt) < maxAge) return old;

    final results = await Future.wait<({double value, String date})?>([
      for (final t in yieldTenors) _symbol(t.$3),
      _symbol('ECONOMICS:VNINTR'),
      _symbol('ECONOMICS:VNINBR'),
      _symbol('ECONOMICS:VNIRYY'),
      _symbol('ECONOMICS:VNCIR'),
    ]);
    final n = yieldTenors.length;
    final cafef = await _get(_cafefUrl, headers: {'User-Agent': _tvHeaders['User-Agent']!, 'Referer': 'https://cafef.vn/'});
    final deposits = cafef == null ? <int, DepositStat>{} : parseDeposits(cafef);

    final failed = <String>{};
    final yields = <int, double>{};
    for (var i = 0; i < n; i++) {
      final r = results[i];
      if (r != null) {
        yields[yieldTenors[i].$2] = r.value;
      } else if (old?.yields[yieldTenors[i].$2] != null) {
        yields[yieldTenors[i].$2] = old!.yields[yieldTenors[i].$2]!;
      } else {
        failed.add('Lợi suất ${yieldTenors[i].$1}');
      }
    }
    final pol = results[n], inter = results[n + 1], cpi = results[n + 2], core = results[n + 3];
    if (pol == null && old?.policy == null) failed.add('Lãi suất điều hành');
    if (inter == null && old?.interbank == null) failed.add('Lãi suất liên ngân hàng');
    if (cpi == null && old?.cpiYoy == null) failed.add('CPI');
    if (deposits.isEmpty && (old?.deposits.isEmpty ?? true)) failed.add('Lãi suất tiền gửi');

    final snap = RatesSnapshot(
      fetchedAt: DateTime.now(),
      yields: yields,
      policy: pol?.value ?? old?.policy,
      interbank: inter?.value ?? old?.interbank,
      interbankDate: inter?.date ?? old?.interbankDate,
      cpiYoy: cpi?.value ?? old?.cpiYoy,
      cpiPeriod: cpi?.date ?? old?.cpiPeriod,
      coreCpi: core?.value ?? old?.coreCpi,
      deposits: deposits.isNotEmpty ? deposits : (old?.deposits ?? const {}),
      failed: failed,
    );
    // Không có chỉ tiêu nào tải được và cũng không có bản lưu: báo lỗi thay vì ghi đè bản lưu bằng dữ liệu rỗng
    if (yields.isEmpty && snap.policy == null && snap.interbank == null && snap.cpiYoy == null && snap.deposits.isEmpty) {
      return old ?? snap;
    }
    await _save(snap);
    return snap;
  }

  /// Giá trị các chỉ tiêu chính theo ngày (giờ Việt Nam), lưu lại để so sánh với lần trước.
  Future<Map<String, Map<String, double>>> history() async {
    try {
      if (historyFile != null && await historyFile!.exists()) {
        final raw = jsonDecode(await historyFile!.readAsString()) as Map<String, dynamic>;
        return {
          for (final e in raw.entries) e.key: {for (final v in (e.value as Map).entries) '${v.key}': (v.value as num).toDouble()},
        };
      }
    } catch (_) {}
    return {};
  }

  /// Số liệu của ngày gần nhất trước hôm nay, null nếu chưa có.
  Future<Map<String, double>?> previousDay() async {
    final h = await history();
    final days = h.keys.where((d) => d.compareTo(_today()) < 0).toList()..sort();
    return days.isEmpty ? null : h[days.last];
  }

  Future<void> _save(RatesSnapshot s) async {
    try {
      if (cacheFile != null) {
        await cacheFile!.parent.create(recursive: true);
        await cacheFile!.writeAsString(jsonEncode(s.toJson()), flush: true);
      }
      if (historyFile != null) {
        final h = await history();
        h[_today()] = {
          if (s.y10 != null) 'y10': s.y10!,
          if (s.policy != null) 'policy': s.policy!,
          if (s.interbank != null) 'interbank': s.interbank!,
          if (s.dep12 != null) 'dep12': s.dep12!,
          if (s.cpiYoy != null) 'cpi': s.cpiYoy!,
        };
        final days = h.keys.toList()..sort();
        for (final d in days.take(days.length > keepDays ? days.length - keepDays : 0)) {
          h.remove(d);
        }
        await historyFile!.parent.create(recursive: true);
        await historyFile!.writeAsString(jsonEncode(h), flush: true);
      }
    } catch (_) {
      // Không ghi được ra đĩa thì vẫn dùng số liệu vừa tải trong phiên này.
    }
  }
}
