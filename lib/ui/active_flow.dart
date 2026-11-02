// Dòng tiền trong phiên theo lệnh khớp: khối lượng, mua chủ động và bán chủ động theo từng khoảng thời gian, kèm "tiền lớn"
// (lệnh khớp từ 1 tỷ đồng). Dữ liệu lệnh khớp của Vietcap, tải cả phiên bằng nhiều lượt song song (xem services/ticks.dart) và tự cập nhật
// trong giờ giao dịch. Biểu đồ có chú giải, giá trị khi rê chuột/chạm, và phân biệt mua/bán bằng hướng cột (lên/xuống) chứ không chỉ bằng màu.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dashboard.dart';
import '../services/market.dart' show vnDate;
import '../services/ticks.dart';
import 'widgets.dart';

String _clock(int epoch) {
  final v = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).add(const Duration(hours: 7));
  return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
}

String _vol(double v) {
  if (v >= 1e6) return '${fmt(v / 1e6, 2)} triệu';
  if (v >= 1e3) return '${fmt(v / 1e3, 1)} nghìn';
  return fmt(v, 0);
}

String _bn(double dong) => '${fmt(dong.abs() / 1e9, 1)} tỷ';

class ActiveFlow extends StatefulWidget {
  final String symbol;

  /// Chỉ dùng trong kiểm thử để thay nguồn dữ liệu.
  final Future<TickLoad> Function(String symbol, void Function(int, int) onProgress)? loader;
  final Future<List<Tick>> Function(String symbol, List<Tick> known)? refresher;
  const ActiveFlow(this.symbol, {super.key, this.loader, this.refresher});

  @override
  State<ActiveFlow> createState() => _ActiveFlowState();
}

