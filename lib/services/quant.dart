// Chỉ số định lượng cho phân tích CFA, tính cục bộ từ giá lịch sử và số liệu cơ bản (không nhờ AI tính số).
//
// Các công thức theo giáo trình CFA: thống kê lợi suất và rủi ro (Quantitative Methods), CAPM và hồi quy theo VN-Index,
// VaR/CVaR lịch sử, phân tách DuPont và định giá P/B chính đáng theo mô hình thu nhập thặng dư (Equity Valuation).
// Các giả định thị trường (lãi suất phi rủi ro, phần bù rủi ro vốn, tăng trưởng dài hạn) là giả định người dùng chỉnh được.

import 'dart:math' as math;

import 'market.dart';

/// Giả định thị trường; mặc định là mức tham khảo cho Việt Nam, người dùng có thể đổi.
class CfaAssumptions {
  /// Lãi suất phi rủi ro (năm), ví dụ lãi suất trái phiếu chính phủ kỳ hạn dài.
  final double rf;

  /// Phần bù rủi ro vốn cổ phần (năm).
  final double erp;

  /// Tăng trưởng dài hạn của lợi nhuận (danh nghĩa, năm).
  final double g;
  const CfaAssumptions({this.rf = 0.045, this.erp = 0.07, this.g = 0.04});

  Map<String, dynamic> toJson() => {'rf': rf, 'erp': erp, 'g': g};

  factory CfaAssumptions.fromJson(Map? m) => m == null
      ? const CfaAssumptions()
      : CfaAssumptions(
          rf: (m['rf'] as num?)?.toDouble() ?? 0.045,
          erp: (m['erp'] as num?)?.toDouble() ?? 0.07,
          g: (m['g'] as num?)?.toDouble() ?? 0.04,
        );
}

const tradingDays = 252;

double _mean(List<double> x) => x.isEmpty ? 0 : x.reduce((a, b) => a + b) / x.length;

double _std(List<double> x) {
  if (x.length < 2) return 0;
  final m = _mean(x);
  return math.sqrt(x.fold<double>(0, (s, v) => s + (v - m) * (v - m)) / (x.length - 1));
}

double _cov(List<double> a, List<double> b) {
  final ma = _mean(a), mb = _mean(b);
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - ma) * (b[i] - mb);
  }
  return a.length < 2 ? 0 : s / (a.length - 1);
}

double? _r(double? v, [int d = 4]) {
  if (v == null || !v.isFinite) return null;
  final p = math.pow(10, d);
  return (v * p).round() / p;
}

/// Lợi suất đơn giản theo ngày.
List<double> simpleReturns(List<double> closes) => [
  for (var i = 1; i < closes.length; i++)
    if (closes[i - 1] != 0) closes[i] / closes[i - 1] - 1,
];

