// Số liệu kinh tế vĩ mô Việt Nam từ các nguồn công khai miễn phí:
//  - World Bank (số liệu thực tế hàng năm),
//  - IMF World Economic Outlook (thực tế và dự báo hàng năm, DataMapper),
//  - Yahoo Finance (tỷ giá USD/VND hàng tháng).
// Số liệu hàng tháng của Tổng cục Thống kê (CPI, xuất nhập khẩu theo tháng...) không có API công khai miễn phí
// nên không được đưa vào; trang vĩ mô ghi rõ điều này, không tự suy ra số.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum MacroSource { worldBank, imf, yahoo }

/// Một điểm dữ liệu: [period] là "2025" (năm) hoặc "2025-10" (tháng).
class MacroPoint {
  final String period;
  final double value;
  final bool forecast;
  const MacroPoint(this.period, this.value, {this.forecast = false});

  int get year => int.parse(period.substring(0, 4));
  int? get month => period.length >= 7 ? int.parse(period.substring(5, 7)) : null;

  /// Nhãn hiển thị: "2025" hoặc "10/2025".
  String get label {
    final m = month;
    return m == null ? '$year' : '${m.toString().padLeft(2, '0')}/$year';
  }
}

/// Khai báo một chỉ tiêu: lấy ở đâu, đơn vị gì.
class MacroDef {
  final String id, title, unit, code;
  final MacroSource kind;
  final double scale; // nhân vào giá trị gốc (ví dụ 1e-9 để đổi USD sang tỷ USD)
  final int decimals;
  const MacroDef(this.id, this.title, this.unit, this.kind, this.code, {this.scale = 1, this.decimals = 1});

  bool get monthly => kind == MacroSource.yahoo;
  String get frequency => monthly ? 'Hàng tháng' : 'Hàng năm';
  String get sourceName => switch (kind) {
        MacroSource.worldBank => 'World Bank',
        MacroSource.imf => 'IMF, gồm dự báo',
        MacroSource.yahoo => 'Yahoo Finance',
      };

  /// Đơn vị của chênh lệch giữa hai kỳ: với tỷ lệ % thì chênh lệch tính bằng điểm phần trăm.
  String get diffUnit => unit == '%' ? 'điểm %' : unit;
}

const macroDefs = <MacroDef>[
  // IMF: có thực tế và dự báo
  MacroDef('gdp_growth', 'Tăng trưởng GDP thực', '%', MacroSource.imf, 'NGDP_RPCH'),
  MacroDef('inflation', 'Lạm phát (CPI bình quân năm)', '%', MacroSource.imf, 'PCPIPCH'),
  MacroDef('unemployment', 'Tỷ lệ thất nghiệp', '%', MacroSource.imf, 'LUR'),
  MacroDef('current_account', 'Cán cân vãng lai (% GDP)', '% GDP', MacroSource.imf, 'BCA_NGDPD'),
  MacroDef('gov_debt', 'Nợ công (% GDP)', '% GDP', MacroSource.imf, 'GGXWDG_NGDP'),
  MacroDef('fiscal_balance', 'Cán cân ngân sách (% GDP)', '% GDP', MacroSource.imf, 'GGXCNL_NGDP'),
  MacroDef('gdp_usd', 'Quy mô GDP', 'tỷ USD', MacroSource.imf, 'NGDPD', decimals: 0),
  MacroDef('gdp_pc', 'GDP bình quân đầu người', 'USD', MacroSource.imf, 'NGDPDPC', decimals: 0),
  // World Bank: thực tế
  MacroDef('exports', 'Xuất khẩu hàng hóa và dịch vụ', 'tỷ USD', MacroSource.worldBank, 'NE.EXP.GNFS.CD', scale: 1e-9),
  MacroDef('imports', 'Nhập khẩu hàng hóa và dịch vụ', 'tỷ USD', MacroSource.worldBank, 'NE.IMP.GNFS.CD', scale: 1e-9),
  MacroDef('trade_balance', 'Cán cân thương mại', 'tỷ USD', MacroSource.worldBank, 'NE.RSB.GNFS.CD', scale: 1e-9),
  MacroDef('fdi', 'Đầu tư trực tiếp nước ngoài ròng', 'tỷ USD', MacroSource.worldBank, 'BX.KLT.DINV.CD.WD', scale: 1e-9),
  MacroDef('lending_rate', 'Lãi suất cho vay', '%', MacroSource.worldBank, 'FR.INR.LEND'),
  MacroDef('real_rate', 'Lãi suất thực', '%', MacroSource.worldBank, 'FR.INR.RINR'),
  MacroDef('m2', 'Cung tiền M2 (% GDP)', '% GDP', MacroSource.worldBank, 'FM.LBL.BMNY.GD.ZS'),
  MacroDef('population', 'Dân số', 'triệu người', MacroSource.worldBank, 'SP.POP.TOTL', scale: 1e-6),
  // Yahoo Finance: hàng tháng
  MacroDef('usdvnd', 'Tỷ giá USD/VND', 'VND/USD', MacroSource.yahoo, 'VND=X', decimals: 0),
];