class _ActiveFlowState extends State<ActiveFlow> {
  List<Tick>? _ticks;
  String _day = '';
  bool _complete = true, _loading = true;
  String? _error;
  int _progress = 0;
  int _minutes = 5;
  int? _hover;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isTradingTime(DateTime.now()) && _ticks != null && !_loading) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final load = await (widget.loader ?? ((s, p) => loadSessionTicks(s, onProgress: p)))(widget.symbol, (n, _) {
        if (mounted) setState(() => _progress = n);
      });
      if (!mounted) return;
      setState(() {
        _ticks = load.ticks;
        _day = load.day;
        _complete = load.complete;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final next = await (widget.refresher ?? ((s, k) => refreshTicks(s, k)))(widget.symbol, _ticks!);
      if (mounted) setState(() => _ticks = next);
    } catch (_) {
      // giữ dữ liệu đang có; lần làm mới sau sẽ thử lại
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ticks = _ticks;
    if (_loading && ticks == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Đang tải lệnh khớp cả phiên… ${_progress == 0 ? '' : '${fmt(_progress, 0)} lệnh'}', style: text.bodyMedium),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(
              'Mỗi lần nguồn chỉ trả 100 lệnh nên cổ phiếu thanh khoản cao có thể mất khoảng nửa phút.',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (ticks == null || ticks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(_error ?? 'Chưa có lệnh khớp nào trong phiên này.', style: text.bodyMedium)),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _loading ? null : _load,
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    final buckets = bucketize(ticks, _minutes);
    final sum = summarize(ticks);
    final act = sum.buyVol + sum.sellVol;
    final buyPct = act == 0 ? 0.0 : sum.buyVol / act * 100;
    Widget stat(String label, String value, String sub, {Color? color}) => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(
            value,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Text(sub, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
    String signed(double dong) => '${dong >= 0 ? '+' : '−'}${_bn(dong)}';
    final up = Tone.up(context), down = Tone.down(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thẻ chỉ số chia đều theo bề rộng biểu đồ bên dưới: 6 cột khi đủ rộng, 3 hoặc 2 cột khi hẹp; thẻ cùng hàng cao bằng nhau.
        LayoutBuilder(
          builder: (context, box) {
            final cards = <Widget>[
              stat(
                'Tiền lớn · lệnh khớp từ ${fmt(sum.bigThreshold / 1e9, 0)} tỷ',
                signed(sum.bigNet),
                'ròng chủ động ${sum.bigNet >= 0 ? '(mua)' : '(bán)'}',
                color: Tone.of(context, sum.bigNet),
              ),
              stat('Mua chủ động lớn', _bn(sum.bigBuyValue), '${sum.bigBuyCount} lệnh', color: up),
              stat('Bán chủ động lớn', _bn(sum.bigSellValue), '${sum.bigSellCount} lệnh', color: down),
              stat('Mua chủ động', _vol(sum.buyVol), '${fmt(buyPct, 0)}% · ${_bn(sum.buyValue)}', color: up),
              stat('Bán chủ động', _vol(sum.sellVol), '${fmt(100 - buyPct, 0)}% · ${_bn(sum.sellValue)}', color: down),
              stat('Khối lượng khớp', _vol(sum.totalVol), 'gồm ${_vol(sum.otherVol)} ATO/ATC'),
            ];
            final cols = box.maxWidth >= 900 ? 6 : (box.maxWidth >= 480 ? 3 : 2);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i += cols) ...[
                  if (i > 0) const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < cols; j++) ...[
                          if (j > 0) const SizedBox(width: 10),
                          Expanded(child: i + j < cards.length ? cards[i + j] : const SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Key(cs.onSurfaceVariant.withValues(alpha: 0.55), 'Khối lượng (cổ phiếu)', filled: true),
            _Key(up, 'Mua chủ động (cột lên)', filled: true),
            _Key(down, 'Bán chủ động (cột xuống)', filled: true),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, minimumSize: WidgetStatePropertyAll(Size(48, 36))),
              segments: const [
                ButtonSegment(value: 1, label: Text('1 phút')),
                ButtonSegment(value: 5, label: Text('5 phút')),
                ButtonSegment(value: 15, label: Text('15 phút')),
              ],
              selected: {_minutes},
              onSelectionChanged: (s) => setState(() {
                _minutes = s.first;
                _hover = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            const padL = 56.0, padR = 8.0;
            void track(Offset p) {
              final w = box.maxWidth - padL - padR;
              final slots = _slots(_day, _minutes);
              final i = ((p.dx - padL) / w * slots).floor().clamp(0, slots - 1);
              if (i != _hover) setState(() => _hover = i);
            }

            return Semantics(
              label:
                  'Biểu đồ khối lượng, mua chủ động và bán chủ động trong phiên. Mua chủ động ${_vol(sum.buyVol)}, bán chủ động ${_vol(sum.sellVol)}.',
              child: MouseRegion(
                onHover: (e) => track(e.localPosition),
                onExit: (_) => setState(() => _hover = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => track(e.localPosition),
                  onHorizontalDragUpdate: (e) => track(e.localPosition),
                  child: CustomPaint(
                    size: Size(box.maxWidth, 300),
                    painter: _FlowPainter(buckets, _day, _minutes, up, down, cs.onSurfaceVariant, cs.outlineVariant, cs.onSurface, _hover),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          _readout(buckets),
          style: text.bodySmall?.copyWith(
            fontWeight: _hover == null ? FontWeight.w400 : FontWeight.w700,
            color: _hover == null ? cs.onSurfaceVariant : null,
          ),
        ),
        if (!_complete)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Phiên có quá nhiều lệnh nên có thể còn thiếu một phần; số liệu chỉ để tham khảo.',
              style: text.bodySmall?.copyWith(color: Tone.flat(context)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Phiên ${_day.split('-').reversed.join('/')} · ${fmt(ticks.length, 0)} lệnh · mua/bán chủ động theo phân loại của nguồn Vietcap, ATO/ATC không phân loại nên không vẽ. Chỉ để tham khảo.',
            style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  String _readout(List<FlowBucket> buckets) {
    final h = _hover;
    if (h == null) return 'Rê chuột hoặc chạm vào biểu đồ để xem từng khoảng thời gian.';
    final start = sessionOpen(_day) + h * _minutes * 60;
    final b = buckets.where((x) => x.start == start).firstOrNull;
    if (b == null) return '${_clock(start)}–${_clock(start + _minutes * 60)}: không có lệnh khớp';
    final net = b.buy - b.sell;
    return '${_clock(start)}–${_clock(start + _minutes * 60)}: khối lượng ${fmt(b.total, 0)} · mua chủ động ${fmt(b.buy, 0)} · bán chủ động ${fmt(b.sell, 0)} · ròng ${net >= 0 ? '+' : '−'}${fmt(net.abs(), 0)}';
  }
}

/// 09:00 giờ Việt Nam của ngày [day], giây epoch.
int sessionOpen(String day) {
  final d = DateTime.parse(day.isEmpty ? vnDate(DateTime.now().millisecondsSinceEpoch ~/ 1000) : day);
  return DateTime.utc(d.year, d.month, d.day, 2).millisecondsSinceEpoch ~/ 1000;
}

/// Số khoảng thời gian trong phiên 09:00–15:00.
int _slots(String day, int minutes) => (360 / minutes).ceil();

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  final bool filled;
  const _Key(this.color, this.label, {this.filled = false});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
    ],
  );
}

class _FlowPainter extends CustomPainter {
  final List<FlowBucket> buckets;
  final String day;
  final int minutes;
  final Color up, down, muted, grid, strong;
  final int? hover;
  _FlowPainter(this.buckets, this.day, this.minutes, this.up, this.down, this.muted, this.grid, this.strong, this.hover);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 56.0, padR = 8.0, padB = 22.0, gap = 14.0;
    final w = size.width - padL - padR;
    final slots = _slots(day, minutes);
    final open = sessionOpen(day);
    final volH = (size.height - padB - gap) * 0.38;
    final flowTop = volH + gap;
    final flowH = size.height - padB - flowTop;
    final slotW = w / slots;
    final barW = math.max(slotW * 0.7, 1.0);

    void txt(String s, Offset at, {bool right = false, bool center = false, Color? color, bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontSize: 11, color: color ?? muted, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(right ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx), at.dy - tp.height / 2));
    }

    final maxTotal = buckets.fold<double>(1, (m, b) => math.max(m, b.buy + b.sell));
    final maxSide = buckets.fold<double>(1, (m, b) => math.max(m, math.max(b.buy, b.sell)));
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    String axis(double v) => v >= 1e6 ? '${fmt(v / 1e6, 1)}tr' : (v >= 1e3 ? '${fmt(v / 1e3, 0)}k' : fmt(v, 0));

    // Khung khối lượng (trên)
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = volH - volH * f;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gp);
      txt(axis(maxTotal * f), Offset(padL - 6, y), right: true);
    }
    txt('Khối lượng', const Offset(padL + 4, 6), bold: true);
    // Khung mua/bán chủ động (dưới): 0 ở giữa
    final mid = flowTop + flowH / 2;
    for (final f in const [-1.0, 0.0, 1.0]) {
      final y = mid - f * flowH / 2;
      canvas.drawLine(
        Offset(padL, y),
        Offset(padL + w, y),
        Paint()
          ..color = f == 0 ? muted.withValues(alpha: 0.6) : grid
          ..strokeWidth = 1,
      );
      txt('${f < 0 ? '−' : ''}${axis(maxSide * f.abs())}', Offset(padL - 6, y), right: true);
    }
    txt('Mua chủ động ▲ / Bán chủ động ▼', Offset(padL + 4, flowTop + 8), bold: true);

    for (final b in buckets) {
      final i = ((b.start - open) / (minutes * 60)).floor();
      if (i < 0 || i >= slots) continue;
      final x = padL + i * slotW + (slotW - barW) / 2;
      final tv = (b.buy + b.sell) / maxTotal * volH;
      canvas.drawRect(Rect.fromLTWH(x, volH - tv, barW, tv), Paint()..color = muted.withValues(alpha: hover == i ? 0.9 : 0.55));
      final bh = b.buy / maxSide * flowH / 2, sh = b.sell / maxSide * flowH / 2;
      canvas.drawRect(Rect.fromLTWH(x, mid - bh, barW, bh), Paint()..color = up.withValues(alpha: hover == i ? 1 : 0.8));
      canvas.drawRect(Rect.fromLTWH(x, mid, barW, sh), Paint()..color = down.withValues(alpha: hover == i ? 1 : 0.8));
    }
    // Trục giờ
    for (var m = 0; m <= 360; m += 60) {
      final x = padL + m / 360 * w;
      txt('${(9 + m ~/ 60).toString().padLeft(2, '0')}:00', Offset(x, size.height - 8), center: true);
    }
    if (hover != null) {
      final x = padL + hover! * slotW + slotW / 2;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height - padB),
        Paint()
          ..color = strong.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowPainter o) => o.buckets != buckets || o.hover != hover || o.minutes != minutes || o.up != up || o.down != down;
}