/// Phân vị [q] (0..1) của dữ liệu, nội suy tuyến tính.
double percentile(List<double> x, double q) {
  final s = [...x]..sort();
  if (s.isEmpty) return 0;
  final pos = (s.length - 1) * q;
  final lo = pos.floor(), hi = pos.ceil();
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

/// Giá đóng cửa chung của cổ phiếu và chỉ số theo ngày giao dịch, [days] phiên gần nhất.
({List<String> dates, List<double> stock, List<double> index}) alignCloses(List<Bar> stock, List<Bar> index, {int days = tradingDays + 1}) {
  final idx = {for (final b in index) vnDate(b.t): b.c};
  final dates = <String>[], s = <double>[], m = <double>[];
  for (final b in stock) {
    final d = vnDate(b.t);
    final i = idx[d];
    if (i != null) {
      dates.add(d);
      s.add(b.c);
      m.add(i);
    }
  }
  final from = math.max(0, dates.length - days);
  return (dates: dates.sublist(from), stock: s.sublist(from), index: m.sublist(from));
}

/// Chỉ số định lượng của cổ phiếu so với VN-Index trong khoảng 1 năm giao dịch gần nhất. Null nếu thiếu dữ liệu chung (< 60 phiên).
Map<String, dynamic>? quantStats(List<Bar> stock, List<Bar> index, {double rf = 0.045}) {
  final a = alignCloses(stock, index);
  if (a.stock.length < 61) return null;
  final rs = simpleReturns(a.stock), rm = simpleReturns(a.index);
  final n = math.min(rs.length, rm.length);
  final r = rs.sublist(rs.length - n), m = rm.sublist(rm.length - n);
  final years = n / tradingDays;

  double cagr(List<double> c) => math.pow(c.last / c.first, 1 / years).toDouble() - 1;
  final retS = cagr(a.stock), retM = cagr(a.index);
  final vol = _std(r) * math.sqrt(tradingDays);
  final volM = _std(m) * math.sqrt(tradingDays);

  // Độ lệch xuống (Sortino) so với lãi suất phi rủi ro theo ngày
  final dailyRf = rf / tradingDays;
  final downside = math.sqrt(r.fold<double>(0, (s, v) => s + math.pow(math.min(0, v - dailyRf), 2)) / r.length) * math.sqrt(tradingDays);

  // Sụt giảm tối đa và thời gian dưới đỉnh dài nhất
  var peak = a.stock.first, maxDd = 0.0, under = 0, longest = 0;
  for (final p in a.stock) {
    if (p >= peak) {
      peak = p;
      under = 0;
    } else {
      under++;
      longest = math.max(longest, under);
      maxDd = math.min(maxDd, p / peak - 1);
    }
  }
  final currentDd = a.stock.last / a.stock.reduce(math.max) - 1;

  final var95 = -percentile(r, 0.05);
  final tail = r.where((v) => v <= -var95).toList();
  final cvar95 = tail.isEmpty ? var95 : -_mean(tail);

  final mean = _mean(r), sd = _std(r);
  final skew = sd == 0 ? 0.0 : r.fold<double>(0, (s, v) => s + math.pow((v - mean) / sd, 3)) / r.length;
  final kurt = sd == 0 ? 0.0 : r.fold<double>(0, (s, v) => s + math.pow((v - mean) / sd, 4)) / r.length - 3;

  final varM = _cov(m, m);
  final beta = varM == 0 ? null : _cov(r, m) / varM;
  final corr = (_std(r) == 0 || _std(m) == 0) ? null : _cov(r, m) / (_std(r) * _std(m));
  final alpha = beta == null ? null : (retS - rf) - beta * (retM - rf);
  final active = [for (var i = 0; i < n; i++) r[i] - m[i]];
  final te = _std(active) * math.sqrt(tradingDays);

  double? capture(bool up) {
    final idx = [
      for (var i = 0; i < n; i++)
        if (up ? m[i] > 0 : m[i] < 0) i,
    ];
    if (idx.length < 5) return null;
    final mm = _mean([for (final i in idx) m[i]]);
    return mm == 0 ? null : _mean([for (final i in idx) r[i]]) / mm;
  }

  // Động lượng 12-1: lợi suất từ 12 tháng trước đến 1 tháng trước (bỏ tháng gần nhất)
  double? mom;
  if (a.stock.length > 253) {
    mom = a.stock[a.stock.length - 22] / a.stock[a.stock.length - 253] - 1;
  }

  return {
    'so_phien': n,
    'den_ngay': a.dates.last,
    'loi_suat_nam': _r(retS),
    'loi_suat_vnindex_nam': _r(retM),
    'bien_dong_nam': _r(vol),
    'bien_dong_vnindex_nam': _r(volM),
    'sharpe': vol == 0 ? null : _r((retS - rf) / vol, 2),
    'sortino': downside == 0 ? null : _r((retS - rf) / downside, 2),
    'sut_giam_toi_da': _r(maxDd),
    'sut_giam_hien_tai': _r(currentDd),
    'so_phien_duoi_dinh_dai_nhat': longest,
    'var95_1_ngay': _r(var95),
    'cvar95_1_ngay': _r(cvar95),
    'do_lech_skew': _r(skew, 2),
    'kurtosis_vuot_chuan': _r(kurt, 2),
    'beta': _r(beta, 2),
    'alpha_jensen_nam': _r(alpha),
    'tuong_quan_vnindex': _r(corr, 2),
    'r_binh_phuong': corr == null ? null : _r(corr * corr, 2),
    'tracking_error': _r(te),
    'information_ratio': te == 0 ? null : _r((retS - retM) / te, 2),
    'treynor': beta == null || beta == 0 ? null : _r((retS - rf) / beta),
    'capture_tang': _r(capture(true), 2),
    'capture_giam': _r(capture(false), 2),
    'dong_luong_12_1': _r(mom),
    'rf_gia_dinh': rf,
  };
}

/// Chuỗi lợi suất tích lũy (so với ngày đầu, %) của cổ phiếu và VN-Index, dùng vẽ biểu đồ so sánh.
({List<String> dates, List<double> stock, List<double> index}) relativeSeries(
  List<Bar> stock,
  List<Bar> index, {
  int days = tradingDays + 1,
}) {
  final a = alignCloses(stock, index, days: days);
  if (a.stock.isEmpty) return a;
  return (
    dates: a.dates,
    stock: [for (final v in a.stock) (v / a.stock.first - 1) * 100],
    index: [for (final v in a.index) (v / a.index.first - 1) * 100],
  );
}

double? _frac(dynamic v) {
  if (v is! num) return null;
  final x = v.toDouble();
  return x.abs() > 1.5 ? x / 100 : x;
}

/// Định giá theo khung CFA: chi phí vốn CAPM, DuPont và P/B chính đáng (thu nhập thặng dư).
/// [fund] là kết quả của fetchFundamentals; [price] tính theo nghìn đồng; [beta] từ [quantStats].
Map<String, dynamic> cfaValuation(Map<String, dynamic>? fund, double? price, double? beta, CfaAssumptions a) {
  final notes = <String>[];
  final quarters = ((fund?['chi_so_ttm_theo_quy'] as List?) ?? const []).cast<Map>();
  final last = quarters.isEmpty ? null : quarters.last;
  final isBank = ((fund?['company'] as Map?)?['la_ngan_hang']) == true;
  final roe = _frac(last?['roe']);
  final pb = (last?['pb'] as num?)?.toDouble();
  final pe = (last?['pe'] as num?)?.toDouble();

  final b = beta ?? 1.0;
  if (beta == null) notes.add('Không tính được beta, tạm dùng beta = 1,0.');
  final ke = a.rf + b * a.erp;

  double? justPb(double ke_, double g_) => roe == null || ke_ <= g_ ? null : (roe - g_) / (ke_ - g_);

  final jpb = justPb(ke, a.g);
  if (roe == null) notes.add('Thiếu ROE nên không tính được P/B chính đáng.');
  if (pb == null) notes.add('Thiếu P/B hiện tại.');
  if (ke <= a.g) notes.add('Chi phí vốn không lớn hơn tăng trưởng dài hạn nên mô hình không áp dụng được.');
  final bvps = (price != null && pb != null && pb > 0) ? price / pb : null;
  final intrinsic = (bvps != null && jpb != null) ? bvps * jpb : null;

  final grid = <Map<String, dynamic>>[];
  for (final dk in [-0.01, 0.0, 0.01]) {
    for (final dg in [-0.01, 0.0, 0.01]) {
      final k = ke + dk, g = a.g + dg;
      final j = justPb(k, g);
      grid.add({
        'chi_phi_von': _r(k),
        'tang_truong': _r(g),
        'pb_chinh_dang': _r(j, 2),
        'gia_nghin_dong': (bvps != null && j != null) ? _r(bvps * j, 1) : null,
      });
    }
  }

  Map<String, dynamic>? dupont;
  if (!isBank && last != null) {
    final margin = _frac(last['afterTaxProfitMargin']);
    final de = (last['debtToEquity'] as num?)?.toDouble();
    if (roe != null && margin != null && margin != 0 && de != null) {
      final multiplier = 1 + de;
      dupont = {
        'roe': _r(roe),
        'bien_loi_nhuan_rong': _r(margin),
        'vong_quay_tai_san_suy_ra': _r(roe / (margin * multiplier), 2),
        'don_bay_tai_chinh_xap_xi': _r(multiplier, 2),
        'ghi_chu': 'Vòng quay tài sản suy ra từ ROE / (biên LN ròng × đòn bẩy); đòn bẩy xấp xỉ 1 + Nợ/Vốn chủ.',
      };
    }
  }

  return {
    'gia_dinh': a.toJson(),
    'chi_phi_von_chu_so_huu_capm': _r(ke),
    'beta_su_dung': _r(b, 2),
    'roe_ttm': _r(roe),
    'pb_hien_tai': _r(pb, 2),
    'pe_hien_tai': _r(pe, 1),
    'bvps_uoc_tinh_nghin_dong': _r(bvps, 1),
    'pb_chinh_dang': _r(jpb, 2),
    'pe_chinh_dang': (jpb != null && roe != null && roe != 0) ? _r(jpb / roe, 1) : null,
    'gia_noi_tai_uoc_tinh_nghin_dong': _r(intrinsic, 1),
    'chenh_lech_so_voi_gia_pct': (intrinsic != null && price != null && price > 0) ? _r((intrinsic / price - 1) * 100, 1) : null,
    'bang_do_nhay': grid,
    'dupont': dupont,
    'ghi_chu': notes,
  };
}
