// Danh mục đầu tư: mô hình dữ liệu, lưu trên máy (portfolios.json) và chỉ số định lượng tính cục bộ
// (lợi suất, rủi ro, beta, đa dạng hóa, đóng góp rủi ro, tập trung, kiểm tra sức chịu đựng).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'market.dart';
import 'quant.dart';

const portfolioGoals = ['Tăng trưởng', 'Cân bằng', 'Thu nhập'];
const portfolioHorizons = ['Ngắn hạn (dưới 1 năm)', 'Trung hạn (1–3 năm)', 'Dài hạn (trên 3 năm)'];
const portfolioRisks = ['Thấp', 'Vừa', 'Cao'];

/// Mỗi vị thế: {symbol, shares (cổ phiếu), cost (giá vốn, nghìn đồng/cổ phiếu, có thể bỏ trống)}.
Map<String, dynamic> newPortfolio(String name) {
  final now = DateTime.now();
  return {
    'id': '${now.millisecondsSinceEpoch}',
    'name': name,
    'goal': portfolioGoals[1],
    'horizon': portfolioHorizons[1],
    'risk': portfolioRisks[1],
    'cash': 0.0, // triệu đồng
    'holdings': <Map<String, dynamic>>[],
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
    'analyses': <Map<String, dynamic>>[],
  };
}

/// Các danh mục đã lưu trên máy, kèm lịch sử phân tích của từng danh mục.
class PortfolioStore extends ChangeNotifier {
  final File file;
  static const maxAnalyses = 10;
  List<Map<String, dynamic>> portfolios = [];
  PortfolioStore(this.file);

  Map<String, dynamic>? byId(String id) => portfolios.where((p) => p['id'] == id).firstOrNull;

  Future<void> load() async {
    try {
      if (await file.exists()) {
        portfolios = [for (final r in jsonDecode(await file.readAsString()) as List) Map<String, dynamic>.from(r as Map)];
      }
    } catch (_) {
      portfolios = [];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(portfolios), flush: true);
    } catch (_) {
      // Không ghi được ra đĩa thì vẫn giữ trong bộ nhớ của phiên này.
    }
  }

  /// Thêm mới hoặc cập nhật (theo id), giữ thứ tự: danh mục mới/vừa sửa lên đầu.
  Future<void> upsert(Map<String, dynamic> p) async {
    p['updated_at'] = DateTime.now().toIso8601String();
    portfolios = [p, ...portfolios.where((x) => x['id'] != p['id'])];
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    portfolios = [
      for (final p in portfolios)
        if (p['id'] != id) p,
    ];
    notifyListeners();
    await _save();
  }

  /// Gắn một bản phân tích mới (mới nhất trước) vào danh mục, giữ tối đa [maxAnalyses] bản.
  Future<void> addAnalysis(String id, Map<String, dynamic> analysis) async {
    final p = byId(id);
    if (p == null) return;
    final list = [analysis, ...((p['analyses'] as List?) ?? const []).cast<Map>().map((e) => Map<String, dynamic>.from(e))];
    p['analyses'] = list.take(maxAnalyses).toList();
    notifyListeners();
    await _save();
  }
}

int _ts(String date) => DateTime.parse('${date}T03:00:00Z').millisecondsSinceEpoch ~/ 1000;

double _mean(List<double> x) => x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;

double _cov(List<double> a, List<double> b) {
  if (a.length < 2) return 0;
  final ma = _mean(a), mb = _mean(b);
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - ma) * (b[i] - mb);
  }
  return s / (a.length - 1);
}

double? _r(double? v, [int d = 4]) {
  if (v == null || !v.isFinite) return null;
  final p = math.pow(10, d);
  return (v * p).round() / p;
}

