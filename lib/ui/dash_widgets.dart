// Các thành phần vẽ tay của dashboard Tổng quan: bản đồ nhiệt, biểu đồ tròn/cột dòng tiền, biểu đồ trong phiên.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/board.dart';
import '../services/market.dart';
import '../services/treemap.dart';
import 'widgets.dart';

const heatUp = Color(0xFF16B04B), heatDown = Color(0xFFE0392F), heatFlat = Color(0xFFD8B400);
const heatCeil = Color(0xFFB04DFF), heatFloor = Color(0xFF1EC8E0);

/// Màu ô theo % thay đổi: xanh lá tăng, đỏ giảm, vàng đứng giá, tím trần, xanh lơ sàn; đậm nhạt theo độ lớn.
Color heatColor(BoardRow r) {
  if (r.atCeil) return heatCeil;
  if (r.atFloor) return heatFloor;
  if (r.dir == 0) return heatFlat;
  final t = (r.pct.abs() / 6).clamp(0.0, 1.0);
  return r.dir > 0
      ? Color.lerp(const Color(0xFF3F7A4B), heatUp, t)!
      : Color.lerp(const Color(0xFF86413E), heatDown, t)!;
}

// ---------- Bản đồ nhiệt ----------

class HeatMap extends StatefulWidget {
  final List<BoardRow> rows;
  final Map<String, SectorInfo> sectors;
  final void Function(String symbol) onOpen;
  const HeatMap({super.key, required this.rows, required this.sectors, required this.onOpen});

  @override
  State<HeatMap> createState() => _HeatMapState();
}

class _HeatMapState extends State<HeatMap> {
  List<PlacedGroup> _placed = const [];
  Map<String, BoardRow> _bySymbol = const {};
  Map<String, String> _sectorOf = const {};
  Object? _builtRows;
  Object? _builtSectors;
  Size? _builtSize;
  String? _hover;
  Offset _pointer = Offset.zero;

  void _build(Size size) {
    if (identical(_builtRows, widget.rows) && identical(_builtSectors, widget.sectors) && _builtSize == size) return;
    final groups = groupBySector(widget.rows, widget.sectors);
    _bySymbol = {for (final r in widget.rows) r.symbol: r};
    _sectorOf = {
      for (final g in groups)
        for (final r in g.rows) r.symbol: g.name,
    };
    final noValue = widget.rows.every((r) => r.valueMn + r.ptValueMn <= 0);
    double w(BoardRow r) => noValue ? (widget.sectors[r.symbol]?.marketCap ?? 0) : r.valueMn + r.ptValueMn;
    _placed = layoutTwoLevel([
      for (final g in groups) TreeGroup(g.name, [for (final r in g.rows) TreeItem(r.symbol, w(r))]),
    ], Offset.zero & size);
    _builtRows = widget.rows;
    _builtSectors = widget.sectors;
    _builtSize = size;
    if (!_bySymbol.containsKey(_hover)) _hover = null;
  }

