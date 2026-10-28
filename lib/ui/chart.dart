// Biểu đồ giá tương tác: nến, thanh OHLC, đường, vùng, baseline, Heikin-Ashi; chỉ báo MA/EMA/Bollinger,
// khối lượng, RSI, MACD, Stochastic. Kéo để di chuyển, cuộn chuột/chụm 2 ngón để phóng to,
// rê chuột hoặc nhấn giữ để xem chi tiết từng phiên.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;

import '../services/indicators.dart';
import '../services/market.dart';
import '../state.dart';
import 'widgets.dart';

enum ChartType {
  candle('Nến'),
  hollow('Nến rỗng'),
  ohlc('Thanh OHLC'),
  line('Đường'),
  area('Vùng'),
  baseline('Baseline'),
  heikinAshi('Heikin-Ashi');

  final String label;
  const ChartType(this.label);
  bool get usesOhlc => this == candle || this == hollow || this == ohlc || this == heikinAshi;
}

enum Indicator {
  ma10('MA 10', Color(0xFF9575CD)),
  ma20('MA 20', Color(0xFF2962FF)),
  ma50('MA 50', Color(0xFFFF9800)),
  ma200('MA 200', Color(0xFFE91E63)),
  ema20('EMA 20', Color(0xFF00BCD4)),
  bollinger('Bollinger (20, 2)', Color(0xFF9C27B0)),
  volume('Khối lượng', Color(0xFF26A69A)),
  rsi('RSI 14', Color(0xFF7E57C2)),
  macd('MACD (12, 26, 9)', Color(0xFF2962FF)),
  stoch('Stochastic (14, 3)', Color(0xFF2962FF));

  final String label;
  final Color color;
  const Indicator(this.label, this.color);
  bool get pane => this == rsi || this == macd || this == stoch;
}

const _up = Color(0xFF26A69A), _down = Color(0xFFEF5350);

/// Khoảng thời gian gọn cho dashboard (số phiên): 1d ≈ 10 phiên gần nhất.
const dashboardRanges = [('1d', 10), ('1m', 22), ('3m', 66), ('6m', 130), ('1y', 250), ('3y', 750), ('5y', 1250)];

const ranges = [('1T', 22), ('3T', 66), ('6T', 130), ('1N', 250), ('5N', 1250), ('Tất cả', 0)];

/// Mở biểu đồ toàn màn hình, tải lịch sử dài (5 năm).
void openChart(BuildContext context, String symbol, {String? title, String? kind}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChartPage(symbol, title: title, kind: kind)));

class ChartPage extends StatefulWidget {
  final String symbol;
  final String? title;
  final String? kind; // 'index' | 'derivative' | null (cổ phiếu)
  const ChartPage(this.symbol, {super.key, this.title, this.kind});

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  List<Bar>? _bars;
  String? _error;

  @override
  void initState() {
    super.initState();
    fetchBars(widget.symbol, days: 1900, isIndex: widget.symbol == 'VNINDEX', kind: widget.kind).then((b) {
      if (!mounted) return;
      setState(() => b.length < 2 ? _error = 'Không lấy được dữ liệu giá ${widget.symbol}.' : _bars = b);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title ?? 'Biểu đồ ${widget.symbol}')),
        body: _error != null
            ? Center(child: Text(_error!))
            : _bars == null
                ? const Center(child: CircularProgressIndicator())
                : Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: StockChart(widget.symbol, _bars!, expand: true)),
      );
}

class StockChart extends StatefulWidget {
  final String symbol;
  final List<Bar> bars;
  final double height;
  final bool expand; // chiếm hết chiều cao còn lại (trang biểu đồ riêng)
  final VoidCallback? onFullscreen;

