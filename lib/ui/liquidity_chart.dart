// Biểu đồ thanh khoản trong phiên: khối lượng khớp cộng dồn theo từng phút, phiên gần nhất so với phiên trước đó.
// Tự cập nhật trong giờ giao dịch cùng nhịp với giá.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/market.dart';
import 'widgets.dart';

/// Khối lượng cộng dồn theo phút (phút trong ngày, giờ Việt Nam) của một phiên.
class SessionVolume {
  final String day;
  final List<(int, double)> points;
  const SessionVolume(this.day, this.points);

  double get total => points.isEmpty ? 0 : points.last.$2;

  /// Khối lượng cộng dồn tại phút [minute] (giữ nguyên giá trị gần nhất trước đó; null nếu phiên chưa tới phút này).
  double? at(int minute) {
    if (points.isEmpty || minute < points.first.$1) return null;
    if (minute > points.last.$1) return null;
    var v = points.first.$2;
    for (final p in points) {
      if (p.$1 > minute) break;
      v = p.$2;
    }
    return v;
  }
}

/// Gộp nến 1 phút thành hai phiên cuối: (phiên trước, phiên gần nhất). Trả về null nếu thiếu dữ liệu.
(SessionVolume, SessionVolume)? sessionsOf(List<Bar> minutes) {
  final byDay = <String, List<Bar>>{};
  for (final b in minutes) {
    byDay.putIfAbsent(vnDate(b.t), () => []).add(b);
  }
  final days = byDay.keys.toList()..sort();
  if (days.length < 2) return null;
  SessionVolume build(String d) {
    var sum = 0.0;
    final pts = <(int, double)>[];
    for (final b in byDay[d]!) {
      sum += b.v;
      pts.add((((b.t + 7 * 3600) % 86400) ~/ 60, sum));
    }
    return SessionVolume(d, pts);
  }

  return (build(days[days.length - 2]), build(days.last));
}

String _compact(double v) {
  if (v >= 1e9) return '${fmt(v / 1e9, 1)} tỷ';
  if (v >= 1e6) return '${fmt(v / 1e6, v >= 1e7 ? 0 : 1)} tr';
  if (v >= 1e3) return '${fmt(v / 1e3, 0)} N';
  return fmt(v, 0);
}

