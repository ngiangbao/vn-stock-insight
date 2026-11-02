// Trang chi tiết cổ phiếu hoặc chỉ số (mở khi bấm vào một mã hay một chỉ số): nhận định xu hướng, biểu đồ nhiều khung
// (1 giờ, 4 giờ, ngày, tuần) có đường hỗ trợ/kháng cự và Fibonacci, điểm sức khỏe, dấu hiệu tạo đáy, vùng giá và kịch bản,
// dòng tiền phiên, rồi các chỉ số cơ bản. Mọi nhận định kỹ thuật tính trên máy theo quy tắc cố định (xem services/insight.dart).

import 'dart:async';

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/board.dart';
import '../services/fundamentals.dart';
import '../services/indicators.dart';
import '../services/insight.dart';
import '../services/market.dart';
import '../state.dart';
import 'analysis_page.dart';
import 'chart.dart';
import 'liquidity_chart.dart';
import 'stock_dialog.dart' show IndexSidebar, StockSidebar;
import 'widgets.dart';

/// Mở trang chi tiết cổ phiếu.
Future<void> openStockDetail(BuildContext context, String symbol) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockDetailPage(symbol: symbol)));

/// Mở trang chi tiết chỉ số (VN-Index, HNX, UPCOM, VN30, phái sinh, chỉ số thế giới).
Future<void> openIndexDetail(BuildContext context, IndexMeta meta) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => StockDetailPage(symbol: meta.symbol, meta: meta),
  ),
);

enum _Frame {
  hour('1 giờ'),
  hour4('4 giờ'),
  day('Ngày'),
  week('Tuần');

  final String label;
  const _Frame(this.label);
}

const _dayRanges = [('1T', 22), ('3T', 66), ('6T', 130), ('1N', 250), ('5N', 1250), ('Tất cả', 0)];
const _weekRanges = [('6T', 26), ('1N', 52), ('3N', 156), ('Tất cả', 0)];
const _hourRanges = [('1T', 150), ('Tất cả', 0)];

class StockDetailPage extends StatefulWidget {
  final String symbol;

  /// Có giá trị khi là chỉ số/phái sinh/chỉ số thế giới.
  final IndexMeta? meta;
  const StockDetailPage({super.key, required this.symbol, this.meta});

  @override
  State<StockDetailPage> createState() => _StockDetailPageState();
}

class _StockDetailPageState extends State<StockDetailPage> {
  List<Bar>? _daily;
  List<Bar> _market = const [];
  List<Bar>? _intraday; // nến 15 phút, dùng gộp thành 1 giờ và 4 giờ
  Map<String, dynamic>? _fund;
  BoardRow? _row;
  bool _failed = false;
  _Frame _frame = _Frame.day;
  bool _zones = true, _fib = false; // ignore: prefer_final_fields
  final Set<Indicator> _ind = {Indicator.ma50, Indicator.ema20, Indicator.ma200, Indicator.volume, Indicator.rsi, Indicator.macd};
  Timer? _live;

  bool get _isStock => widget.meta == null;