  /// Chế độ gọn (dashboard): chỉ báo cố định, khoảng thời gian riêng, không có menu dạng biểu đồ/chỉ báo.
  final Set<Indicator>? fixedIndicators;
  final List<(String, int)> rangeList;
  final int initialRange;
  const StockChart(this.symbol, this.bars,
      {super.key,
      this.height = 420,
      this.expand = false,
      this.onFullscreen,
      this.fixedIndicators,
      this.rangeList = ranges,
      this.initialRange = 2});

  @override
  State<StockChart> createState() => _StockChartState();
}

class _Series {
  final List<Bar> raw, shown;
  final Map<String, List<double?>> s;
  _Series(this.raw, this.shown, this.s);
}

class _StockChartState extends State<StockChart> {
  late _Series _data;
  double _end = 0, _count = 130; // phiên ngoài cùng bên phải (có thể lẻ) và số phiên hiển thị
  Offset? _cross;
  late int _range = widget.initialRange;
  double _startCount = 0;
  ChartType? _builtFor;

  @override
  void didUpdateWidget(StockChart old) {
    super.didUpdateWidget(old);
    if (old.bars != widget.bars) _builtFor = null;
  }

  void _compute(ChartType type) {
    final bars = widget.bars;
    final closes = bars.map((b) => b.c).toList();
    final (bbMid, bbUp, bbLo) = bollinger(closes);
    final (macd, signal, hist) = macdSeries(closes);
    final (k, d) = stochasticSeries(bars);
    _data = _Series(bars, type == ChartType.heikinAshi ? heikinAshi(bars) : bars, {
      'ma10': smaSeries(closes, 10),
      'ma20': smaSeries(closes, 20),
      'ma50': smaSeries(closes, 50),
      'ma200': smaSeries(closes, 200),
      'ema20': emaSeries(closes, 20),
      'bbMid': bbMid,
      'bbUp': bbUp,
      'bbLo': bbLo,
      'rsi': rsiSeries(closes),
      'macd': macd,
      'signal': signal,
      'hist': hist,
      'k': k,
      'd': d,
    });
    if (_builtFor == null) _setRange(_range, rebuild: false);
    _builtFor = type;
  }

  void _setRange(int i, {bool rebuild = true}) {
    final n = widget.bars.length;
    final rl = widget.rangeList;
    final count = rl[i].$2 == 0 ? n.toDouble() : math.min(rl[i].$2, n).toDouble();
    void apply() {
      _range = i;
      _count = math.max(count + 3, 10);
      _end = n - 1 + 3; // chừa khoảng trống bên phải như TradingView
    }

    rebuild ? setState(apply) : apply();
  }

  void _clampView() {
    final n = widget.bars.length;
    _count = _count.clamp(10, math.max(n + 20, 30)).toDouble();
    _end = _end.clamp(math.min(_count * 0.3, n - 1), n - 1 + _count * 0.5).toDouble();
  }

  void _zoom(double factor, double focusFraction) {
    setState(() {
      final focusIndex = _end - (1 - focusFraction) * _count;
      _count *= factor;
      _clampView();
      _end = focusIndex + (1 - focusFraction) * _count;
      _clampView();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final type = state.chartType;
    if (_builtFor != type) _compute(type);
    final active = widget.fixedIndicators ?? state.chartIndicators;
    final compact = widget.fixedIndicators != null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;

    final toolbar = Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final (i, r) in widget.rangeList.indexed)
        ChoiceChip(
          label: Text(r.$1),
          selected: _range == i,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => _setRange(i),
        ),
      if (!compact) const SizedBox(width: 4),
      if (!compact)
        PopupMenuButton<ChartType>(
        tooltip: 'Dạng biểu đồ',
        initialValue: type,
        onSelected: state.setChartType,
        itemBuilder: (_) => [for (final t in ChartType.values) PopupMenuItem(value: t, child: Text(t.label))],
        child: Chip(avatar: const Icon(Icons.candlestick_chart, size: 18), label: Text(type.label), visualDensity: VisualDensity.compact),
      ),
      if (!compact)
        PopupMenuButton<Indicator>(
        tooltip: 'Chỉ báo',
        onSelected: state.toggleIndicator,
        itemBuilder: (_) => [
          for (final ind in Indicator.values)
            CheckedPopupMenuItem(value: ind, checked: active.contains(ind), child: Text(ind.label)),
        ],
        child: Chip(
            avatar: const Icon(Icons.stacked_line_chart, size: 18),
            label: Text('Chỉ báo (${active.length})'),
            visualDensity: VisualDensity.compact),
      ),
      if (widget.onFullscreen != null)
        IconButton(onPressed: widget.onFullscreen, icon: const Icon(Icons.open_in_full, size: 20), tooltip: 'Phóng to biểu đồ'),
    ]);