String _clock(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class LiquidityChart extends StatefulWidget {
  final String symbol;
  const LiquidityChart(this.symbol, {super.key});

  @override
  State<LiquidityChart> createState() => _LiquidityChartState();
}

class _LiquidityChartState extends State<LiquidityChart> {
  (SessionVolume, SessionVolume)? _data;
  bool _failed = false;
  Timer? _timer;
  int? _hover;

  @override
  void initState() {
    super.initState();
    _load();
    // Cùng nhịp với giá: 30 giây một lần trong giờ giao dịch
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isTradingTime(DateTime.now())) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final bars = await fetchBars(widget.symbol, days: 6, resolution: '1');
    if (!mounted) return;
    final s = sessionsOf(bars);
    setState(() {
      if (s != null) {
        _data = s;
        _failed = false;
      } else if (_data == null) {
        _failed = true;
      }
    });
  }

  String _name(String day) {
    final today = vietnamToday();
    if (day == today) return 'Hôm nay';
    final d = DateTime.parse(day), t = DateTime.parse(today);
    final diff = DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
    final dm = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return diff == 1 ? 'Hôm qua' : dm;
  }

  void _track(Offset p, double width) {
    final m = _xToMinute(p.dx, width);
    if (m != _hover) setState(() => _hover = m);
  }

  int? _xToMinute(double x, double width) {
    final inner = width - _padL - _padR;
    if (inner <= 0) return null;
    final f = ((x - _padL) / inner).clamp(0.0, 1.0);
    return (_open + f * (_close - _open)).round();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = _data;
    final yesterday = Tone.down(context);
    final today = Tone.up(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'THANH KHOẢN TRONG PHIÊN',
                  style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (d == null)
            SizedBox(
              height: 140,
              child: Center(
                child: _failed
                    ? Text('Chưa có dữ liệu theo phút.', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                    : const CircularProgressIndicator(),
              ),
            )
          else ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                _Key(color: yesterday, dashed: true, label: '${_name(d.$1.day)}: ${_compact(d.$1.total)}'),
                _Key(color: today, label: '${_name(d.$2.day)}: ${_compact(d.$2.total)}'),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                final h = 170.0;
                final m = _hover;
                return Semantics(
                  label:
                      'Biểu đồ thanh khoản cộng dồn trong phiên. ${_name(d.$2.day)} ${_compact(d.$2.total)}, '
                      '${_name(d.$1.day)} ${_compact(d.$1.total)}.',
                  child: MouseRegion(
                    onHover: (e) => _track(e.localPosition, w),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (e) => _track(e.localPosition, w),
                      onHorizontalDragUpdate: (e) => _track(e.localPosition, w),
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: CustomPaint(
                          painter: _LiquidityPainter(
                            prev: d.$1,
                            cur: d.$2,
                            prevColor: yesterday,
                            curColor: today,
                            grid: cs.outlineVariant,
                            label: cs.onSurfaceVariant,
                            hover: m,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_hover != null) ...[
              const SizedBox(height: 6),
              _Readout(hover: _hover!, prev: d.$1, cur: d.$2, prevName: _name(d.$1.day), curName: _name(d.$2.day)),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Khối lượng cộng dồn từng phút. Rê chuột hoặc chạm vào biểu đồ để xem chi tiết.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Ngày hôm nay (giờ Việt Nam) dạng yyyy-MM-dd.
String vietnamToday() => DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);

const double _padL = 44, _padR = 8, _padT = 8, _padB = 22;
const int _open = 9 * 60, _close = 15 * 60;

class _Key extends StatelessWidget {
  final Color color;
  final bool dashed;
  final String label;
  const _Key({required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 22, height: 10, child: CustomPaint(painter: _KeyPainter(color, dashed))),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
    ],
  );
}

class _KeyPainter extends CustomPainter {
  final Color color;
  final bool dashed;
  _KeyPainter(this.color, this.dashed);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.color != color || old.dashed != dashed;
}

class _Readout extends StatelessWidget {
  final int hover;
  final SessionVolume prev, cur;
  final String prevName, curName;
  const _Readout({required this.hover, required this.prev, required this.cur, required this.prevName, required this.curName});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = cur.at(hover), p = prev.at(hover);
    String f(double? v) => v == null ? '–' : fmt(v, 0);
    return Text(
      '${_clock(hover)}  ·  $curName: ${f(c)}  ·  $prevName: ${f(p)}',
      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class _LiquidityPainter extends CustomPainter {
  final SessionVolume prev, cur;
  final Color prevColor, curColor, grid, label;
  final int? hover;
  _LiquidityPainter({
    required this.prev,
    required this.cur,
    required this.prevColor,
    required this.curColor,
    required this.grid,
    required this.label,
    required this.hover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _padL - _padR, h = size.height - _padT - _padB;
    if (w <= 0 || h <= 0) return;
    final top = math.max(prev.total, cur.total);
    final maxV = _niceMax(top <= 0 ? 1 : top);
    double x(int m) => _padL + (m - _open) / (_close - _open) * w;
    double y(double v) => _padT + h - v / maxV * h;

    void text(String s, Offset at, {TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: 11, color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.right ? at.dx - tp.width : (align == TextAlign.center ? at.dx - tp.width / 2 : at.dx);
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = maxV * i / 4;
      canvas.drawLine(Offset(_padL, y(v)), Offset(_padL + w, y(v)), gridPaint);
      text(_compact(v), Offset(_padL - 6, y(v)), align: TextAlign.right);
    }
    for (final m in [9 * 60, 10 * 60 + 30, 11 * 60 + 30, 13 * 60, 14 * 60, 15 * 60]) {
      text(_clock(m), Offset(x(m), size.height - 8), align: TextAlign.center);
    }

    Path line(SessionVolume s, {bool close = false}) {
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = s.points[i];
        final o = Offset(x(p.$1.clamp(_open, _close)), y(p.$2));
        if (i == 0) {
          path.moveTo(o.dx, y(0));
          path.lineTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      if (close && s.points.isNotEmpty) path.lineTo(x(s.points.last.$1.clamp(_open, _close)), y(0));
      return path;
    }

    // Vùng tô của phiên gần nhất, đường liền; phiên trước là nét đứt để không chỉ phân biệt bằng màu
    canvas.drawPath(line(cur, close: true), Paint()..color = curColor.withValues(alpha: 0.22));
    final prevPath = line(prev);
    final dash = Paint()
      ..color = prevColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in prevPath.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), dash);
      }
    }
    canvas.drawPath(
      line(cur),
      Paint()
        ..color = curColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    final hv = hover;
    if (hv != null) {
      canvas.drawLine(
        Offset(x(hv), _padT),
        Offset(x(hv), _padT + h),
        Paint()
          ..color = label
          ..strokeWidth = 1,
      );
      for (final (s, c) in [(prev, prevColor), (cur, curColor)]) {
        final v = s.at(hv);
        if (v != null) {
          canvas.drawCircle(Offset(x(hv), y(v)), 4, Paint()..color = c);
        }
      }
    }
  }

  double _niceMax(double v) {
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final k in [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
      if (v <= k * mag) return k * mag;
    }
    return 10 * mag;
  }

  @override
  bool shouldRepaint(_LiquidityPainter old) =>
      old.prev != prev || old.cur != cur || old.hover != hover || old.prevColor != prevColor || old.curColor != curColor;
}
