// Chuyển động kiểu Liquid Glass khi đổi tab, theo hành vi của thanh tab trên iOS/macOS 26 trở lên:
// - ô chọn là một "thấu kính" kính trượt giữa các tab bằng lò xo, giãn ra theo hướng di chuyển rồi co lại (squash & stretch);
// - bấm hoặc kéo thì thấu kính nổi lên (to hơn, sáng hơn) và phóng đại nhẹ nền phía sau như khúc xạ; kéo ngang để chọn tab dưới ngón tay;
// - nội dung mới hiện ra mờ dần, hơi phóng nhẹ, thay vì đổi cứng (chỉ dùng biến đổi/độ mờ do GPU ghép lớp, không lọc nhòe cả trang).
// Tôn trọng chế độ giảm chuyển động của hệ thống (nhảy thẳng tới đích, không hoạt ảnh). Kiểu Cổ điển không dùng các lớp này.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'glass.dart';

/// Lò xo của thấu kính: hơi dưới tới hạn nên vọt nhẹ qua đích rồi về, giống cảm giác của thanh tab hệ thống.
const lensSpring = SpringDescription(mass: 1, stiffness: 420, damping: 25);

/// Vẽ một thấu kính kính: phóng đại nhẹ nền phía sau, nền sáng bán trong suốt, ánh phản chiếu ở góc trên trái, viền sáng và bóng mềm.
/// [lift] từ 0 đến 1: mức "nổi lên" khi đang bấm hoặc kéo.
class GlassLens extends StatelessWidget {
  final BorderRadius radius;
  final double lift;
  final Brightness brightness;
  final Widget? child;
  const GlassLens({super.key, required this.radius, required this.brightness, this.lift = 0, this.child});

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final tint = Colors.white.withValues(alpha: (dark ? 0.12 : 0.34) + 0.10 * lift);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: (dark ? 0.35 : 0.14) + 0.08 * lift),
            blurRadius: 14 + 8 * lift,
            offset: Offset(0, 4 + 3 * lift),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: LayoutBuilder(
          builder: (context, box) {
            // Khúc xạ giả: phóng đại phần nền nằm dưới thấu kính quanh tâm của nó, kèm blur rất nhẹ
            final s = 1.07 + 0.06 * lift;
            final cx = box.maxWidth / 2, cy = box.maxHeight / 2;
            final m = Matrix4.identity()
              ..translateByDouble(cx, cy, 0, 1)
              ..scaleByDouble(s, s, 1, 1)
              ..translateByDouble(-cx, -cy, 0, 1);
            return BackdropFilter(
              filter: ui.ImageFilter.compose(outer: ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2), inner: ui.ImageFilter.matrix(m.storage)),
              child: CustomPaint(painter: _LensPainter(radius, tint, dark, lift), child: child),
            );
          },
        ),
      ),
    );
  }
}

class _LensPainter extends CustomPainter {
  final BorderRadius radius;
  final Color tint;
  final bool dark;
  final double lift;
  _LensPainter(this.radius, this.tint, this.dark, this.lift);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    canvas.drawRRect(rrect, Paint()..color = tint);
    // Ánh phản chiếu mềm ở góc trên trái
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(Offset(size.width * 0.22, size.height * 0.05), size.shortestSide * 1.1, [
          Colors.white.withValues(alpha: (dark ? 0.22 : 0.55) + 0.1 * lift),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    // Quầng sáng yếu hơn ở mép dưới phải (ánh sáng khúc xạ ngược)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(Offset(size.width * 0.85, size.height * 1.05), size.shortestSide * 0.9, [
          Colors.white.withValues(alpha: dark ? 0.10 : 0.22),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
    // Viền: sáng ở trên trái và dưới phải, gần như trong ở giữa
    canvas.drawRRect(
      rrect.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            Colors.white.withValues(alpha: dark ? 0.55 : 0.95),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: dark ? 0.30 : 0.7),
          ],
          const [0, 0.55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_LensPainter o) => o.tint != tint || o.dark != dark || o.lift != lift || o.radius != radius;
}

/// Thấu kính trượt tới [target] (toạ độ của Stack cha) bằng lò xo, giãn theo hướng di chuyển. Đặt trong Stack, không cần Positioned.
class GlassLensMover extends StatefulWidget {
  final Rect target;
  final BorderRadius radius;
  final Brightness brightness;