  // Kết quả tính toán, chỉ tính lại khi dữ liệu ngày đổi
  HealthScore? _health;
  List<BottomSignal> _bottom = const [];
  PriceZones? _pz;
  Scenarios? _sc;
  TrendSummary? _trend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _live = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isTradingTime(DateTime.now())) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  void _recompute() {
    final d = _daily;
    if (d == null || d.length < 2) return;
    _health = healthScore(d, _market);
    _bottom = bottomSignals(d, _market);
    _pz = priceZones(d);
    _sc = _pz == null ? null : scenarios(d, _pz!);
    _trend = trendSummary(widget.symbol, d, _health, _pz, _sc);
  }

  Future<void> _load({bool quiet = false}) async {
    final state = AppScope.of(context);
    final known = _isStock ? state.stocks[widget.symbol]?.bars : state.dash.quotes[widget.symbol]?.bars;
    if (!quiet && known != null && known.length >= 2) {
      setState(() {
        _daily = known;
        _market = state.index?.bars ?? const [];
        _recompute();
      });
    }
    for (final rows in state.dash.boards.values) {
      final hit = rows.where((r) => r.symbol == widget.symbol);
      if (hit.isNotEmpty) _row = hit.first;
    }
    final m = widget.meta;
    final results = await Future.wait<List<Bar>>([
      fetchBars(widget.symbol, days: 1900, kind: m?.kind),
      if (_market.isEmpty && widget.symbol != 'VNINDEX') fetchBars('VNINDEX', days: 1900, isIndex: true) else Future.value(_market),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0].length >= 2) {
        _daily = results[0];
        _market = widget.symbol == 'VNINDEX' ? results[0] : results[1];
        _recompute();
      } else if (_daily == null) {
        _failed = true;
      }
    });
    if (_isStock && !quiet) {
      fetchFundamentals(widget.symbol).then((f) => mounted ? setState(() => _fund = f) : null).catchError((_) {});
      if (_row == null) {
        for (final group in ['HOSE', 'HNX', 'UPCOM']) {
          try {
            final hit = (await fetchBoard(group)).where((r) => r.symbol == widget.symbol);
            if (hit.isNotEmpty) {
              if (mounted) setState(() => _row = hit.first);
              break;
            }
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _loadIntraday() async {
    if (_intraday != null) return;
    final b = await fetchBars(widget.symbol, days: 20, kind: widget.meta?.kind, resolution: '15');
    if (mounted) setState(() => _intraday = b);
  }

  List<Bar>? get _frameBars {
    final d = _daily;
    if (d == null) return null;
    return switch (_frame) {
      _Frame.day => d,
      _Frame.week => weeklyBars(d),
      _Frame.hour => _intraday == null ? null : hourlyBars(_intraday!, 1),
      _Frame.hour4 => _intraday == null ? null : hourlyBars(_intraday!, 4),
    };
  }

  /// Các đường mức giá đang bật (chỉ có nghĩa với khung ngày, vì tính từ nến ngày).
  List<ChartLevel> _levels(BuildContext context) {
    final z = _pz;
    if (z == null || _frame != _Frame.day) return const [];
    final up = Tone.up(context), down = Tone.down(context), gold = Tone.flat(context);
    return [
      if (_zones) ...[
        for (final r in z.resistances.take(2))
          ChartLevel(r.low, 'Kháng cự ${_range(r.low, r.high)}', down, priceTo: r.high - r.low < 0.05 ? null : r.high),
        for (final s in z.supports.take(2))
          ChartLevel(s.high, 'Hỗ trợ ${_range(s.low, s.high)}', up, priceTo: s.high - s.low < 0.05 ? null : s.low),
      ],
      if (_fib)
        for (final f in z.fib) ChartLevel(f.price, '${f.label} ${fmt(f.price, 2)}', gold, dashed: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = _daily;
    final m = widget.meta;
    final company = (_fund?['company'] as Map?) ?? const {};
    final last = d != null && d.length >= 2 ? d.last : null;
    final prev = d != null && d.length >= 2 ? d[d.length - 2] : null;
    final diff = last == null || prev == null ? null : last.c - prev.c;
    final pct = diff == null || prev!.c == 0 ? null : diff / prev.c * 100;
    final mult = _isStock ? 1000.0 : 1.0;
    final watching = state.watchlist.contains(widget.symbol);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(m?.name ?? widget.symbol, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              if (last != null)
                Text(
                  fmt(last.c * mult, _isStock ? 0 : 2),
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Tone.of(context, diff),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (diff != null && pct != null)
                Text(
                  '${diff > 0 ? '▲' : (diff < 0 ? '▼' : '■')} ${diff > 0 ? '+' : ''}${fmt(diff * mult, _isStock ? 0 : 2)} (${pct > 0 ? '+' : ''}${fmt(pct, 2)}%)',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Tone.of(context, diff),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if ((company['ten'] ?? m?.desc) != null)
            Text('${company['ten'] ?? m!.desc}', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          if (company['nganh'] != null) Tag('${company['nganh']}'),
          if (last != null) StatusChip('Phiên ${vnDate(last.t).split('-').reversed.join('/')}'),
        ],
      ),
    );

    final summary = _trend == null ? null : _SummaryCard(_trend!, _bottom);
    final chart = _ChartCard(
      symbol: widget.symbol,
      frame: _frame,
      onFrame: (f) {
        setState(() => _frame = f);
        if (f == _Frame.hour || f == _Frame.hour4) _loadIntraday();
      },
      bars: _frameBars,
      failed: _failed,
      indicators: _ind,
      onToggle: (i) => setState(() => _ind.contains(i) ? _ind.remove(i) : _ind.add(i)),
      zones: _zones,
      fib: _fib,
      onZones: (v) => setState(() => _zones = v),
      onFib: (v) => setState(() => _fib = v),
      levels: _levels(context),
      daily: d,
      isStock: _isStock,
    );
    final flow = _FlowCard(symbol: widget.symbol, row: _row, meta: m, isStock: _isStock);
    final health = _health == null ? null : _HealthCard(_health!);
    final bottom = _BottomCard(_bottom);
    final zones = _pz == null ? null : _ZonesCard(_pz!, _sc!, mult);
    final side = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _isStock
            ? StockSidebar(widget.symbol, d == null || d.length < 2 ? null : analyze(widget.symbol, d), _fund, _row)
            : IndexSidebar(d),
      ),
    );

    List<Widget> gap(List<Widget?> xs) => [
      for (final x in xs.whereType<Widget>()) ...[x, const SizedBox(height: 16)],
    ];

    final left = gap([summary, chart, flow]);
    final right = gap([health, if (_isStock) bottom, zones, side]);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(_isStock ? 'Chi tiết cổ phiếu' : 'Chi tiết chỉ số'),
        actions: [
          if (_isStock) ...[
            IconButton(
              tooltip: watching ? 'Bỏ theo dõi' : 'Thêm vào danh sách theo dõi',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(watching ? Icons.star : Icons.star_border, color: watching ? Tone.flat(context) : null),
              onPressed: () => watching ? state.removeWatch(widget.symbol) : state.addWatch(widget.symbol),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => openAnalysis(context, widget.symbol),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Phân tích AI'),
              ),
            ),
          ],
        ],
      ),
      body: d == null
          ? Center(child: _failed ? Text('Không lấy được dữ liệu giá ${widget.symbol}.') : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                header,
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 400,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
                      ),
                    ],
                  )
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, ...right]),
              ],
            ),
    );
  }
}