MacroDef macroDef(String id) => macroDefs.firstWhere((d) => d.id == id);

class MacroTab {
  final String title;
  final List<String> ids;
  const MacroTab(this.title, this.ids);
}

const macroTabs = <MacroTab>[
  MacroTab('Tổng quan', ['gdp_growth', 'inflation', 'trade_balance', 'fdi', 'usdvnd', 'unemployment']),
  MacroTab('GDP', ['gdp_growth', 'gdp_usd', 'gdp_pc']),
  MacroTab('Giá cả & lãi suất', ['inflation', 'lending_rate', 'real_rate']),
  MacroTab('Thương mại', ['exports', 'imports', 'trade_balance', 'current_account', 'fdi']),
  MacroTab('Lao động & dân số', ['unemployment', 'population']),
  MacroTab('Tiền tệ', ['usdvnd', 'm2']),
  MacroTab('Tài khóa', ['gov_debt', 'fiscal_balance']),
];

class MacroSeries {
  final MacroDef def;
  final List<MacroPoint> points; // đã sắp theo thời gian tăng dần
  const MacroSeries(this.def, this.points);

  List<MacroPoint> get actual => [for (final p in points) if (!p.forecast) p];
  MacroPoint? get latest => actual.isEmpty ? null : actual.last;
  MacroPoint? get previous => actual.length < 2 ? null : actual[actual.length - 2];
  bool get hasForecast => points.any((p) => p.forecast);

  /// Các điểm trong [years] năm gần nhất (tính đến kỳ thực tế mới nhất); 0 hoặc null = toàn bộ.
  /// Điểm dự báo luôn được giữ lại.
  List<MacroPoint> window(int? years) {
    final last = latest;
    if (years == null || years <= 0 || last == null) return points;
    final minYear = last.year - years + 1;
    return [for (final p in points) if (p.year >= minYear) p];
  }
}

// ---------- Đọc dữ liệu từ các nguồn ----------

/// World Bank: `[meta, [ {date: "2025", value: 8.0}, ... ]]`, giá trị null bị bỏ.
List<MacroPoint> parseWorldBank(String body, {double scale = 1}) {
  final json = jsonDecode(body);
  if (json is! List || json.length < 2 || json[1] is! List) return const [];
  final points = [
    for (final row in (json[1] as List).cast<Map<String, dynamic>>())
      if (row['value'] is num) MacroPoint(row['date'].toString(), (row['value'] as num).toDouble() * scale),
  ]..sort((a, b) => a.period.compareTo(b.period));
  return points;
}

/// IMF DataMapper: `{values: {CODE: {VNM: {"2025": 8.0, ...}}}}`. Từ năm [firstForecastYear] trở đi là dự báo.
List<MacroPoint> parseImf(String body, String code, {required int firstForecastYear}) {
  final json = jsonDecode(body);
  final byYear = (((json is Map ? json['values'] : null) as Map?)?[code] as Map?)?['VNM'];
  if (byYear is! Map) return const [];
  final points = [
    for (final e in byYear.entries)
      if (e.value is num)
        MacroPoint(e.key.toString(), (e.value as num).toDouble(), forecast: int.parse(e.key.toString()) >= firstForecastYear),
  ]..sort((a, b) => a.period.compareTo(b.period));
  return points;
}

/// Yahoo Finance chart API (khung 1 tháng): giá đóng cửa từng tháng, kỳ là "YYYY-MM".
List<MacroPoint> parseYahooMonthly(String body) {
  final result = ((jsonDecode(body) as Map)['chart']?['result'] as List?)?.firstOrNull as Map?;
  if (result == null) return const [];
  final times = (result['timestamp'] as List?) ?? const [];
  final closes = (((result['indicators'] as Map?)?['quote'] as List?)?.firstOrNull as Map?)?['close'] as List? ?? const [];
  final points = <MacroPoint>[];
  for (var i = 0; i < times.length && i < closes.length; i++) {
    final c = closes[i];
    if (c is! num) continue;
    final d = DateTime.fromMillisecondsSinceEpoch((times[i] as num).toInt() * 1000, isUtc: true);
    points.add(MacroPoint('${d.year}-${d.month.toString().padLeft(2, '0')}', c.toDouble()));
  }
  return points;
}