  /// Đang bấm/kéo: thấu kính nổi lên.
  final bool lifted;
  final bool visible;
  const GlassLensMover({
    super.key,
    required this.target,
    required this.radius,
    required this.brightness,
    this.lifted = false,
    this.visible = true,
  });

  @override
  State<GlassLensMover> createState() => _GlassLensMoverState();
}

class _GlassLensMoverState extends State<GlassLensMover> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController.unbounded(vsync: this);
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late Rect _from = widget.target, _to = widget.target;

  Rect get _rect => Rect.lerp(_from, _to, _move.value)!;

  @override
  void initState() {
    super.initState();
    _move.value = 1;
    if (widget.lifted) _lift.value = 1;
  }

  @override
  void didUpdateWidget(GlassLensMover old) {
    super.didUpdateWidget(old);
    if (widget.target != old.target) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _from = _to = widget.target;
        _move.value = 1;
      } else {
        _from = _rect;
        _to = widget.target;
        _move.value = 0;
        _move.animateWith(SpringSimulation(lensSpring, 0, 1, 0));
      }
    }
    if (widget.lifted != old.lifted && !MediaQuery.disableAnimationsOf(context)) {
      widget.lifted ? _lift.forward() : _lift.reverse();
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_move, _lift]),
    builder: (context, _) {
      final base = _rect;
      final dist = (_to.center - _from.center).distance;
      final horizontal = (_to.center - _from.center).dx.abs() >= (_to.center - _from.center).dy.abs();
      // Tốc độ px/giây; giãn tối đa ~22% theo hướng chạy và co lại ~10% theo hướng vuông góc
      final speed = _move.isAnimating ? (_move.velocity.abs() * dist) : 0.0;
      final k = (speed / 2200).clamp(0.0, 0.22);
      final lift = Curves.easeOutCubic.transform(_lift.value);
      final grow = 1 + 0.07 * lift;
      final w = base.width * (horizontal ? 1 + k : 1 - k * 0.3) * grow;
      final h = base.height * (horizontal ? 1 - k * 0.3 : 1 + k) * grow;
      final rect = Rect.fromCenter(center: base.center, width: w, height: h);
      return Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: widget.visible ? 1 : 0,
            child: GlassLens(radius: widget.radius, brightness: widget.brightness, lift: lift),
          ),
        ),
      );
    },
  );
}

/// Viên kính chứa một dãy lựa chọn: thấu kính trượt tới lựa chọn đang chọn; bấm để chọn, kéo ngang để chọn dưới ngón tay.
/// Dùng chung cho thanh tab, nút chọn khu vực và các nút khung thời gian. [expand] chia đều chiều rộng cho các lựa chọn.
class GlassPill extends StatefulWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;
  final bool expand;
  final double itemPad, minItem, fontSize;
  const GlassPill({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.height = 40,
    this.expand = false,
    this.itemPad = 18,
    this.minItem = 56,
    this.fontSize = 14,
  });

  @override
  State<GlassPill> createState() => _GlassPillState();
}

class _GlassPillState extends State<GlassPill> {
  int? _drag; // lựa chọn đang nằm dưới ngón tay khi kéo
  bool _down = false;

  // Đo chữ tốn kém nên chỉ đo lại khi nhãn, cỡ chữ hoặc tỉ lệ chữ đổi
  List<double>? _natural;
  String _naturalKey = '';

  static const _pad = 4.0;

