// Biểu đồ đường cho chuỗi vĩ mô. Theo hướng dẫn biểu đồ của skill ui-ux-pro-max:
//  - số liệu thực là nét liền, dự báo là nét đứt kèm chấm rỗng và nhãn "Dự báo" (không chỉ phân biệt bằng màu);
//  - rê chuột, chạm/kéo hoặc phím mũi tên để xem giá trị từng kỳ (tooltip), Home/End/Esc;
//  - viền focus nhìn thấy được, mô tả tóm tắt cho trình đọc màn hình, màu lấy từ theme (không viết cứng).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;

import '../services/macro.dart';
import 'widgets.dart' show fmt;

/// Tóm tắt bằng lời cho trình đọc màn hình (và dùng lại ở bảng số liệu).
String macroSummary(MacroSeries s) {
  final d = s.def, a = s.actual;
  if (a.isEmpty) return d.title;
  final last = a.last;
  final b = StringBuffer('${d.title}. Mới nhất ${fmt(last.value, d.decimals)} ${d.unit}, kỳ ${last.label}.');
  final prev = s.previous;
  if (prev != null) {
    final diff = last.value - prev.value;
    b.write(diff == 0
        ? ' Không đổi so với ${prev.label}.'
        : ' So với ${prev.label}: ${diff > 0 ? 'tăng' : 'giảm'} ${fmt(diff.abs(), d.decimals)} ${d.diffUnit}.');
  }
  final hi = a.reduce((x, y) => y.value > x.value ? y : x), lo = a.reduce((x, y) => y.value < x.value ? y : x);
  b.write(' Cao nhất ${fmt(hi.value, d.decimals)} (${hi.label}), thấp nhất ${fmt(lo.value, d.decimals)} (${lo.label}).');
  if (s.hasForecast) {
    final f = s.points.last;
    b.write(' Dự báo ${f.label}: ${fmt(f.value, d.decimals)} ${d.unit}.');
  }
  return b.toString();
}

class _G {
  static const left = 52.0, right = 14.0, top = 14.0, bottom = 28.0;
}

class MacroChart extends StatefulWidget {
  final MacroSeries series;

  /// Số năm gần nhất cần hiển thị; null hoặc 0 = toàn bộ.
  final int? years;
  const MacroChart(this.series, {super.key, this.years});

  @override
  State<MacroChart> createState() => _MacroChartState();
}

class _MacroChartState extends State<MacroChart> {
  final _focus = FocusNode(debugLabel: 'macro-chart');
  int? _selected;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<MacroPoint> get _pts => widget.series.window(widget.years);

