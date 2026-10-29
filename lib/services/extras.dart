// Phân tích bổ sung theo chủ đề cho báo cáo AI một cổ phiếu: dựng dữ liệu bổ sung (tính trên máy), gọi AI, lưu vào bản ghi.

import '../ai/extra_prompts.dart';
import '../ai/providers.dart';
import '../state.dart';
import 'board.dart';
import 'cfa.dart';
import 'market.dart';
import 'news.dart';
import '../ui/liquidity_chart.dart' show sessionsOf;
import 'quant.dart';

double? _r(double? v, [int d = 2]) {
  if (v == null || !v.isFinite) return null;
  final p = 1.0 * (d == 0 ? 1 : d == 1 ? 10 : d == 2 ? 100 : 10000);
  return (v * p).round() / p;
}

/// Lợi suất (%) trong [n] phiên gần nhất, null nếu không đủ dữ liệu.
double? retPct(List<Bar> b, int n) => b.length > n ? (b.last.c / b[b.length - 1 - n].c - 1) * 100 : null;

/// Lợi suất (%) từ đầu năm (phiên cuối năm trước).
double? ytdPct(List<Bar> b) {
  if (b.isEmpty) return null;
  final year = vnDate(b.last.t).substring(0, 4);
  final before = b.where((x) => vnDate(x.t).substring(0, 4).compareTo(year) < 0).toList();
  return before.isEmpty ? null : (b.last.c / before.last.c - 1) * 100;
}

Map<String, double?> periodReturns(List<Bar> b) => {
      '1_tuan': _r(retPct(b, 5)),
      '1_thang': _r(retPct(b, 21)),
      '3_thang': _r(retPct(b, 63)),
      '6_thang': _r(retPct(b, 126)),
      'tu_dau_nam': _r(ytdPct(b)),
    };

/// Trung bình có trọng số vốn hóa của một chỉ tiêu theo từng mã (bỏ mã thiếu).
double? weightedMean(Map<String, double?> values, Map<String, double> weights) {
  var s = 0.0, w = 0.0;
  for (final e in values.entries) {
    final v = e.value, c = weights[e.key];
    if (v == null || c == null || c <= 0) continue;
    s += v * c;
    w += c;
  }
  return w == 0 ? null : s / w;
}

extension ExtraAnalyses on AppState {
  List<BoardRow> get _allRows => [for (final rows in dash.boards.values) ...rows];

  List<String> _sectorMembers(String symbol) {
    final name = dash.sectors[symbol]?.name;
    if (name == null) return [];
    return (dash.sectors.entries.where((e) => e.value.name == name).toList()..sort((a, b) => b.value.marketCap.compareTo(a.value.marketCap)))
        .map((e) => e.key)
        .toList();
  }

  Future<Map<String, dynamic>> _sectorData(String symbol) async {
    final name = dash.sectors[symbol]?.name;
    final members = _sectorMembers(symbol);
    if (name == null || members.isEmpty) return {'ghi_chu': 'Không xác định được ngành của $symbol (chưa tải danh sách ngành).'};
    final caps = {for (final m in members) m: dash.sectors[m]!.marketCap};
    final rows = {for (final r in _allRows) r.symbol: r};

    // Hôm nay: biến động, độ rộng, giá trị giao dịch, khối ngoại của cả ngành
    final today = <String, double?>{};
    var up = 0, down = 0, flat = 0, valueMn = 0.0, foreignNet = 0.0;
    for (final m in members) {
      final r = rows[m];
      if (r == null || r.ref <= 0 || r.price <= 0) continue;
      final c = (r.price / r.ref - 1) * 100;
      today[m] = c;
      if (c > 0.005) {
        up++;
      } else if (c < -0.005) {
        down++;
      } else {
        flat++;
      }
      valueMn += r.valueMn;
      foreignNet += (r.foreignBuy - r.foreignSell) * r.price / 1e9;
    }
    final ranked = today.entries.where((e) => e.value != null).toList()..sort((a, b) => b.value!.compareTo(a.value!));

    // Lịch sử: top 8 theo vốn hóa
    final top = members.take(8).toList();
    final bars = await Future.wait([for (final m in top) fetchBars(m, days: 400)]);
    final index = await fetchBars('VNINDEX', days: 400, isIndex: true);
    final perMember = {for (var i = 0; i < top.length; i++) top[i]: periodReturns(bars[i])};
    Map<String, double?> sectorPerf() => {
          for (final k in const ['1_tuan', '1_thang', '3_thang', '6_thang', 'tu_dau_nam'])
            k: _r(weightedMean({for (final e in perMember.entries) e.key: e.value[k]}, caps)),
        };
    final own = bars.isEmpty || !top.contains(symbol) ? periodReturns(await fetchBars(symbol, days: 400)) : perMember[symbol]!;
    return {
      'nganh': name,
      'so_ma_trong_nganh': members.length,
      'hom_nay': {
        'bien_dong_binh_quan_theo_von_hoa_pct': _r(weightedMean(today, caps)),
        'so_ma_tang': up,
        'so_ma_giam': down,
        'so_ma_dung_gia': flat,
        'gia_tri_giao_dich_ty_dong': _r(valueMn / 1000, 1),
        'khoi_ngoai_mua_ban_rong_ty_dong': _r(foreignNet, 1),
        'ma_tang_manh_nhat': [for (final e in ranked.take(3)) {'ma': e.key, 'pct': _r(e.value)}],
        'ma_giam_manh_nhat': [for (final e in ranked.reversed.take(3)) {'ma': e.key, 'pct': _r(e.value)}],
        'co_phieu_dang_xet_pct': _r(today[symbol]),
      },
      'hieu_suat_nganh_pct_theo_von_hoa_top8': sectorPerf(),
      'hieu_suat_vnindex_pct': periodReturns(index),
      'hieu_suat_co_phieu_pct': own,
      'hieu_suat_tung_ma_top8_pct': perMember,
      'luu_y': 'Hiệu suất ngành tính trung bình có trọng số vốn hóa của tối đa 8 mã lớn nhất ngành, không phải chỉ số ngành chính thức.',
    };
  }