  List<double> _naturalWidths(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final key = '${widget.labels.join('\u0001')}|${widget.fontSize}|${widget.itemPad}|${widget.minItem}|${scaler.scale(10)}';
    if (_natural != null && key == _naturalKey) return _natural!;
    final style = TextStyle(fontSize: widget.fontSize, fontWeight: FontWeight.w700);
    _naturalKey = key;
    return _natural = [
      for (final l in widget.labels)
        math.max(
          widget.minItem,
          (TextPainter(
                text: TextSpan(text: l, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout()).width +
              widget.itemPad * 2,
        ),
    ];
  }

  int _indexAt(double dx, List<double> widths) {
    var x = _pad;
    for (var i = 0; i < widths.length; i++) {
      if (dx < x + widths[i]) return i;
      x += widths[i];
    }
    return widths.length - 1;
  }

  void _clear() => setState(() {
    _down = false;
    _drag = null;
  });

  @override
  Widget build(BuildContext context) {
    if (!widget.expand) {
      final widths = _naturalWidths(context);
      final total = widths.fold<double>(_pad * 2, (a, b) => a + b);
      // Dãy nhãn dài hơn chỗ chứa (điện thoại 375 px) thì cuộn ngang thay vì tràn
      return LayoutBuilder(
        builder: (context, box) => box.hasBoundedWidth && total > box.maxWidth
            ? SizedBox(
                width: box.maxWidth,
                height: widget.height,
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _build(context, widths)),
              )
            : _build(context, widths),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.hasBoundedWidth ? (box.maxWidth - _pad * 2) / widget.labels.length : _naturalWidths(context).reduce(math.max);
        return _build(context, List.filled(widget.labels.length, w));
      },
    );
  }

  Widget _build(BuildContext context, List<double> widths) {
    final g = GlassScope.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final h = widget.height;
    final selected = (_drag ?? widget.selected).clamp(0, widths.length - 1);
    var left = _pad;
    final lefts = <double>[];
    for (final w in widths) {
      lefts.add(left);
      left += w;
    }
    final total = left + _pad;
    final target = Rect.fromLTWH(lefts[selected], _pad, widths[selected], h - _pad * 2);
    final radius = BorderRadius.circular(h / 2);

    return SizedBox(
      width: total,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() {
          _down = true;
          _drag = widget.selected;
        }),
        onHorizontalDragUpdate: (d) {
          final i = _indexAt(d.localPosition.dx, widths);
          if (i != _drag) setState(() => _drag = i);
        },
        onHorizontalDragEnd: (_) {
          final i = _drag;
          _clear();
          if (i != null) widget.onSelect(i);
        },
        onHorizontalDragCancel: _clear,
        // Viên kính và thấu kính nằm trong một lớp riêng: lúc trượt chỉ lớp này vẽ lại, phần còn lại của trang không bị kéo theo
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: (g?.fill ?? cs.surface).withValues(alpha: dark ? 0.32 : 0.38),
              border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.8)),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GlassLensMover(
                  target: target,
                  radius: BorderRadius.circular((h - _pad * 2) / 2),
                  brightness: dark ? Brightness.dark : Brightness.light,
                  lifted: _down,
                ),
                for (var i = 0; i < widget.labels.length; i++)
                  Positioned(
                    left: lefts[i],
                    top: _pad,
                    width: widths[i],
                    height: h - _pad * 2,
                    child: Semantics(
                      button: true,
                      selected: i == widget.selected,
                      label: widget.labels[i],
                      child: ExcludeSemantics(
                        child: InkResponse(
                          radius: 26,
                          highlightShape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(18),
                          onTapDown: (_) => setState(() => _down = true),
                          onTapCancel: () => setState(() => _down = false),
                          onTap: () {
                            setState(() => _down = false);
                            widget.onSelect(i);
                          },
                          child: Center(
                            child: Text(
                              widget.labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.fontSize,
                                fontWeight: FontWeight.w700,
                                color: i == selected ? cs.primary : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh tab kiểu kính: [GlassPill] đặt theo [TabController], cuộn ngang khi hẹp.
class GlassTabBar extends StatefulWidget implements PreferredSizeWidget {
  final TabController? controller;
  final List<Tab> tabs;
  const GlassTabBar({super.key, this.controller, required this.tabs});

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  TabController? _c;
  int _index = 0;

  static const _height = 40.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.controller ?? DefaultTabController.of(context);
    if (!identical(c, _c)) {
      _c?.removeListener(_onTab);
      _c = c..addListener(_onTab);
      _index = c.index;
    }
  }

  // Bộ điều khiển báo mỗi khung hình trong lúc chuyển; chỉ dựng lại khi chỉ số thật sự đổi
  void _onTab() {
    if (mounted && _c!.index != _index) setState(() => _index = _c!.index);
  }

  @override
  void dispose() {
    _c?.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kTextTabBarHeight,
    width: double.infinity,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: (kTextTabBarHeight - _height) / 2),
      child: GlassPill(
        labels: [for (final t in widget.tabs) t.text ?? ''],
        selected: _index,
        height: _height,
        onSelect: (i) => _c!.animateTo(i),
      ),
    ),
  );
}

/// Thanh tab của app: kiểu Liquid Glass dùng [GlassTabBar], kiểu Cổ điển giữ nguyên TabBar của Material.
class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController? controller;
  final List<Tab> tabs;
  const AppTabBar({super.key, this.controller, required this.tabs});

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) => GlassScope.maybeOf(context) == null
      ? TabBar(controller: controller, isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs)
      : GlassTabBar(controller: controller, tabs: tabs);
}

/// Nút chọn một trong vài giá trị: kiểu Liquid Glass dùng [GlassPill] có thấu kính trượt, kiểu Cổ điển giữ [SegmentedButton] của Material.
/// [expand] chia đều chiều rộng khả dụng (như dải khu vực); mặc định rộng vừa nhãn (như khung thời gian).
class AppSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expand;
  final double height;

  /// Kiểu Cổ điển vẽ thành hàng chip (ChoiceChip) thay vì SegmentedButton, để giữ nguyên hình dạng cũ của chỗ đó.
  final bool chips;
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.expand = false,
    this.height = 44,
    this.chips = false,
  });

  @override
  Widget build(BuildContext context) {
    if (GlassScope.maybeOf(context) == null && chips) {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (final (v, l) in options) ChoiceChip(label: Text(l), selected: v == selected, onSelected: (_) => onChanged(v))],
      );
    }
    if (GlassScope.maybeOf(context) == null) {
      return SegmentedButton<T>(
        showSelectedIcon: false,
        expandedInsets: expand ? EdgeInsets.zero : null,
        style: ButtonStyle(
          visualDensity: expand ? null : VisualDensity.compact,
          minimumSize: WidgetStatePropertyAll(Size(expand ? 0 : 48, height)),
          padding: expand ? const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)) : null,
        ),
        segments: [
          for (final (v, l) in options)
            ButtonSegment(
              value: v,
              label: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      );
    }
    final i = options.indexWhere((o) => o.$1 == selected).clamp(0, options.length - 1);
    return GlassPill(
      labels: [for (final (_, l) in options) l],
      selected: i,
      height: height,
      expand: expand,
      itemPad: expand ? 6 : 12,
      minItem: expand ? 0 : 48,
      onSelect: (k) => onChanged(options[k].$1),
    );
  }
}