// ---------- Tải và lưu đệm ----------

class MacroSnapshot {
  final Map<String, MacroSeries> series;
  final DateTime fetchedAt;
  final Set<String> failed; // chỉ tiêu không tải được và cũng chưa có bản lưu đệm
  final bool fromCache;
  const MacroSnapshot(this.series, this.fetchedAt, {this.failed = const {}, this.fromCache = false});
}

class MacroRepository {
  final File? cacheFile;
  final http.Client _client;
  final DateTime Function() _now;
  final Duration maxAge;

  MacroRepository({this.cacheFile, http.Client? client, DateTime Function()? now, this.maxAge = const Duration(hours: 12)})
      : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  // IMF chặn User-Agent dạng "Mozilla/…" (chống bot) nhưng nhận User-Agent tự giới thiệu; Yahoo thì ngược lại.
  static const _appAgent = {'User-Agent': 'vn-stock-insight/1.2 (+https://github.com/ngiangbao/vn-stock-insight)'};
  static const _browserAgent = {'User-Agent': 'Mozilla/5.0 (vn-stock-insight)'};

  Uri _uri(MacroDef d) => switch (d.kind) {
        MacroSource.worldBank =>
          Uri.parse('https://api.worldbank.org/v2/country/VN/indicator/${d.code}?format=json&per_page=100'),
        MacroSource.imf => Uri.parse('https://www.imf.org/external/datamapper/api/v1/${d.code}/VNM'),
        MacroSource.yahoo =>
          Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(d.code)}?range=max&interval=1mo'),
      };

  Future<MacroSeries?> _fetch(MacroDef d) async {
    try {
      final resp = await _client
          .get(_uri(d), headers: d.kind == MacroSource.yahoo ? _browserAgent : _appAgent)
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) return null;
      final body = utf8.decode(resp.bodyBytes);
      final points = switch (d.kind) {
        MacroSource.worldBank => parseWorldBank(body, scale: d.scale),
        // Dự báo của IMF bắt đầu từ năm hiện tại: các năm trước đó là số liệu thực tế hoặc ước tính đã chốt
        MacroSource.imf => parseImf(body, d.code, firstForecastYear: _now().year),
        MacroSource.yahoo => parseYahooMonthly(body),
      };
      return points.length < 2 ? null : MacroSeries(d, points);
    } catch (_) {
      return null;
    }
  }

  /// Dùng bản lưu đệm nếu còn mới (mặc định 12 giờ); [force] bắt buộc tải lại.
  /// Chỉ tiêu nào tải lỗi thì giữ bản lưu đệm cũ của chỉ tiêu đó.
  Future<MacroSnapshot> load({bool force = false}) async {
    final cached = await _readCache();
    if (!force && cached != null && _now().difference(cached.fetchedAt) < maxAge) {
      return MacroSnapshot(cached.series, cached.fetchedAt, fromCache: true);
    }
    final fetched = await Future.wait(macroDefs.map(_fetch));
    final series = <String, MacroSeries>{};
    final failed = <String>{};
    var anyFresh = false;
    for (final (i, d) in macroDefs.indexed) {
      final s = fetched[i] ?? cached?.series[d.id];
      if (s == null) {
        failed.add(d.id);
      } else {
        series[d.id] = s;
        if (fetched[i] != null) anyFresh = true;
      }
    }
    final snap = MacroSnapshot(series, anyFresh ? _now() : (cached?.fetchedAt ?? _now()), failed: failed, fromCache: !anyFresh);
    if (anyFresh) await _writeCache(snap);
    return snap;
  }

  Future<MacroSnapshot?> _readCache() async {
    final f = cacheFile;
    if (f == null || !await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final series = <String, MacroSeries>{};
      for (final d in macroDefs) {
        final rows = json['series']?[d.id] as List?;
        if (rows == null) continue;
        series[d.id] = MacroSeries(d, [
          for (final r in rows.cast<List>()) MacroPoint(r[0] as String, (r[1] as num).toDouble(), forecast: r[2] == 1),
        ]);
      }
      return MacroSnapshot(series, DateTime.parse(json['fetchedAt'] as String), fromCache: true);
    } catch (_) {
      return null; // file hỏng: tải lại từ đầu
    }
  }

  Future<void> _writeCache(MacroSnapshot snap) async {
    final f = cacheFile;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'fetchedAt': snap.fetchedAt.toIso8601String(),
        'series': {
          for (final s in snap.series.values)
            s.def.id: [for (final p in s.points) [p.period, p.value, p.forecast ? 1 : 0]],
        },
      }));
    } catch (_) {
      // không ghi được bản lưu đệm cũng không sao
    }
  }
}