    final chart = LayoutBuilder(builder: (context, c) {
      const axisW = 64.0;
      final plotW = c.maxWidth - axisW;
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            // Giữ sự kiện cuộn cho biểu đồ để trang chứa nó không cuộn theo
            GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
              final s = ev as PointerScrollEvent;
              _zoom(math.exp(s.scrollDelta.dy / 500), (s.localPosition.dx / plotW).clamp(0, 1));
            });
          }
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (e) => setState(() => _cross = e.localPosition),
          onExit: (_) => setState(() => _cross = null),
          child: GestureDetector(
            onDoubleTap: () => _setRange(_range),
            onLongPressStart: (d) => setState(() => _cross = d.localPosition),
            onLongPressMoveUpdate: (d) => setState(() => _cross = d.localPosition),
            onTapUp: (d) => setState(() => _cross = _cross == null ? d.localPosition : null),
            onScaleStart: (_) => _startCount = _count,
            onScaleUpdate: (d) {
              setState(() {
                if (d.pointerCount >= 2 && d.scale != 1) {
                  _count = _startCount / d.scale;
                } else {
                  _end -= d.focalPointDelta.dx / (plotW / _count);
                }
                _clampView();
                if (d.pointerCount == 1 && _cross != null && !_isMouse) _cross = null;
              });
            },
            child: CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _ChartPainter(
                symbol: widget.symbol,
                data: _data,
                type: type,
                indicators: active,
                end: _end,
                count: _count,
                cross: _cross,
                dark: dark,
                textStyle: text.bodySmall!,
              ),
            ),
          ),
        ),
      );
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min, children: [
      toolbar,
      const SizedBox(height: 6),
      if (widget.expand) Expanded(child: chart) else SizedBox(height: widget.height, child: chart),
      if (!compact)
        Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Kéo để di chuyển · cuộn chuột hoặc chụm 2 ngón để phóng to · rê chuột/nhấn giữ để xem chi tiết · nhấp đúp để đặt lại',
            style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    ]);
  }

  bool get _isMouse => RendererBinding.instance.mouseTracker.mouseIsConnected;
}

class _ChartPainter extends CustomPainter {
  final String symbol;
  final _Series data;
  final ChartType type;
  final Set<Indicator> indicators;
  final double end, count;
  final Offset? cross;
  final bool dark;
  final TextStyle textStyle;

  _ChartPainter({
    required this.symbol,
    required this.data,
    required this.type,
    required this.indicators,
    required this.end,
    required this.count,
    required this.cross,
    required this.dark,
    required this.textStyle,
  });

  static const axisW = 64.0, axisH = 22.0;

  Color get _grid => dark ? const Color(0xFF2A2E39) : const Color(0xFFF0F3FA);
  Color get _textColor => dark ? const Color(0xFFB2B5BE) : const Color(0xFF131722);
  Color get _crossColor => dark ? const Color(0xFF9598A1) : const Color(0xFF787B86);
  Color get _labelBg => dark ? const Color(0xFF363A45) : const Color(0xFF131722);