/// Nội dung mới hiện ra khi [trigger] đổi: mờ dần và hơi phóng nhẹ. Chỉ dùng biến đổi và độ mờ (do GPU ghép lớp, không vẽ lại trang),
/// không làm nhòe cả trang vì lọc nhòe trên vùng lớn là thứ gây giật. Lúc đứng yên không thêm lớp nào. Giảm chuyển động thì không hoạt ảnh.
class GlassReveal extends StatefulWidget {
  final Object? trigger;
  final Widget child;

  /// Phát hiệu ứng ngay khi dựng lần đầu (dùng cho trang vừa được mở lần đầu).
  final bool playOnMount;
  const GlassReveal({super.key, required this.trigger, required this.child, this.playOnMount = false});

  @override
  State<GlassReveal> createState() => _GlassRevealState();
}

class _GlassRevealState extends State<GlassReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<double> _scale = Tween<double>(begin: 0.988, end: 1).animate(_t);
  bool _mounted = false;

  // Trang mới dựng nặng khung hình đầu; bắt đầu hoạt ảnh sau khung đó để không bị nuốt mất đoạn đầu
  void _play() {
    _c.value = 0.15;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.forward(from: 0.15);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.playOnMount && !_mounted && !MediaQuery.disableAnimationsOf(context)) _play();
    _mounted = true;
  }

  @override
  void didUpdateWidget(GlassReveal old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _play();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cấu trúc cây giữ nguyên cả lúc đứng yên để trang bên trong không bị dựng lại (mất trạng thái) khi hoạt ảnh kết thúc
    final glass = GlassScope.maybeOf(context) != null;
    final faded = FadeTransition(
      opacity: _t,
      child: RepaintBoundary(child: widget.child),
    );
    return glass ? ScaleTransition(scale: _scale, child: faded) : faded;
  }
}