  Future<Map<String, dynamic>> _peersData(String symbol) async {
    final members = _sectorMembers(symbol);
    final peers = members.where((m) => m != symbol).take(6).toList();
    if (peers.isEmpty) return {'ghi_chu': 'Không tìm thấy doanh nghiệp cùng ngành (chưa tải danh sách ngành).'};
    final all = [symbol, ...peers];
    final snaps = await Future.wait(all.map(peerSnapshot));
    final bars = await Future.wait(all.map((m) => fetchBars(m, days: 400)));
    final rows = [
      for (var i = 0; i < all.length; i++)
        {
          ...snaps[i],
          'hieu_suat_pct': {'1_thang': _r(retPct(bars[i], 21)), '3_thang': _r(retPct(bars[i], 63)), '12_thang': _r(retPct(bars[i], 252))},
        },
    ];
    double? median(String k) {
      final v = [for (final r in rows.skip(1)) if (r[k] is num) (r[k] as num).toDouble()]..sort();
      if (v.isEmpty) return null;
      return v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
    }

    int? rank(String k, {bool higherBetter = true}) {
      final own = rows.first[k];
      if (own is! num) return null;
      final vals = [for (final r in rows) if (r[k] is num) (r[k] as num).toDouble()];
      return vals.where((v) => higherBetter ? v > own : v < own).length + 1;
    }

    return {
      'nganh': dash.sectors[symbol]?.name,
      'co_phieu_dang_xet': rows.first,
      'doanh_nghiep_cung_nganh': rows.skip(1).toList(),
      'trung_vi_nhom_cung_nganh': {for (final k in ['pe', 'pb', 'roe', 'grossMargin', 'afterTaxProfitMargin', 'debtToEquity']) k: _r(median(k), 3)},
      'thu_hang_trong_nhom_${all.length}_ma': {
        'roe_cao_nhat_la_1': rank('roe'),
        'pe_thap_nhat_la_1': rank('pe', higherBetter: false),
        'pb_thap_nhat_la_1': rank('pb', higherBetter: false),
        'bien_loi_nhuan_rong_cao_nhat_la_1': rank('afterTaxProfitMargin'),
      },
    };
  }