/// Hai đầu của một vùng giá, hoặc một số duy nhất khi vùng chỉ có một mức.
String _range(double lo, double hi) => hi - lo < 0.05 ? fmt(lo, 2) : '${fmt(lo, 1)}–${fmt(hi, 1)}';

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _Section(this.title, this.child, {this.trailing});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final TrendSummary t;
  final List<BottomSignal> bottom;
  const _SummaryCard(this.t, this.bottom);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final met = bottom.where((b) => b.met == true).length;
    final tone = t.direction == 'Giảm' ? Tone.down(context) : (t.direction == 'Tăng' ? Tone.up(context) : Tone.flat(context));
    final healthTone = t.healthTag == 'Mạnh' ? Tone.up(context) : (t.healthTag == 'Yếu' ? Tone.down(context) : Tone.flat(context));
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(k, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.headline, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(t.detail, style: text.bodyMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            // Hướng có biểu tượng mũi tên để không chỉ dựa vào màu
            Tag(
              '${t.direction == 'Giảm' ? '↘ ' : (t.direction == 'Tăng' ? '↗ ' : '→ ')}${t.direction == 'Giảm' ? 'Đang giảm' : (t.direction == 'Tăng' ? 'Đang tăng' : 'Đi ngang')}',
              color: tone,
            ),
            Tag('● ${t.healthTag}', color: healthTone),
          ],
        ),
      ],
    );
    final right = Column(
      children: [
        if (t.week != null) kv('Khung tuần', t.week!.text),
        if (t.day != null) kv('Khung ngày', t.day!.text),
        kv('Dấu hiệu tạo đáy', '$met/6'),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 640
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: left),
                    const SizedBox(width: 20),
                    SizedBox(width: 240, child: right),
                  ],
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 10), right]),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String symbol;
  final _Frame frame;
  final ValueChanged<_Frame> onFrame;
  final List<Bar>? bars;
  final bool failed, zones, fib, isStock;
  final Set<Indicator> indicators;
  final ValueChanged<Indicator> onToggle;
  final ValueChanged<bool> onZones, onFib;
  final List<ChartLevel> levels;
  final List<Bar>? daily;
  const _ChartCard({
    required this.symbol,
    required this.frame,
    required this.onFrame,
    required this.bars,
    required this.failed,
    required this.indicators,
    required this.onToggle,
    required this.zones,
    required this.fib,
    required this.onZones,
    required this.onFib,
    required this.levels,
    required this.daily,
    required this.isStock,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final b = bars;
    final d = daily;
    String? stat;
    if (d != null && d.length > 40) {
      final closes = [for (final x in d) x.c];
      final rsi = rsiSeries(closes).last;
      final (macd, signal, _) = macdSeries(closes);
      if (rsi != null && macd.last != null && signal.last != null) {
        stat = 'RSI ${fmt(rsi, 1)} · MACD ${fmt(macd.last, 3)} / tín hiệu ${fmt(signal.last, 3)}';
      }
    }
    final ranges = switch (frame) {
      _Frame.week => _weekRanges,
      _Frame.day => _dayRanges,
      _ => _hourRanges,
    };
    Widget toggle(String label, Color? color, bool on, VoidCallback onTap) => FilterChip(
      avatar: color == null ? null : Container(width: 14, height: 3, color: color),
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_Frame>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact, minimumSize: WidgetStatePropertyAll(Size(48, 40))),
                  segments: [for (final f in _Frame.values) ButtonSegment(value: f, label: Text(f.label))],
                  selected: {frame},
                  onSelectionChanged: (s) => onFrame(s.first),
                ),
                if (stat != null)
                  Text(
                    stat,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                toggle('EMA20', Indicator.ema20.color, indicators.contains(Indicator.ema20), () => onToggle(Indicator.ema20)),
                toggle('MA50', Indicator.ma50.color, indicators.contains(Indicator.ma50), () => onToggle(Indicator.ma50)),
                toggle('MA200', Indicator.ma200.color, indicators.contains(Indicator.ma200), () => onToggle(Indicator.ma200)),
                toggle('Vùng giá', null, zones, () => onZones(!zones)),
                toggle('Fibonacci', null, fib, () => onFib(!fib)),
                toggle('Khối lượng', null, indicators.contains(Indicator.volume), () => onToggle(Indicator.volume)),
                toggle('RSI', null, indicators.contains(Indicator.rsi), () => onToggle(Indicator.rsi)),
                toggle('MACD', null, indicators.contains(Indicator.macd), () => onToggle(Indicator.macd)),
              ],
            ),
            const SizedBox(height: 8),
            if (b == null)
              SizedBox(
                height: 300,
                child: Center(child: failed ? const Text('Không lấy được dữ liệu.') : const CircularProgressIndicator()),
              )
            else if (b.length < 2)
              const SizedBox(height: 200, child: Center(child: Text('Chưa có đủ dữ liệu cho khung này.')))
            else
              StockChart(
                symbol,
                b,
                height: 600,
                fixedIndicators: indicators,
                rangeList: ranges,
                initialRange: frame == _Frame.week ? 1 : (frame == _Frame.day ? 3 : 0),
                levels: levels,
                key: ValueKey('$symbol-${frame.name}-${b.length}'),
              ),
            const SizedBox(height: 6),
            Text(
              'Kéo để di chuyển · cuộn chuột để phóng to · rê chuột hoặc nhấn giữ để xem từng phiên. Khung 1 giờ và 4 giờ gộp từ nến 15 phút (20 ngày gần nhất). '
              'Đường hỗ trợ/kháng cự và Fibonacci tính từ nến ngày, chỉ hiện ở khung Ngày. Nhận định kỹ thuật theo quy tắc cố định, không phải lời khuyên.',
              style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  final String symbol;
  final BoardRow? row;
  final IndexMeta? meta;
  final bool isStock;
  const _FlowCard({required this.symbol, required this.row, required this.meta, required this.isStock});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final state = AppScope.of(context);
    Widget kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Text(
            v,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
    final today = DateTime.now().toUtc().add(const Duration(hours: 7));
    final title = 'Dòng tiền phiên ${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}';

    // Cổ phiếu: khối ngoại từ bảng giá; chỉ số có nhóm bảng giá: tổng hợp độ rộng và khối ngoại của cả nhóm
    double buy = 0, sell = 0, valueMn = 0;
    int? up, down, flat;
    if (isStock && row != null) {
      buy = row!.foreignBuy * row!.price;
      sell = row!.foreignSell * row!.price;
      valueMn = row!.valueMn;
    } else if (meta?.group != null) {
      final rows = state.dash.boards[meta!.group!] ?? const <BoardRow>[];
      up = down = flat = 0;
      for (final r in rows) {
        if (r.ref <= 0 || r.price <= 0) continue;
        r.price > r.ref ? up = up! + 1 : (r.price < r.ref ? down = down! + 1 : flat = flat! + 1);
        buy += r.foreignBuy * r.price;
        sell += r.foreignSell * r.price;
        valueMn += r.valueMn;
      }
    }
    final net = buy - sell;
    final totalForeign = buy + sell;
    final has = (isStock && row != null) || up != null;
    return _Section(
      title,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isStock) ...[LiquidityChart(symbol), const SizedBox(height: 14)],
          if (!has)
            Text('Chưa có dữ liệu bảng giá cho nhóm này.', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          else ...[
            if (up != null) ...[kv('Mã tăng / đứng / giảm', '$up / $flat / $down')],
            kv('Giá trị khớp', '${fmt(valueMn / 1000, 1)} tỷ'),
            kv('Khối ngoại mua', '${fmt(buy / 1e9, 1)} tỷ'),
            kv('Khối ngoại bán', '${fmt(sell / 1e9, 1)} tỷ'),
            kv(
              'Khối ngoại ròng',
              '${net >= 0 ? '+' : '−'}${fmt(net.abs() / 1e9, 1)} tỷ ${net > 0 ? '(mua ròng)' : (net < 0 ? '(bán ròng)' : '')}',
              color: Tone.of(context, net),
            ),
            if (totalForeign > 0) ...[
              const SizedBox(height: 8),
              // Thanh mua/bán kèm số: không chỉ phân biệt bằng màu
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (buy / totalForeign * 1000).round().clamp(1, 999),
                        child: ColoredBox(color: Tone.up(context)),
                      ),
                      Expanded(
                        flex: (sell / totalForeign * 1000).round().clamp(1, 999),
                        child: ColoredBox(color: Tone.down(context)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Mua ${fmt(buy / totalForeign * 100, 0)}%', style: text.bodySmall),
                  const Spacer(),
                  Text('Bán ${fmt(sell / totalForeign * 100, 0)}%', style: text.bodySmall),
                ],
              ),
            ],
          ],
          const SizedBox(height: 8),
          Text(
            'Chưa có dữ liệu lệnh lớn (từ 1 tỷ) và mua/bán chủ động: nguồn dữ liệu miễn phí không cung cấp.',
            style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final HealthScore h;
  const _HealthCard(this.h);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tone = h.label == 'Mạnh' ? Tone.up(context) : (h.label == 'Yếu' ? Tone.down(context) : Tone.flat(context));
    final d = h.delta;
    return _Section(
      'Điểm sức khỏe',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${h.total}',
                      style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: '/100',
                      style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Tag('● ${h.label}', color: tone),
              if (h.previous != null)
                Text(
                  '${(h.backSessions / 5).round()} tuần trước ${h.previous} (${d! >= 0 ? '+' : '−'}${d.abs()})',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in h.parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Semantics(
                label: '${p.name}, trọng số ${p.weight}%, ${p.score} trên 100 điểm',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: p.name,
                                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(
                                    text: ' · ${p.weight}%',
                                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            '${p.score}',
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: p.score / 100,
                          minHeight: 6,
                          color: cs.primary,
                          backgroundColor: cs.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Điểm tổng hợp 4 nhóm theo quy tắc kỹ thuật cố định (xu hướng, động lượng, dòng tiền, sức mạnh so với VN-Index); chưa kiểm định lịch sử.',
            style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      trailing: const Tag('Chưa kiểm định'),
    );
  }
}

class _BottomCard extends StatelessWidget {
  final List<BottomSignal> signals;
  const _BottomCard(this.signals);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final met = signals.where((s) => s.met == true).length;
    return _Section(
      'Dấu hiệu tạo đáy · $met/6',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in signals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Có biểu tượng và chữ cho từng trạng thái, không chỉ dựa vào màu
                  Icon(
                    s.met == true ? Icons.check_circle : (s.met == false ? Icons.radio_button_unchecked : Icons.remove_circle_outline),
                    size: 18,
                    color: s.met == true ? Tone.up(context) : cs.onSurfaceVariant,
                    semanticLabel: s.met == true ? 'Có' : (s.met == false ? 'Chưa' : 'Chưa đủ dữ liệu'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.label, style: text.bodyMedium)),
                  if (s.met == null) Text('chưa đủ dữ liệu', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ZonesCard extends StatelessWidget {
  final PriceZones z;
  final Scenarios sc;
  final double mult;
  const _ZonesCard(this.z, this.sc, this.mult);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    String p(double v) => vnNum(v * mult, mult == 1 ? 2 : 0);
    String pr(PriceZone r) => r.high - r.low < 0.05 ? p(r.low) : '${p(r.low)}–${p(r.high)}';
    Widget row(String k, String v, {String? note, bool strong = false}) => Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      decoration: strong ? BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: text.bodyMedium?.copyWith(fontWeight: strong ? FontWeight.w700 : FontWeight.w400)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: v,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: strong ? cs.primary : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (note != null)
                    TextSpan(
                      text: ' · $note',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    final r1 = z.nearestResistance, r2 = z.resistances.length > 1 ? z.resistances[1] : null, s1 = z.nearestSupport;
    final dyn = z.dynamicResistance;
    return _Section(
      'Vùng giá và kịch bản',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r1 != null) row('Kháng cự', pr(r1), note: '${r1.touches} lần chạm'),
          if (dyn != null) row('${dyn.name}, kháng cự động', p(dyn.price)),
          if (r2 != null) row('Kháng cự xa hơn', pr(r2), note: '${r2.touches} lần chạm'),
          row('Giá đóng cửa', p(z.close), strong: true),
          if (s1 != null) row('Hỗ trợ gần', pr(s1), note: '${s1.touches} lần chạm'),
          if (z.recentLow != null) row('Đáy nhịp gần', p(z.recentLow!)),
          const SizedBox(height: 10),
          Text('Kịch bản theo dõi', style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _ScenarioBox(Icons.trending_up, 'Tích cực', sc.positive, Tone.up(context)),
          const SizedBox(height: 6),
          _ScenarioBox(Icons.trending_down, 'Tiêu cực', sc.negative, Tone.down(context)),
        ],
      ),
    );
  }
}

class _ScenarioBox extends StatelessWidget {
  final IconData icon;
  final String label, body;
  final Color color;
  const _ScenarioBox(this.icon, this.label, this.body, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
