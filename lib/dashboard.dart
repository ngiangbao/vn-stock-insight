// Dữ liệu cho dashboard "Tổng quan": chỉ số, bảng giá toàn sàn, phân ngành, biểu đồ trong phiên.
// Tự làm mới mỗi 45 giây trong giờ giao dịch (9:00–15:00 giờ VN, thứ 2–6).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'services/board.dart';
import 'services/market.dart';

class IndexMeta {
  final String symbol, name, desc, kind;
  final String? group; // nhóm bảng giá dùng để tính KL/giá trị/khối ngoại; null nếu không có
  const IndexMeta(this.symbol, this.name, this.desc, this.kind, this.group);
}

const indexMetas = [
  IndexMeta('VNINDEX', 'VNINDEX', 'Chỉ số VN-Index (HOSE)', 'index', 'HOSE'),
  IndexMeta('HNX', 'HNXINDEX', 'Chỉ số HNX-Index', 'index', 'HNX'),
  IndexMeta('UPCOM', 'UPINDEX', 'Chỉ số UPCOM-Index', 'index', 'UPCOM'),
  IndexMeta('VN30', 'VN30', 'Chỉ số VN30', 'index', 'VN30'),
  IndexMeta('VN30F1M', 'VN30F1M', 'Hợp đồng tương lai VN30 tháng gần', 'derivative', null),
];

/// Sàn của bản đồ nhiệt: tên hiển thị → nhóm bảng giá.
const heatExchanges = [('HSX', 'HOSE'), ('HNX', 'HNX'), ('UPCOM', 'UPCOM')];

class IndexQuote {
  final IndexMeta meta;
  final List<Bar> bars;
  const IndexQuote(this.meta, this.bars);

  double? get last => bars.isEmpty ? null : bars.last.c;
  double? get prev => bars.length < 2 ? null : bars[bars.length - 2].c;
  double? get change => last == null || prev == null ? null : last! - prev!;
  double? get pct => change == null || prev == 0 ? null : change! / prev! * 100;
  List<double> get spark => [for (final b in bars.skip(bars.length > 30 ? bars.length - 30 : 0)) b.c];
}

/// Giờ giao dịch: 9:00–15:00 giờ Việt Nam, thứ 2–6.
bool isTradingTime(DateTime now) {
  final vn = now.toUtc().add(const Duration(hours: 7));
  if (vn.weekday > DateTime.friday) return false;
  final m = vn.hour * 60 + vn.minute;
  return m >= 9 * 60 && m <= 15 * 60 + 5;
}

class MarketDashboard extends ChangeNotifier {
  final File sectorFile;
  MarketDashboard(this.sectorFile);

  static const autoRefresh = Duration(seconds: 45);

  Map<String, IndexQuote> quotes = {};
  String selected = 'VNINDEX';
  String exchange = 'HOSE'; // sàn của bản đồ nhiệt
  Map<String, List<BoardRow>> boards = {};
  Map<String, SectorInfo> sectors = {};
  List<Bar> intraday = const [];
  bool loading = false;
  String? error;
  DateTime? updatedAt;

  Timer? _timer;
  bool _disposed = false;

  IndexMeta get meta => indexMetas.firstWhere((m) => m.symbol == selected);
  IndexQuote? get quote => quotes[selected];
  List<BoardRow> get heatRows => boards[exchange] ?? const [];
  List<BoardRow>? get metaBoard => meta.group == null ? null : boards[meta.group];

  void start() {
    _timer ??= Timer.periodic(autoRefresh, (_) {
      if (isTradingTime(DateTime.now())) refresh();
    });
    refresh();
  }

  void select(String symbol) {
    if (selected == symbol) return;
    selected = symbol;
    intraday = const [];
    notifyListeners();
    refresh();
  }

  void setExchange(String group) {
    if (exchange == group) return;
    exchange = group;
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final needed = {exchange, if (meta.group != null) meta.group!};
      final results = await Future.wait([
        for (final m in indexMetas) fetchBars(m.symbol, days: 1900, kind: m.kind),
        fetchIntraday(selected, kind: meta.kind),
        for (final g in needed) fetchBoard(g).then<List<BoardRow>?>((r) => r, onError: (_) => null),
        if (sectors.isEmpty) loadSectors(sectorFile) else Future.value(sectors),
      ]);
      final n = indexMetas.length;
      final next = <String, IndexQuote>{};
      for (final (i, m) in indexMetas.indexed) {
        final bars = results[i] as List<Bar>;
        final old = quotes[m.symbol];
        // Giữ nguyên danh sách khi không đổi để biểu đồ không bị đặt lại vị trí xem
        next[m.symbol] = bars.isEmpty
            ? (old ?? IndexQuote(m, bars))
            : (old != null && _sameTail(old.bars, bars) ? old : IndexQuote(m, bars));
      }
      quotes = next;
      intraday = results[n] as List<Bar>;
      final groups = needed.toList();
      var failed = 0;
      for (final (i, g) in groups.indexed) {
        final rows = results[n + 1 + i] as List<BoardRow>?;
        if (rows == null || rows.isEmpty) {
          failed++;
        } else {
          boards = {...boards, g: rows};
        }
      }
      sectors = results.last as Map<String, SectorInfo>;
      error = failed == groups.length ? 'Không lấy được bảng giá. Kiểm tra kết nối mạng.' : null;
      updatedAt = DateTime.now();
    } catch (e) {
      error = 'Lỗi tải dữ liệu thị trường: $e';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  static bool _sameTail(List<Bar> a, List<Bar> b) =>
      a.length == b.length && a.isNotEmpty && a.last.t == b.last.t && a.last.c == b.last.c && a.last.v == b.last.v;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