  Future<Map<String, dynamic>> _flowData(String symbol, Map<String, dynamic> record) async {
    final row = _allRows.where((r) => r.symbol == symbol).firstOrNull;
    final daily = await fetchBars(symbol, days: 120);
    final vols = [for (final b in daily) b.v];
    double? avg(int n) => vols.length >= n ? vols.sublist(vols.length - n).reduce((a, b) => a + b) / n : null;
    double? ratio(int n) => avg(n) == null || avg(n) == 0 ? null : vols.last / avg(n)!;
    Map<String, dynamic>? sessions;
    try {
      final s = sessionsOf(await fetchBars(symbol, days: 6, resolution: '1'));
      if (s != null) {
        sessions = {
          'phien_gan_nhat': {'ngay': s.$2.day, 'khoi_luong_cong_don': s.$2.total},
          'phien_truoc': {'ngay': s.$1.day, 'khoi_luong_cong_don_ca_phien': s.$1.total},
        };
      }
    } catch (_) {}
    final fund = (record['inputs'] as Map?)?['fundamentals'] as Map?;
    final company = (fund?['company'] as Map?) ?? const {};
    return {
      if (row != null)
        'bang_gia_hom_nay': {
          'gia_dong': row.price,
          'khoi_luong_khop': row.volume,
          'khoi_luong_thoa_thuan': row.ptVolume,
          'gia_tri_khop_trieu_dong': row.valueMn,
          'khoi_ngoai_mua_kl': row.foreignBuy,
          'khoi_ngoai_ban_kl': row.foreignSell,
          'khoi_ngoai_mua_ban_rong_ty_dong': _r((row.foreignBuy - row.foreignSell) * row.price / 1e9, 2),
        },
      'khoi_luong_phien_cuoi_so_voi_tb_20_phien': _r(ratio(20)),
      'khoi_luong_phien_cuoi_so_voi_tb_60_phien': _r(ratio(60)),
      'khoi_luong_tb_20_phien': _r(avg(20), 0),
      'thanh_khoan_trong_phien': sessions,
      'so_huu_nuoc_ngoai': company['so_huu_nuoc_ngoai'],
      'room_nuoc_ngoai_toi_da': company['room_nuoc_ngoai_toi_da'],
      'gia_tri_khop_tb_1_thang_ty_dong': company['gia_tri_khop_tb_1_thang_ty_dong'],
    };
  }

  Future<Map<String, dynamic>> _riskData(String symbol) async {
    final bars = await fetchBars(symbol, days: 1900);
    final index = await fetchBars('VNINDEX', days: 1900, isIndex: true);
    final q = quantStats(bars, index);
    final beta = (q?['beta'] as num?)?.toDouble();
    final rs = simpleReturns([for (final b in bars) b.c]);
    double? worst(int n) {
      if (bars.length <= n) return null;
      var w = 0.0;
      for (var i = n; i < bars.length; i++) {
        final r = bars[i].c / bars[i - n].c - 1;
        if (r < w) w = r;
      }
      return w * 100;
    }

    return {
      'chi_so_dinh_luong_1_nam': q,
      'cu_soc_gia_dinh_theo_beta': [
        for (final shock in [-10, -20])
          {'vnindex_pct': shock, 'co_phieu_uoc_tinh_pct': beta == null ? null : _r(beta * shock, 1)},
      ],
      'te_nhat_lich_su_pct': {'1_ngay': _r(rs.isEmpty ? null : rs.reduce((a, b) => a < b ? a : b) * 100), '20_phien': _r(worst(20)), '60_phien': _r(worst(60))},
      'luu_y': 'Cú sốc giả định chỉ dùng beta tuyến tính; thực tế cổ phiếu có thể giảm sâu hơn khi thanh khoản cạn.',
    };
  }

  Future<Map<String, dynamic>> _newsData(String symbol, Map<String, dynamic> record) async {
    List<NewsItem> items;
    try {
      items = await fetchNews({symbol}, maxAge: const Duration(days: 14));
    } catch (_) {
      items = const [];
    }
    final result = (record['result'] as Map?) ?? const {};
    return {
      'tin_tuc_14_ngay': newsFor(items, symbol, limit: 25).map((n) => n.toPromptJson()).toList(),
      'su_kien_o_bao_cao_thu_nhat': result['catalysts'],
    };
  }

  /// Lập phân tích bổ sung [kind] cho nhận định ngày [dayKey] của [symbol] và lưu vào bản ghi.
  Future<Map<String, dynamic>> runExtra(String symbol, String dayKey, Map<String, dynamic> record, String kind) async {
    final k = extraKind(kind);
    final data = switch (kind) {
      'sector' => await _sectorData(symbol),
      'peers' => await _peersData(symbol),
      'flow' => await _flowData(symbol, record),
      'macro' => {'vi_mo': await macroDigest(macroCacheFile), 'nganh': dash.sectors[symbol]?.name},
      'news' => await _newsData(symbol, record),
      'risk' => await _riskData(symbol),
      _ => throw AiException('Chủ đề không hợp lệ: $kind'),
    };
    final result = (record['result'] as Map?) ?? const {};
    final first = {
      for (final key in ['stance', 'confidence', 'headline', 'summary', 'valuation', 'earnings', 'thesis', 'risks']) key: result[key],
    };
    final out = await generateJson(
      await resolveAiConfig(),
      system: extraSystem(k),
      prompt: extraPrompt(symbol, k, first, data),
      schema: extraSchema,
      schemaName: 'extra_$kind',
    );
    final extra = {'created_at': DateTime.now().toIso8601String(), 'ai': aiLabel, 'result': out};
    await saveExtra(symbol, dayKey, kind, extra);
    return extra;
  }
}