  String? _hit(Offset p) {
    for (final g in _placed) {
      if (!g.rect.contains(p)) continue;
      for (final it in g.items) {
        if (it.rect.contains(p)) return it.id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const Center(child: Text('Chưa có dữ liệu bảng giá'));
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        _build(size);
        final hover = _hover == null ? null : _bySymbol[_hover];
        return MouseRegion(
          onHover: (e) {
            final h = _hit(e.localPosition);
            if (h != _hover || h != null) {
              setState(() {
                _hover = h;
                _pointer = e.localPosition;
              });
            }
          },
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapUp: (d) {
              final h = _hit(d.localPosition);
              if (h != null) widget.onOpen(h);
            },
            onLongPressStart: (d) => setState(() {
              _hover = _hit(d.localPosition);
              _pointer = d.localPosition;
            }),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(child: CustomPaint(painter: _HeatPainter(_placed, _bySymbol, widget.rows))),
                ),
                if (hover != null) ..._tooltip(context, hover, size),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _tooltip(BuildContext context, BoardRow r, Size size) {
    final cell = [
      for (final g in _placed)
        for (final it in g.items)
          if (it.id == r.symbol) it.rect,
    ].firstOrNull;
    final text =
        '${r.symbol} · ${_sectorOf[r.symbol] ?? 'Khác'}\n'
        'Giá ${fmt(r.price / 1000, 2)} (${r.pct >= 0 ? '+' : ''}${fmt(r.pct)}%)\n'
        'GTGD ${fmt((r.valueMn + r.ptValueMn) / 1000, 1)} tỷ';
    const w = 170.0, h = 62.0;
    final left = (_pointer.dx + 14 + w > size.width) ? _pointer.dx - 14 - w : _pointer.dx + 14;
    final top = (_pointer.dy + 14 + h > size.height) ? _pointer.dy - 14 - h : _pointer.dy + 14;
    return [
      if (cell != null)
        Positioned.fromRect(
          rect: cell,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2)),
            ),
          ),
        ),
      Positioned(
        left: left.clamp(0.0, math.max(0, size.width - w)),
        top: top.clamp(0.0, math.max(0, size.height - h)),
        width: w,
        child: IgnorePointer(
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            color: Theme.of(context).colorScheme.inverseSurface,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                text,
                style: TextStyle(fontSize: 12, height: 1.3, color: Theme.of(context).colorScheme.onInverseSurface),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

class _HeatPainter extends CustomPainter {
  final List<PlacedGroup> placed;
  final Map<String, BoardRow> rows;
  final Object token; // đổi khi dữ liệu đổi
  _HeatPainter(this.placed, this.rows, this.token);

  TextPainter _tp(String s, double size, Color color, double maxW, {FontWeight w = FontWeight.w600}) => TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: size, color: color, fontWeight: w, height: 1.1),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxW);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B2230));
    for (final g in placed) {
      if (g.header.height > 0) {
        final tp = _tp(g.name, 11, Colors.white70, g.header.width - 6);
        tp.paint(canvas, Offset(g.header.left + 4, g.header.top + (g.header.height - tp.height) / 2));
      }
      for (final it in g.items) {
        final r = rows[it.id];
        if (r == null) continue;
        final rect = it.rect.deflate(0.6);
        canvas.drawRect(rect, Paint()..color = heatColor(r));
        if (rect.width >= 30 && rect.height >= 18) {
          final big = rect.width >= 56 && rect.height >= 36;
          final fs = math.min(big ? 15.0 : 11.0, math.max(9.0, math.min(rect.width / 4.2, rect.height / 2.6)));
          final sym = _tp(it.id, fs, Colors.white, rect.width - 4, w: FontWeight.w700);
          final showPct = rect.height >= sym.height * 2 + 4 && rect.width >= 44;
          final pct = showPct
              ? _tp(
                  '${r.pct >= 0 ? '+' : ''}${fmt(r.pct)}%',
                  math.max(9, fs - 2),
                  Colors.white,
                  rect.width - 4,
                  w: FontWeight.w500,
                )
              : null;
          final total = sym.height + (pct?.height ?? 0);
          var y = rect.top + (rect.height - total) / 2;
          sym.paint(canvas, Offset(rect.left + (rect.width - sym.width) / 2, y));
          pct?.paint(canvas, Offset(rect.left + (rect.width - pct.width) / 2, y + sym.height));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) => !identical(old.placed, placed) || !identical(old.token, token);
}

// ---------- Dòng tiền: biểu đồ tròn và cột ----------

class BreadthPie extends StatelessWidget {
  final int up, down, flat;
  const BreadthPie({super.key, required this.up, required this.down, required this.flat});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _PiePainter(up, down, flat, Theme.of(context).colorScheme.onSurface));
}

class _PiePainter extends CustomPainter {
  final int up, down, flat;
  final Color text;
  _PiePainter(this.up, this.down, this.flat, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    final total = up + down + flat;
    if (total == 0) return;
    final radius = math.max(10.0, math.min(size.width / 2 - 52, size.height / 2 - 8));
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (final (n, color, label) in [(up, heatUp, 'Tăng'), (down, heatDown, 'Giảm'), (flat, heatFlat, 'Không đổi')]) {
      if (n == 0) continue;
      final sweep = n / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = color);
      final mid = start + sweep / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: '$label ($n)',
          style: TextStyle(fontSize: 11, color: text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = center + Offset(math.cos(mid), math.sin(mid)) * (radius + 6);
      final dx = math.cos(mid) >= 0 ? p.dx : p.dx - tp.width;
      tp.paint(
        canvas,
        Offset(dx.clamp(0.0, size.width - tp.width), (p.dy - tp.height / 2).clamp(0.0, size.height - tp.height)),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.up != up || old.down != down || old.flat != flat || old.text != text;
}

/// Cột "Phân bổ dòng tiền": tổng giá trị giao dịch (tỷ đồng) của nhóm Tăng / Giảm / Không đổi.
class FlowBars extends StatelessWidget {
  final double up, down, flat; // tỷ đồng
  const FlowBars({super.key, required this.up, required this.down, required this.flat});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _FlowPainter(up, down, flat, Theme.of(context).colorScheme.onSurface));
}

class _FlowPainter extends CustomPainter {
  final double up, down, flat;
  final Color text;
  _FlowPainter(this.up, this.down, this.flat, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(math.max(up, down), math.max(flat, 1));
    const labelH = 16.0, topPad = 16.0;
    final base = size.height - labelH;
    final slot = size.width / 3;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = text.withValues(alpha: 0.25));
    for (final (i, v, color, label) in [
      (0, up, heatUp, 'Tăng'),
      (1, down, heatDown, 'Giảm'),
      (2, flat, heatFlat, 'Kh. đổi'),
    ]) {
      final h = (v / maxV) * (base - topPad);
      final w = math.min(slot * 0.5, 44.0);
      final cx = slot * i + slot / 2;
      canvas.drawRect(Rect.fromLTWH(cx - w / 2, base - h, w, h), Paint()..color = color);
      final val = TextPainter(
        text: TextSpan(
          text: '${fmt(v, 1)} tỷ',
          style: TextStyle(fontSize: 11, color: text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      val.paint(canvas, Offset(cx - val.width / 2, math.max(0, base - h - val.height - 1)));
      final lab = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 11, color: text.withValues(alpha: 0.7)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lab.paint(canvas, Offset(cx - lab.width / 2, base + 2));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.up != up || old.down != down || old.flat != flat || old.text != text;
}

// ---------- Biểu đồ trong phiên ----------

/// Phút trong ngày (giờ Việt Nam) của một nến.
int minuteOfDayVN(int t) => ((t + 7 * 3600) % 86400) ~/ 60;

class IntradayChart extends StatelessWidget {
  final List<Bar> bars;
  final double? ref;
  const IntradayChart({super.key, required this.bars, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (bars.length < 2) return const Center(child: Text('Chưa có dữ liệu trong phiên'));
    final last = bars.last.c;
    final color = ref == null || last >= ref! ? Tone.up(context) : Tone.down(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _IntradayPainter(bars, ref, color, Tone.flat(context), Theme.of(context).colorScheme.onSurface),
    );
  }
}

class _IntradayPainter extends CustomPainter {
  final List<Bar> bars;
  final double? ref;
  final Color line, refColor, text;
  _IntradayPainter(this.bars, this.ref, this.line, this.refColor, this.text);

  static const open = 9 * 60, close = 15 * 60;

  @override
  void paint(Canvas canvas, Size size) {
    const axisW = 44.0, axisH = 16.0;
    final plotW = size.width - axisW, plotH = size.height - axisH;
    if (plotW <= 0 || plotH <= 0) return;
    double x(Bar b) => ((minuteOfDayVN(b.t) - open) / (close - open)).clamp(0.0, 1.0) * plotW;
    var lo = bars.map((b) => b.c).reduce(math.min), hi = bars.map((b) => b.c).reduce(math.max);
    if (ref != null) {
      lo = math.min(lo, ref!);
      hi = math.max(hi, ref!);
    }
    final pad = (hi - lo) * 0.08 + 0.01;
    lo -= pad;
    hi += pad;
    final volH = plotH * 0.22;
    final priceH = plotH - volH * 0.6;
    double y(double v) => (1 - (v - lo) / (hi - lo)) * priceH;
    TextPainter label(String s, Color c) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: 10, color: c),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final grid = Paint()..color = text.withValues(alpha: 0.12);
    for (var i = 0; i <= 3; i++) {
      final v = lo + (hi - lo) * i / 3;
      canvas.drawLine(Offset(0, y(v)), Offset(plotW, y(v)), grid);
      label(fmt(v, 1), text.withValues(alpha: 0.7)).paint(canvas, Offset(plotW + 4, y(v) - 6));
    }
    for (var h = 9; h <= 15; h++) {
      final gx = (h * 60 - open) / (close - open) * plotW;
      canvas.drawLine(Offset(gx, 0), Offset(gx, plotH), grid);
      final tp = label('$h:00', text.withValues(alpha: 0.7));
      tp.paint(canvas, Offset((gx - tp.width / 2).clamp(0.0, size.width - tp.width), plotH + 2));
    }
    // Khối lượng
    final maxV = bars.map((b) => b.v).reduce(math.max);
    if (maxV > 0) {
      final w = math.max(1.0, plotW / (close - open));
      for (final b in bars) {
        final h = b.v / maxV * volH;
        canvas.drawRect(Rect.fromLTWH(x(b), plotH - h, w, h), Paint()..color = line.withValues(alpha: 0.45));
      }
    }
    // Đường tham chiếu nét đứt
    if (ref != null) {
      final p = Paint()
        ..color = refColor
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < plotW; dx += 8) {
        canvas.drawLine(Offset(dx, y(ref!)), Offset(math.min(dx + 4, plotW), y(ref!)), p);
      }
    }
    final path = Path();
    for (final (i, b) in bars.indexed) {
      i == 0 ? path.moveTo(x(b), y(b.c)) : path.lineTo(x(b), y(b.c));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(x(bars.last), y(bars.last.c)), 3, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_IntradayPainter old) =>
      !identical(old.bars, bars) || old.ref != ref || old.line != line || old.text != text;
}