  @override
  void paint(Canvas canvas, Size size) {
    final bars = data.shown;
    final n = bars.length;
    if (n < 2) return;
    final plotW = size.width - axisW;
    final panes = [for (final i in Indicator.values) if (i.pane && indicators.contains(i)) i];
    final paneH = panes.isEmpty ? 0.0 : math.min(110.0, (size.height - axisH) * 0.2);
    final mainH = size.height - axisH - paneH * panes.length;
    final barW = plotW / count;
    double x(int i) => plotW - (end - i + 0.5) * barW;
    final from = math.max(0, (end - count).floor());
    final to = math.min(n - 1, end.ceil());
    if (from > to) return;

    // ---------- Thang giá ----------
    var lo = double.infinity, hi = -double.infinity;
    for (var i = from; i <= to; i++) {
      if (type.usesOhlc) {
        lo = math.min(lo, bars[i].l);
        hi = math.max(hi, bars[i].h);
      } else {
        lo = math.min(lo, bars[i].c);
        hi = math.max(hi, bars[i].c);
      }
      for (final key in _overlayKeys) {
        final v = data.s[key]![i];
        if (v != null) {
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
      }
    }
    final volOn = indicators.contains(Indicator.volume);
    final priceTop = 28.0 + (_overlayKeys.isEmpty ? 0 : 14.0); // chừa chỗ cho dòng chú thích
    final priceBottom = mainH - (volOn ? mainH * 0.18 : 8);
    final pad = (hi - lo) * 0.06 + 1e-9;
    lo -= pad;
    hi += pad;
    double y(double v) => priceTop + (hi - v) / (hi - lo) * (priceBottom - priceTop);
    double priceAt(double py) => hi - (py - priceTop) / (priceBottom - priceTop) * (hi - lo);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Lưới + trục giá
    for (final v in _ticks(lo, hi, 6)) {
      final py = y(v);
      if (py < 4 || py > mainH - 4) continue;
      canvas.drawLine(Offset(0, py), Offset(plotW, py), Paint()..color = _grid);
      _text(canvas, fmt(v, v.abs() >= 100 ? 1 : 2), Offset(plotW + 6, py - 7), _textColor);
    }
    _timeAxis(canvas, size, plotW, from, to, x);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, plotW, mainH));

    // Khối lượng
    if (volOn) {
      var maxV = 0.0;
      for (var i = from; i <= to; i++) {
        maxV = math.max(maxV, data.raw[i].v);
      }
      for (var i = from; i <= to; i++) {
        final b = data.raw[i];
        final h = maxV == 0 ? 0.0 : b.v / maxV * mainH * 0.16;
        canvas.drawRect(Rect.fromLTWH(x(i) - barW * 0.4, mainH - h, math.max(barW * 0.8, 1), h),
            Paint()..color = (b.c >= b.o ? _up : _down).withValues(alpha: 0.35));
      }
    }

    // Bollinger: vùng tô giữa 2 dải
    if (indicators.contains(Indicator.bollinger)) {
      final band = Path();
      final up = data.s['bbUp']!, lo2 = data.s['bbLo']!;
      final pts = [for (var i = from; i <= to; i++) if (up[i] != null) i];
      if (pts.isNotEmpty) {
        band.moveTo(x(pts.first), y(up[pts.first]!));
        for (final i in pts) {
          band.lineTo(x(i), y(up[i]!));
        }
        for (final i in pts.reversed) {
          band.lineTo(x(i), y(lo2[i]!));
        }
        band.close();
        canvas.drawPath(band, Paint()..color = Indicator.bollinger.color.withValues(alpha: 0.06));
      }
    }

    _drawPrice(canvas, bars, from, to, x, y, barW, mainH);

    for (final (key, color) in _overlayLines) {
      _line(canvas, data.s[key]!, from, to, x, y, color, 1.4);
    }
    canvas.restore();

    // Giá hiện tại trên trục phải
    final last = data.raw.last;
    final lastColor = last.c >= (n > 1 ? data.raw[n - 2].c : last.o) ? _up : _down;
    final ly = y(last.c);
    if (ly > 0 && ly < mainH) {
      _dashed(canvas, Offset(0, ly), Offset(plotW, ly), lastColor.withValues(alpha: 0.7));
      _tag(canvas, fmt(last.c, 2), Offset(plotW, ly), lastColor);
    }