  void _selectAt(double dx, double plotW) {
    final n = _pts.length;
    if (n == 0) return;
    final t = n == 1 ? 0.0 : ((dx - _G.left) / plotW).clamp(0.0, 1.0);
    final i = (t * (n - 1)).round();
    if (i != _selected) setState(() => _selected = i);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final n = _pts.length;
    if (n == 0) return KeyEventResult.ignored;
    final k = e.logicalKey;
    int? next;
    if (k == LogicalKeyboardKey.arrowLeft) {
      next = ((_selected ?? n) - 1).clamp(0, n - 1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      next = ((_selected ?? -1) + 1).clamp(0, n - 1);
    } else if (k == LogicalKeyboardKey.home) {
      next = 0;
    } else if (k == LogicalKeyboardKey.end) {
      next = n - 1;
    } else if (k == LogicalKeyboardKey.escape) {
      setState(() => _selected = null);
      return KeyEventResult.handled;
    }
    if (next == null) return KeyEventResult.ignored;
    setState(() => _selected = next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = _pts;
    final sel = _selected != null && _selected! < pts.length ? _selected : null;
    final d = widget.series.def;
    final selectedText = sel == null
        ? null
        : '${pts[sel].label}: ${fmt(pts[sel].value, d.decimals)} ${d.unit}${pts[sel].forecast ? ', dự báo' : ''}';

    return Semantics(
      container: true,
      label: macroSummary(widget.series),
      value: selectedText,
      hint: 'Dùng phím mũi tên trái phải để xem từng kỳ',
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          onFocusChange: (f) => setState(() => _focused = f),
          child: LayoutBuilder(builder: (context, box) {
            final plotW = box.maxWidth - _G.left - _G.right;
            return MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (e) => _selectAt(e.localPosition.dx, plotW),
              onExit: (_) {
                if (!_focused) setState(() => _selected = null);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (t) {
                  _focus.requestFocus();
                  _selectAt(t.localPosition.dx, plotW);
                },
                onHorizontalDragUpdate: (u) => _selectAt(u.localPosition.dx, plotW),
                child: DecoratedBox(
                  // Viền luôn có độ dày cố định để không làm lệch bố cục khi nhận/mất focus
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _focused ? cs.primary : Colors.transparent, width: 2),
                  ),
                  child: CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: _MacroPainter(
                      pts: pts,
                      def: d,
                      selected: sel,
                      line: cs.primary,
                      grid: cs.outlineVariant,
                      axis: cs.onSurfaceVariant,
                      tipBg: cs.inverseSurface,
                      tipFg: cs.onInverseSurface,
                      ring: Theme.of(context).cardTheme.color ?? cs.surface,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _MacroPainter extends CustomPainter {
  final List<MacroPoint> pts;
  final MacroDef def;
  final int? selected;
  final Color line, grid, axis, tipBg, tipFg, ring;

  _MacroPainter({
    required this.pts,
    required this.def,
    required this.selected,
    required this.line,
    required this.grid,
    required this.axis,
    required this.tipBg,
    required this.tipFg,
    required this.ring,
  });

  TextPainter _tp(String s, Color c, {double size = 12, FontWeight? weight}) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: c, fontSize: size, fontWeight: weight, height: 1.2)),
        textDirection: TextDirection.ltr,
      )..layout();

  /// Mốc chia đẹp (1, 2, 2.5, 5 × 10^k) cho trục giá trị.
  static List<double> niceTicks(double lo, double hi, int target) {
    final raw = (hi - lo) / target;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1.0, 2.0, 2.5, 5.0, 10.0].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    return [for (var v = (lo / step).ceil() * step; v <= hi + step * 1e-9; v += step) v];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = pts.length;
    final plotW = size.width - _G.left - _G.right, plotH = size.height - _G.top - _G.bottom;
    if (n == 0 || plotW <= 0 || plotH <= 0) return;

    var lo = pts.map((p) => p.value).reduce(math.min), hi = pts.map((p) => p.value).reduce(math.max);
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    double x(int i) => n == 1 ? _G.left + plotW / 2 : _G.left + i * plotW / (n - 1);
    double y(double v) => _G.top + (hi - v) / (hi - lo) * plotH;

    // Lưới ngang và nhãn trục giá trị
    final ticks = niceTicks(lo, hi, 4);
    final step = ticks.length > 1 ? ticks[1] - ticks[0] : 1.0;
    final tickDecimals = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    for (final t in ticks) {
      final py = y(t);
      final isZero = t.abs() < step * 1e-9;
      canvas.drawLine(
        Offset(_G.left, py),
        Offset(_G.left + plotW, py),
        Paint()
          ..color = isZero ? axis.withValues(alpha: 0.7) : grid
          ..strokeWidth = isZero ? 1.5 : 1,
      );
      final lab = _tp(fmt(t, tickDecimals), axis);
      lab.paint(canvas, Offset(_G.left - 8 - lab.width, py - lab.height / 2));
    }

    // Nhãn trục thời gian: cách nhau tối thiểu ~72px, neo từ kỳ cuối
    final perPoint = n > 1 ? plotW / (n - 1) : plotW;
    final every = math.max(1, (72 / perPoint).ceil());
    for (var i = n - 1; i >= 0; i -= every) {
      final lab = _tp(pts[i].label, axis);
      final lx = (x(i) - lab.width / 2).clamp(_G.left - 20, size.width - lab.width - 2).toDouble();
      lab.paint(canvas, Offset(lx, size.height - _G.bottom + 8));
    }

    final aEnd = pts.lastIndexWhere((p) => !p.forecast);
    final baseY = (lo < 0 && hi > 0) ? y(0) : _G.top + plotH;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(_G.left - 2, 0, plotW + 4, size.height));

    // Vùng dự báo
    if (aEnd >= 0 && aEnd < n - 1) {
      final r = Rect.fromLTRB(x(aEnd), _G.top, _G.left + plotW, _G.top + plotH);
      canvas.drawRect(r, Paint()..color = line.withValues(alpha: 0.08));
      _tp('Dự báo', axis, weight: FontWeight.w600).paint(canvas, Offset(r.left + 6, _G.top + 2));
    }

    // Số liệu thực: vùng tô nhạt + nét liền
    if (aEnd >= 0) {
      final path = Path()..moveTo(x(0), y(pts[0].value));
      for (var i = 1; i <= aEnd; i++) {
        path.lineTo(x(i), y(pts[i].value));
      }
      if (aEnd > 0) {
        final fill = Path.from(path)
          ..lineTo(x(aEnd), baseY)
          ..lineTo(x(0), baseY)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, _G.top),
              Offset(0, _G.top + plotH),
              [line.withValues(alpha: 0.22), line.withValues(alpha: 0.0)],
            ),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.25
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // Dự báo: nét đứt nối từ kỳ thực tế cuối
    if (aEnd < n - 1) {
      final from = math.max(aEnd, 0);
      final path = Path()..moveTo(x(from), y(pts[from].value));
      for (var i = from + 1; i < n; i++) {
        path.lineTo(x(i), y(pts[i].value));
      }
      final dashed = Path();
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 9) {
          dashed.addPath(m.extractPath(d, math.min(d + 5, m.length)), Offset.zero);
        }
      }
      canvas.drawPath(
        dashed,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.25
          ..strokeCap = StrokeCap.round,
      );
    }

    // Chấm dữ liệu: đặc cho số liệu thực, rỗng cho dự báo
    if (n <= 60) {
      for (var i = 0; i < n; i++) {
        final c = Offset(x(i), y(pts[i].value));
        if (pts[i].forecast) {
          canvas.drawCircle(c, 3, Paint()..color = ring);
          canvas.drawCircle(
            c,
            3,
            Paint()
              ..color = line
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        } else {
          canvas.drawCircle(c, 2.5, Paint()..color = line);
        }
      }
    }
    if (aEnd >= 0) {
      final c = Offset(x(aEnd), y(pts[aEnd].value));
      canvas.drawCircle(c, 6, Paint()..color = ring);
      canvas.drawCircle(c, 4.5, Paint()..color = line);
    }
    canvas.restore();

    // Điểm đang xem + tooltip
    final s = selected;
    if (s != null && s < n) {
      final p = pts[s];
      final px = x(s), py = y(p.value);
      final guide = Paint()
        ..color = axis
        ..strokeWidth = 1;
      for (var d = _G.top; d < _G.top + plotH; d += 7) {
        canvas.drawLine(Offset(px, d), Offset(px, math.min(d + 4, _G.top + plotH)), guide);
      }
      canvas.drawCircle(Offset(px, py), 7, Paint()..color = ring);
      canvas.drawCircle(Offset(px, py), 5, Paint()..color = line);

      final head = _tp(p.forecast ? '${p.label} · Dự báo' : p.label, tipFg, weight: FontWeight.w600);
      final body = _tp('${fmt(p.value, def.decimals)} ${def.unit}', tipFg, size: 13);
      final w = math.max(head.width, body.width) + 16, h = head.height + body.height + 14;
      var bx = px + 12;
      if (bx + w > size.width - 4) bx = px - 12 - w;
      bx = bx.clamp(4.0, math.max(4.0, size.width - w - 4)).toDouble();
      var by = py - h - 10;
      if (by < 2) by = py + 12;
      by = by.clamp(2.0, math.max(2.0, size.height - _G.bottom - h)).toDouble();
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, w, h), const Radius.circular(8)), Paint()..color = tipBg);
      head.paint(canvas, Offset(bx + 8, by + 6));
      body.paint(canvas, Offset(bx + 8, by + 8 + head.height));
    }
  }

  @override
  bool shouldRepaint(_MacroPainter o) =>
      o.pts != pts ||
      o.selected != selected ||
      o.def != def ||
      o.line != line ||
      o.grid != grid ||
      o.axis != axis ||
      o.tipBg != tipBg ||
      o.ring != ring;
}
