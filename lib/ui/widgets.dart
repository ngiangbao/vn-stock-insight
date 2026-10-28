import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../state.dart';

/// Màu tăng/giảm/đứng giá, đổi theo chế độ sáng/tối.
class Tone {
  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color up(BuildContext c) => _dark(c) ? const Color(0xFF3ECF7F) : const Color(0xFF0F8A4A);
  static Color down(BuildContext c) => _dark(c) ? const Color(0xFFFF6B62) : const Color(0xFFC8322B);
  static Color flat(BuildContext c) => _dark(c) ? const Color(0xFFE2B448) : const Color(0xFFB07D10);
  static Color of(BuildContext c, num? v) => v == null || v == 0 ? flat(c) : (v > 0 ? up(c) : down(c));
  static Color stance(BuildContext c, String? s) => switch (s) {
        'Tích cực' => up(c),
        'Tiêu cực' => down(c),
        _ => flat(c),
      };
}

String fmt(num? n, [int digits = 2]) {
  if (n == null) return '–';
  var s = n.toStringAsFixed(digits);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final int = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return parts.length > 1 ? '$int,${parts[1]}' : int;
}

String _two(int x) => x.toString().padLeft(2, '0');
String _stamp(DateTime v) => '${_two(v.hour)}:${_two(v.minute)} ${_two(v.day)}/${_two(v.month)}/${v.year}';

/// Giờ Việt Nam: dùng cho dữ liệu thị trường và tin tức.
String timeVN(DateTime t) => _stamp(t.toUtc().add(const Duration(hours: 7)));

/// Giờ theo đồng hồ máy người dùng.
String timeLocal(DateTime t) => _stamp(t.toLocal());

class Pct extends StatelessWidget {
  final num? value;
  final TextStyle? style;
  const Pct(this.value, {super.key, this.style});

  @override
  Widget build(BuildContext context) => Text(
        value == null ? '–' : '${value! >= 0 ? '+' : ''}${fmt(value)}%',
        style: (style ?? const TextStyle()).copyWith(color: Tone.of(context, value), fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  const Tag(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class Sparkline extends StatelessWidget {
  final List<double> values;
  final double height;
  const Sparkline(this.values, {super.key, this.height = 44});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    final color = values.last >= values.first ? Tone.up(context) : Tone.down(context);
    return SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color)));
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final min = values.reduce((a, b) => a < b ? a : b), max = values.reduce((a, b) => a > b ? a : b);
    final span = max - min == 0 ? 1 : max - min;
    const pad = 3.0;
    final path = Path();
    late Offset last;
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * (size.width - pad * 2) + pad;
      final y = size.height - (values[i] - min) / span * (size.height - pad * 2) - pad;
      last = Offset(x, y);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    // Vùng tô chuyển màu dưới đường giá
    final fill = Path.from(path)
      ..lineTo(last.dx, size.height)
      ..lineTo(pad, size.height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
              Offset.zero, Offset(0, size.height), [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)]));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true);
    canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// Một cặp nhãn – giá trị nhỏ.
class Kv extends StatelessWidget {
  final String label;
  final Widget value;
  const Kv(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.w600), child: value),
      ]);
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class Bullets extends StatelessWidget {
  final List? items;
  const Bullets(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    if (items == null || items!.isEmpty) return const Text('–');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final i in items!)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(i.toString())),
          ]),
        ),
    ]);
  }
}

/// Khung trang có tiêu đề, nút làm mới và nội dung cuộn.
class PageFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  const PageFrame({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.onRefresh,
    this.maxWidth = 1100,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          if (state.updatedAt != null)
            Text('Cập nhật lúc ${timeLocal(state.updatedAt!)}', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          ...actions,
          if (onRefresh != null)
            state.loading
                ? const Padding(padding: EdgeInsets.all(16), child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Làm mới dữ liệu'),
        ],
      ),
      body: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
    );
  }
}

/// Cỡ giao diện. [manual] = null: tự co giãn nhẹ theo chiều rộng cửa sổ (chuẩn [designWidth],
/// trong khoảng [minAuto]–[maxAuto]); có giá trị: dùng đúng tỉ lệ đó (0.8 = 80%).
/// Màn hình hẹp (điện thoại) ở chế độ tự động giữ nguyên kích thước gốc.
class AutoScale extends StatelessWidget {
  static const designWidth = 1600.0, minAuto = 0.85, maxAuto = 1.15;
  static const presets = [0.8, 0.9, 1.0, 1.1, 1.25];
  final bool enabled;
  final double? manual;
  final Widget child;
  const AutoScale({super.key, required this.enabled, this.manual, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final double s;
    if (manual != null) {
      s = manual!;
    } else {
      if (!enabled || width < 600) return child;
      s = (width / designWidth).clamp(minAuto, maxAuto);
    }
    if ((s - 1).abs() < 0.02) return child;
    final logical = mq.size / s;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: logical,
        child: MediaQuery(
          data: mq.copyWith(
            size: logical,
            padding: mq.padding / s,
            viewPadding: mq.viewPadding / s,
            viewInsets: mq.viewInsets / s,
          ),
          child: child,
        ),
      ),
    );
  }
}

const disclaimer ='Phân tích do AI tạo ra, có thể sai, chỉ mang tính tham khảo, không phải khuyến nghị đầu tư.';

/// Cột của [FlexTable]: các cột chia đều toàn bộ chiều rộng theo tỉ lệ [flex], không bao giờ chồng lấn nhau.
class FlexCol {
  final String label;
  final int flex;
  final Alignment align;
  final VoidCallback? onSort;
  final bool? ascending; // null: cột này không đang được sắp xếp
  const FlexCol(this.label, this.flex, {this.align = Alignment.centerLeft, this.onSort, this.ascending});
}

class FlexRow {
  final List<Widget> cells;
  final VoidCallback? onTap;
  const FlexRow(this.cells, {this.onTap});
}

/// Bảng ngang trải hết chiều rộng: mỗi cột có chiều rộng tỉ lệ, đệm hai bên 10 px để chữ không dính nhau.
/// Khi cửa sổ hẹp hơn [minWidth], bảng giữ nguyên chiều rộng tối thiểu và cuộn ngang.
class FlexTable extends StatelessWidget {
  final List<FlexCol> columns;
  final List<FlexRow> rows;
  final double minWidth;
  final double rowHeight;
  const FlexTable({super.key, required this.columns, required this.rows, this.minWidth = 1100, this.rowHeight = 64});

  static const _pad = EdgeInsets.symmetric(horizontal: 10);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final head = Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700);

    Widget line(List<Widget> cells, {double? height}) => Row(
      children: [
        for (final (i, c) in cells.indexed)
          Expanded(
            flex: columns[i].flex,
            child: Padding(
              padding: _pad,
              child: Align(alignment: columns[i].align, child: c),
            ),
          ),
      ],
    );

    Widget header() => Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: line([
        for (final c in columns)
          c.onSort == null
              ? Text(c.label, style: head, maxLines: 2, overflow: TextOverflow.ellipsis)
              : InkWell(
                  onTap: c.onSort,
                  borderRadius: BorderRadius.circular(6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(c.label, style: head, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        if (c.ascending != null)
                          Icon(c.ascending! ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: cs.primary),
                      ],
                    ),
                  ),
                ),
      ]),
    );

    Widget row(FlexRow r) => InkWell(
      onTap: r.onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: line(r.cells),
      ),
    );

    final table = Column(children: [header(), for (final r in rows) row(r)]);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= minWidth
          ? table
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth, child: table),
            ),
    );
  }
}