    // Phiên đang xem: phiên dưới con trỏ, hoặc phiên cuối cùng
    final hoverIndex = cross == null ? null : (end - (plotW - cross!.dx) / barW + 0.5).floor().clamp(from, to);
    final idx = hoverIndex ?? n - 1;

    // ---------- Khung chỉ báo dao động ----------
    for (final (pi, p) in panes.indexed) {
      final top = mainH + pi * paneH;
      canvas.drawLine(Offset(0, top), Offset(size.width, top), Paint()..color = _grid..strokeWidth = 1.5);
      _pane(canvas, p, top, paneH, plotW, from, to, x, idx);
    }

    // ---------- Đường dóng + chú thích ----------
    if (cross != null && cross!.dx <= plotW && cross!.dy <= size.height - axisH) {
      final cx = x(idx);
      _dashed(canvas, Offset(cx, 0), Offset(cx, size.height - axisH), _crossColor);
      _dashed(canvas, Offset(0, cross!.dy), Offset(plotW, cross!.dy), _crossColor);
      if (cross!.dy < mainH) _tag(canvas, fmt(priceAt(cross!.dy), 2), Offset(plotW, cross!.dy), _labelBg);
      final d = _date(data.raw[idx].t);
      final label = '${_two(d.day)}/${_two(d.month)}/${d.year}';
      final tp = _layout(label, Colors.white);
      final bx = (cx - tp.width / 2 - 6).clamp(0.0, plotW - tp.width - 12);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, size.height - axisH + 2, tp.width + 12, axisH - 4), const Radius.circular(3)),
          Paint()..color = _labelBg);
      tp.paint(canvas, Offset(bx + 6, size.height - axisH + 4));
    }
    _legend(canvas, idx, plotW);
    canvas.restore();
  }

  List<String> get _overlayKeys => [
        if (indicators.contains(Indicator.ma10)) 'ma10',
        if (indicators.contains(Indicator.ma20)) 'ma20',
        if (indicators.contains(Indicator.ma50)) 'ma50',
        if (indicators.contains(Indicator.ma200)) 'ma200',
        if (indicators.contains(Indicator.ema20)) 'ema20',
        if (indicators.contains(Indicator.bollinger)) ...['bbUp', 'bbLo'],
      ];

  List<(String, Color)> get _overlayLines => [
        if (indicators.contains(Indicator.bollinger)) ...[
          ('bbUp', Indicator.bollinger.color),
          ('bbMid', Indicator.bollinger.color.withValues(alpha: 0.6)),
          ('bbLo', Indicator.bollinger.color),
        ],
        if (indicators.contains(Indicator.ma10)) ('ma10', Indicator.ma10.color),
        if (indicators.contains(Indicator.ma20)) ('ma20', Indicator.ma20.color),
        if (indicators.contains(Indicator.ma50)) ('ma50', Indicator.ma50.color),
        if (indicators.contains(Indicator.ma200)) ('ma200', Indicator.ma200.color),
        if (indicators.contains(Indicator.ema20)) ('ema20', Indicator.ema20.color),
      ];

  void _drawPrice(Canvas canvas, List<Bar> bars, int from, int to, double Function(int) x, double Function(double) y,
      double barW, double mainH) {
    switch (type) {
      case ChartType.candle || ChartType.hollow || ChartType.heikinAshi:
        final bodyW = math.max(barW * 0.7, 1.0);
        for (var i = from; i <= to; i++) {
          final b = bars[i];
          final upBar = b.c >= b.o;
          final color = upBar ? _up : _down;
          final wick = Paint()
            ..color = color
            ..strokeWidth = math.max(1, barW * 0.1).clamp(1, 1.5).toDouble();
          final cx = x(i);
          canvas.drawLine(Offset(cx, y(b.h)), Offset(cx, y(b.l)), wick);
          final top = y(math.max(b.o, b.c)), bottom = y(math.min(b.o, b.c));
          final rect = Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2, math.max(bottom, top + 1));
          final hollowUp = type == ChartType.hollow && upBar;
          canvas.drawRect(
              rect,
              Paint()
                ..color = hollowUp ? (dark ? const Color(0xFF131722) : Colors.white) : color
                ..style = PaintingStyle.fill);
          if (hollowUp) {
            canvas.drawRect(rect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1);
          }
        }
      case ChartType.ohlc:
        final tick = math.max(barW * 0.35, 1.5);
        for (var i = from; i <= to; i++) {
          final b = bars[i];
          final p = Paint()
            ..color = b.c >= b.o ? _up : _down
            ..strokeWidth = 1.5;
          final cx = x(i);
          canvas.drawLine(Offset(cx, y(b.h)), Offset(cx, y(b.l)), p);
          canvas.drawLine(Offset(cx - tick, y(b.o)), Offset(cx, y(b.o)), p);
          canvas.drawLine(Offset(cx, y(b.c)), Offset(cx + tick, y(b.c)), p);
        }
      case ChartType.line || ChartType.area || ChartType.baseline:
        final closes = <double?>[for (final b in bars) b.c];
        const lineColor = Color(0xFF2962FF);
        if (type == ChartType.area) {
          final path = _path(closes, from, to, x, y);
          if (path != null) {
            path
              ..lineTo(x(to), mainH)
              ..lineTo(x(from), mainH)
              ..close();
            canvas.drawPath(
                path,
                Paint()
                  ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, mainH),
                      [lineColor.withValues(alpha: 0.35), lineColor.withValues(alpha: 0.02)]));
          }
          _line(canvas, closes, from, to, x, y, lineColor, 2);
        } else if (type == ChartType.baseline) {
          final base = bars[from].c;
          final by = y(base);
          final path = _path(closes, from, to, x, y);
          if (path != null) {
            final fill = Path.from(path)
              ..lineTo(x(to), by)
              ..lineTo(x(from), by)
              ..close();
            canvas.save();
            canvas.clipRect(Rect.fromLTRB(0, 0, double.infinity, by));
            canvas.drawPath(fill, Paint()..color = _up.withValues(alpha: 0.18));
            canvas.drawPath(path, _stroke(_up, 2));
            canvas.restore();
            canvas.save();
            canvas.clipRect(Rect.fromLTRB(0, by, double.infinity, mainH));
            canvas.drawPath(fill, Paint()..color = _down.withValues(alpha: 0.18));
            canvas.drawPath(path, _stroke(_down, 2));
            canvas.restore();
            _dashed(canvas, Offset(0, by), Offset(x(to), by), _crossColor);
          }
        } else {
          _line(canvas, closes, from, to, x, y, lineColor, 2);
        }
    }
  }

  void _pane(Canvas canvas, Indicator p, double top, double h, double plotW, int from, int to, double Function(int) x,
      int idx) {
    final inner = Rect.fromLTWH(0, top + 18, plotW, h - 24);
    List<double?> a;
    List<double?>? b, hist;
    double lo, hi;
    List<double> guides = [];
    switch (p) {
      case Indicator.rsi:
        a = data.s['rsi']!;
        (lo, hi, guides) = (0, 100, [30, 70]);
      case Indicator.stoch:
        a = data.s['k']!;
        b = data.s['d']!;
        (lo, hi, guides) = (0, 100, [20, 80]);
      default:
        a = data.s['macd']!;
        b = data.s['signal']!;
        hist = data.s['hist']!;
        lo = double.infinity;
        hi = -double.infinity;
        for (var i = from; i <= to; i++) {
          for (final s in [a, b, hist]) {
            final v = s[i];
            if (v != null) {
              lo = math.min(lo, v);
              hi = math.max(hi, v);
            }
          }
        }
        if (!lo.isFinite) return;
        final m = math.max(hi.abs(), lo.abs()) * 1.1 + 1e-9;
        (lo, hi, guides) = (-m, m, [0]);
    }
    double y(double v) => inner.bottom - (v - lo) / (hi - lo) * inner.height;
    for (final g in guides) {
      _dashed(canvas, Offset(0, y(g)), Offset(plotW, y(g)), _crossColor.withValues(alpha: 0.5));
      _text(canvas, fmt(g, 0), Offset(plotW + 6, y(g) - 7), _textColor);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, top, plotW, h));
    if (p == Indicator.rsi) {
      canvas.drawRect(Rect.fromLTRB(0, y(70), plotW, y(30)), Paint()..color = p.color.withValues(alpha: 0.07));
    }
    if (hist != null) {
      final barW = plotW / count;
      for (var i = from; i <= to; i++) {
        final v = hist[i];
        if (v == null) continue;
        final prev = i > 0 ? hist[i - 1] ?? 0 : 0;
        final color = v >= 0 ? (v >= prev ? _up : _up.withValues(alpha: 0.5)) : (v <= prev ? _down : _down.withValues(alpha: 0.5));
        canvas.drawRect(Rect.fromLTRB(x(i) - barW * 0.35, math.min(y(v), y(0)), x(i) + barW * 0.35, math.max(y(v), y(0))),
            Paint()..color = color);
      }
    }
    final mainColor = p == Indicator.rsi ? p.color : const Color(0xFF2962FF);
    const secondColor = Color(0xFFFF6D00);
    _line(canvas, a, from, to, x, y, mainColor, 1.4);
    if (b != null) _line(canvas, b, from, to, x, y, secondColor, 1.4);
    canvas.restore();

    _rich(canvas, [
      TextSpan(text: '${p.label}  ', style: TextStyle(color: _textColor)),
      TextSpan(text: fmt(a[idx], 2), style: TextStyle(color: mainColor)),
      if (b != null) TextSpan(text: '  ${fmt(b[idx], 2)}', style: const TextStyle(color: secondColor)),
      if (hist != null && hist[idx] != null)
        TextSpan(text: '  ${fmt(hist[idx], 2)}', style: TextStyle(color: hist[idx]! >= 0 ? _up : _down)),
    ], Offset(6, top + 3), plotW - 12);
  }

  void _legend(Canvas canvas, int i, double plotW) {
    final b = data.raw[i];
    final prev = i > 0 ? data.raw[i - 1].c : b.o;
    final chg = (b.c / prev - 1) * 100;
    final color = b.c >= prev ? _up : _down;
    final spans = <InlineSpan>[
      TextSpan(text: '$symbol · 1D  ', style: TextStyle(color: _textColor, fontWeight: FontWeight.w700)),
      for (final (k, v) in [('M', b.o), ('C', b.h), ('T', b.l), ('Đ', b.c)]) ...[
        TextSpan(text: '$k ', style: TextStyle(color: _textColor)),
        TextSpan(text: '${fmt(v, 2)}  ', style: TextStyle(color: color)),
      ],
      TextSpan(text: '${chg >= 0 ? '+' : ''}${fmt(chg, 2)}%  ', style: TextStyle(color: color)),
      if (indicators.contains(Indicator.volume)) ...[
        TextSpan(text: 'KL ', style: TextStyle(color: _textColor)),
        TextSpan(text: _short(b.v), style: TextStyle(color: color)),
      ],
    ];
    _rich(canvas, spans, const Offset(6, 6), plotW - 12);
    final lines = _overlayLines.where((e) => e.$1 != 'bbMid' && e.$1 != 'bbLo').toList();
    if (lines.isNotEmpty) {
      _rich(canvas, [
        for (final (key, c) in lines) ...[
          TextSpan(text: '${key == 'bbUp' ? 'BB' : key.toUpperCase()} ', style: TextStyle(color: c)),
          TextSpan(
              text: key == 'bbUp'
                  ? '${fmt(data.s['bbUp']![i], 2)} / ${fmt(data.s['bbLo']![i], 2)}   '
                  : '${fmt(data.s[key]![i], 2)}   ',
              style: TextStyle(color: c)),
        ],
      ], const Offset(6, 24), plotW - 12);
    }
  }

  void _timeAxis(Canvas canvas, Size size, double plotW, int from, int to, double Function(int) x) {
    final barW = plotW / count;
    final step = math.max(1, (90 / barW).ceil());
    final long = count > 400;
    for (var i = from; i <= to; i += step) {
      final px = x(i);
      if (px < 20 || px > plotW - 20) continue;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height - axisH), Paint()..color = _grid);
      final d = _date(data.raw[i].t);
      _text(canvas, long ? '${_two(d.month)}/${d.year}' : '${_two(d.day)}/${_two(d.month)}', Offset(px - 16, size.height - axisH + 4),
          _textColor);
    }
  }

  // ---------- Tiện ích vẽ ----------
  Path? _path(List<double?> s, int from, int to, double Function(int) x, double Function(double) y) {
    Path? path;
    for (var i = from; i <= to; i++) {
      final v = s[i];
      if (v == null) continue;
      if (path == null) {
        path = Path()..moveTo(x(i), y(v));
      } else {
        path.lineTo(x(i), y(v));
      }
    }
    return path;
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  void _line(Canvas canvas, List<double?> s, int from, int to, double Function(int) x, double Function(double) y, Color c, double w) {
    final path = _path(s, from, to, x, y);
    if (path != null) canvas.drawPath(path, _stroke(c, w));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color c) {
    final p = Paint()
      ..color = c
      ..strokeWidth = 1;
    final len = (b - a).distance;
    final dir = (b - a) / len;
    for (var d = 0.0; d < len; d += 7) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 4, len), p);
    }
  }

  TextPainter _layout(String s, Color c) =>
      TextPainter(text: TextSpan(text: s, style: textStyle.copyWith(color: c, fontSize: 11)), textDirection: TextDirection.ltr)
        ..layout();

  void _text(Canvas canvas, String s, Offset o, Color c) => _layout(s, c).paint(canvas, o);

  void _rich(Canvas canvas, List<InlineSpan> spans, Offset o, double maxW) {
    (TextPainter(
      text: TextSpan(style: textStyle.copyWith(fontSize: 11.5), children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(maxW, 10)))
        .paint(canvas, o);
  }

  void _tag(Canvas canvas, String s, Offset at, Color bg) {
    final tp = _layout(s, Colors.white);
    final r = Rect.fromLTWH(at.dx + 2, at.dy - 9, math.max(tp.width + 10, axisW - 4), 18);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), Paint()..color = bg);
    tp.paint(canvas, Offset(r.left + 5, r.top + 2));
  }

  static DateTime _date(int t) => DateTime.fromMillisecondsSinceEpoch((t + 7 * 3600) * 1000, isUtc: true);
  static String _two(int x) => x.toString().padLeft(2, '0');
  static String _short(double v) => v >= 1e9
      ? '${fmt(v / 1e9, 2)}B'
      : v >= 1e6
          ? '${fmt(v / 1e6, 2)}M'
          : v >= 1e3
              ? '${fmt(v / 1e3, 1)}K'
              : fmt(v, 0);

  /// Mốc chia đẹp (1, 2, 5 × 10^k) cho trục giá.
  static List<double> _ticks(double lo, double hi, int target) {
    final raw = (hi - lo) / target;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    final out = <double>[];
    for (var v = (lo / step).ceil() * step; v <= hi; v += step) {
      out.add(v);
    }
    return out;
  }

  @override
  bool shouldRepaint(_ChartPainter o) =>
      o.end != end ||
      o.count != count ||
      o.cross != cross ||
      o.type != type ||
      o.indicators != indicators ||
      o.data != data ||
      o.dark != dark;
}