/// Chỉ số định lượng của danh mục. [holdings]: danh sách vị thế; [bars]: nến ngày theo mã; [cash] tính bằng nghìn đồng;
/// [sectors]: mã → tên ngành. Trả về null nếu không có mã nào đủ dữ liệu giá.
Map<String, dynamic>? portfolioStats({
  required List<Map<String, dynamic>> holdings,
  required Map<String, List<Bar>> bars,
  required List<Bar> index,
  double cash = 0,
  double rf = 0.045,
  Map<String, String> sectors = const {},
}) {
  // Gộp vị thế trùng mã, bỏ mã không có đủ giá hoặc không có số lượng
  final shares = <String, double>{}, cost = <String, double>{};
  for (final h in holdings) {
    final s = '${h['symbol']}'.toUpperCase();
    final n = (h['shares'] as num?)?.toDouble() ?? 0;
    if (n <= 0) continue;
    final prev = shares[s] ?? 0;
    final c = (h['cost'] as num?)?.toDouble();
    if (c != null && c > 0) cost[s] = ((cost[s] ?? 0) * prev + c * n) / (prev + n);
    shares[s] = prev + n;
  }
  final skipped = <String>[];
  final symbols = <String>[];
  for (final s in shares.keys) {
    if ((bars[s]?.length ?? 0) >= 61) {
      symbols.add(s);
    } else {
      skipped.add(s);
    }
  }
  if (symbols.isEmpty) return null;

  // Ngày giao dịch chung của mọi mã và VN-Index, 253 phiên gần nhất
  final maps = {
    for (final s in symbols) s: {for (final b in bars[s]!) vnDate(b.t): b.c},
  };
  final idx = {for (final b in index) vnDate(b.t): b.c};
  var dates = idx.keys.where((d) => maps.values.every((m) => m.containsKey(d))).toList()..sort();
  if (dates.length > tradingDays + 1) dates = dates.sublist(dates.length - tradingDays - 1);
  if (dates.length < 61) return null;

  final price = {for (final s in symbols) s: bars[s]!.last.c};
  final value = {for (final s in symbols) s: shares[s]! * price[s]!};
  final total = value.values.fold<double>(0, (a, b) => a + b) + cash;
  if (total <= 0) return null;
  final w = {for (final s in symbols) s: value[s]! / total};
  final wCash = cash / total;

  List<double> rets(List<double> closes) => simpleReturns(closes);
  final r = {
    for (final s in symbols) s: rets([for (final d in dates) maps[s]![d]!]),
  };
  final m = rets([for (final d in dates) idx[d]!]);
  final n = m.length;

  // Danh mục giữ tỷ trọng hiện tại không đổi trong 1 năm; tiền mặt có lợi suất 0
  final pr = [for (var t = 0; t < n; t++) symbols.fold<double>(0, (a, s) => a + w[s]! * r[s]![t])];
  var level = 100.0;
  final pBars = [Bar(_ts(dates.first), level, level, level, level, 0)];
  for (var t = 0; t < n; t++) {
    level *= 1 + pr[t];
    pBars.add(Bar(_ts(dates[t + 1]), level, level, level, level, 0));
  }
  final iBars = [for (final d in dates) Bar(_ts(d), idx[d]!, idx[d]!, idx[d]!, idx[d]!, 0)];
  final q = quantStats(pBars, iBars, rf: rf);

  // Hiệp phương sai, tương quan, đóng góp rủi ro
  final k = symbols.length;
  final cov = [
    for (var i = 0; i < k; i++) [for (var j = 0; j < k; j++) _cov(r[symbols[i]]!, r[symbols[j]]!) * tradingDays],
  ];
  final wv = [for (final s in symbols) w[s]!];
  final cw = [
    for (var i = 0; i < k; i++) [for (var j = 0; j < k; j++) cov[i][j] * wv[j]].fold<double>(0, (a, b) => a + b),
  ];
  final variance = [for (var i = 0; i < k; i++) wv[i] * cw[i]].fold<double>(0, (a, b) => a + b);
  final sigma = math.sqrt(math.max(variance, 0));
  final vol = [for (var i = 0; i < k; i++) math.sqrt(math.max(cov[i][i], 0))];
  final corr = [
    for (var i = 0; i < k; i++) [for (var j = 0; j < k; j++) (vol[i] == 0 || vol[j] == 0) ? 0.0 : cov[i][j] / (vol[i] * vol[j])],
  ];
  final rc = [for (var i = 0; i < k; i++) variance == 0 ? 0.0 : wv[i] * cw[i] / variance];
  var pairs = 0.0, pairN = 0;
  for (var i = 0; i < k; i++) {
    for (var j = i + 1; j < k; j++) {
      pairs += corr[i][j];
      pairN++;
    }
  }
  final weightedVol = [for (var i = 0; i < k; i++) wv[i] * vol[i]].fold<double>(0, (a, b) => a + b);
  final hhi = wv.map((x) => x * x).fold<double>(0, (a, b) => a + b) + wCash * wCash;

  final varM = _cov(m, m);
  final betaOf = {for (final s in symbols) s: varM == 0 ? null : _cov(r[s]!, m) / varM};
  double cagr(List<double> c) => math.pow(c.last / c.first, tradingDays / (c.length - 1)).toDouble() - 1;

  final rows = [
    for (var i = 0; i < k; i++)
      {
        'ma': symbols[i],
        'nganh': sectors[symbols[i]],
        'so_luong': shares[symbols[i]],
        'gia': _r(price[symbols[i]], 2),
        'gia_tri_nghin_dong': _r(value[symbols[i]], 0),
        'ty_trong': _r(wv[i]),
        'gia_von': cost[symbols[i]],
        'lai_lo_pct': cost[symbols[i]] == null ? null : _r((price[symbols[i]]! / cost[symbols[i]]! - 1) * 100, 1),
        'loi_suat_nam': _r(cagr([for (final d in dates) maps[symbols[i]]![d]!])),
        'bien_dong_nam': _r(vol[i]),
        'beta': _r(betaOf[symbols[i]], 2),
        'dong_gop_rui_ro': _r(rc[i]),
      },
  ]..sort((a, b) => (b['ty_trong'] as double).compareTo(a['ty_trong'] as double));

  final bySector = <String, double>{};
  for (final s in symbols) {
    final name = sectors[s] ?? 'Chưa rõ ngành';
    bySector[name] = (bySector[name] ?? 0) + w[s]!;
  }
  final sectorRows = (bySector.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => {'nganh': e.key, 'ty_trong': _r(e.value)})
      .toList();

  final beta = (q?['beta'] as num?)?.toDouble();
  double worst(int len) {
    var x = 0.0;
    for (var i = len; i < pBars.length; i++) {
      x = math.min(x, pBars[i].c / pBars[i - len].c - 1);
    }
    return x;
  }

  final sortedW = [...wv]..sort((a, b) => b.compareTo(a));
  return {
    'den_ngay': dates.last,
    'tong_gia_tri_nghin_dong': _r(total, 0),
    'tien_mat_nghin_dong': _r(cash, 0),
    'ty_trong_tien_mat': _r(wCash),
    'so_ma': k,
    'ma_bi_bo_qua_thieu_du_lieu_gia': skipped,
    'chi_so_danh_muc': q,
    'vi_the': rows,
    'nganh': sectorRows,
    'da_dang_hoa': {
      'bien_dong_danh_muc_nam': _r(sigma),
      'ty_so_da_dang_hoa': sigma == 0 ? null : _r(weightedVol / sigma, 2),
      'tuong_quan_binh_quan_cap': pairN == 0 ? null : _r(pairs / pairN, 2),
      'hhi': _r(hhi),
      'so_ma_hieu_dung': hhi == 0 ? null : _r(1 / hhi, 1),
      'ty_trong_ma_lon_nhat': _r(sortedW.first),
      'ty_trong_3_ma_lon_nhat': _r(sortedW.take(3).fold<double>(0, (a, b) => a + b)),
      'so_nganh': bySector.length,
    },
    'tuong_quan': {
      'ma': symbols,
      'ma_tran': [
        for (final row in corr) [for (final c in row) _r(c, 2)],
      ],
    },
    'kiem_tra_suc_chiu_dung': {
      'cu_soc_theo_beta': [
        for (final shock in [-10, -20]) {'vnindex_pct': shock, 'danh_muc_uoc_tinh_pct': beta == null ? null : _r(beta * shock, 1)},
      ],
      'te_nhat_1_ngay_pct': _r(worst(1) * 100, 2),
      'te_nhat_20_phien_pct': _r(worst(20) * 100, 1),
      'luu_y': 'Giả định tỷ trọng hiện tại giữ nguyên 1 năm; cú sốc theo beta là tuyến tính nên chỉ mang tính ước lượng.',
    },
    'chuoi': {
      'dates': dates.sublist(0, dates.length),
      'danh_muc': [for (final p in pBars) _r((p.c / pBars.first.c - 1) * 100, 2)],
      'vnindex': [for (final d in dates) _r((idx[d]! / idx[dates.first]! - 1) * 100, 2)],
    },
  };
}

/// P/E, P/B (trung bình điều hòa theo tỷ trọng) và ROE (trung bình theo tỷ trọng) của danh mục từ chỉ số từng mã.
Map<String, double?> weightedValuation(List<Map<String, dynamic>> rows, Map<String, Map<String, dynamic>> snaps) {
  double? harmonic(String key) {
    var w = 0.0, y = 0.0;
    for (final r in rows) {
      final v = snaps[r['ma']]?[key];
      if (v is! num || v <= 0) continue;
      final weight = (r['ty_trong'] as num).toDouble();
      w += weight;
      y += weight / v;
    }
    return y == 0 ? null : _r(w / y, 2);
  }

  double? roe() {
    var w = 0.0, s = 0.0;
    for (final r in rows) {
      final v = snaps[r['ma']]?['roe'];
      if (v is! num) continue;
      final weight = (r['ty_trong'] as num).toDouble();
      w += weight;
      s += weight * (v.abs() > 1.5 ? v / 100 : v);
    }
    return w == 0 ? null : _r(s / w);
  }

  return {'pe': harmonic('pe'), 'pb': harmonic('pb'), 'roe': roe()};
}
