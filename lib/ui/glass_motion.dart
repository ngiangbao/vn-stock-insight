// Chuyển động kiểu Liquid Glass khi đổi tab, theo hành vi của thanh tab trên iOS/macOS 26 trở lên:
// - ô chọn là một "thấu kính" kính trượt giữa các tab bằng lò xo, giãn ra theo hướng di chuyển rồi co lại (squash & stretch);
// - bấm hoặc kéo thì thấu kính nổi lên (to hơn, sáng hơn) và phóng đại nhẹ nền phía sau như khúc xạ; kéo ngang để chọn tab dưới ngón tay;
// - nội dung mới hiện ra mờ rồi nét dần, hơi phóng nhẹ, thay vì đổi cứng.
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

/// Thanh tab kiểu kính: viên kính chứa các tab, thấu kính trượt theo tab đang chọn; bấm để chọn, kéo ngang để chọn tab dưới ngón tay.
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
  int? _drag; // tab đang nằm dưới ngón tay khi kéo
  bool _down = false;

  static const _pad = 4.0, _itemPad = 18.0, _height = 40.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.controller ?? DefaultTabController.of(context);
    if (!identical(c, _c)) {
      _c?.removeListener(_onTab);
      _c = c..addListener(_onTab);
    }
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c?.removeListener(_onTab);
    super.dispose();
  }

  String _label(Tab t) => t.text ?? '';

  List<double> _widths(BuildContext context) {
    final style = const TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final scaler = MediaQuery.textScalerOf(context);
    return [
      for (final t in widget.tabs)
        math.max(
          56.0,
          (TextPainter(
                text: TextSpan(text: _label(t), style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout()).width +
              _itemPad * 2,
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

  @override
  Widget build(BuildContext context) {
    final g = GlassScope.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final widths = _widths(context);
    final selected = _drag ?? _c!.index;
    var left = _pad;
    final lefts = <double>[];
    for (final w in widths) {
      lefts.add(left);
      left += w;
    }
    final total = left + _pad;
    final target = Rect.fromLTWH(lefts[selected], _pad, widths[selected], _height - _pad * 2);
    final radius = BorderRadius.circular(_height / 2);

    final pill = SizedBox(
      width: total,
      height: _height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() {
          _down = true;
          _drag = _c!.index;
        }),
        onHorizontalDragUpdate: (d) {
          final i = _indexAt(d.localPosition.dx, widths);
          if (i != _drag) setState(() => _drag = i);
        },
        onHorizontalDragEnd: (_) {
          final i = _drag;
          setState(() {
            _down = false;
            _drag = null;
          });
          if (i != null) _c!.animateTo(i);
        },
        onHorizontalDragCancel: () => setState(() {
          _down = false;
          _drag = null;
        }),
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
                radius: BorderRadius.circular((_height - _pad * 2) / 2),
                brightness: dark ? Brightness.dark : Brightness.light,
                lifted: _down,
              ),
              for (var i = 0; i < widget.tabs.length; i++)
                Positioned(
                  left: lefts[i],
                  top: _pad,
                  width: widths[i],
                  height: _height - _pad * 2,
                  child: Semantics(
                    button: true,
                    selected: i == _c!.index,
                    label: _label(widget.tabs[i]),
                    child: ExcludeSemantics(
                      child: InkResponse(
                        radius: 26,
                        highlightShape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(18),
                        onTapDown: (_) => setState(() => _down = true),
                        onTapCancel: () => setState(() => _down = false),
                        onTap: () {
                          setState(() => _down = false);
                          _c!.animateTo(i);
                        },
                        child: Center(
                          child: Text(
                            _label(widget.tabs[i]),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
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
    );

    return SizedBox(
      height: kTextTabBarHeight,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: (kTextTabBarHeight - _height) / 2),
        child: pill,
      ),
    );
  }
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

/// Nội dung mới hiện ra khi [trigger] đổi: kiểu Liquid Glass mờ rồi nét dần và hơi phóng nhẹ, Cổ điển chỉ mờ dần.
/// Lúc đứng yên không thêm lớp lọc nào nên không tốn hiệu năng. Giảm chuyển động thì không hoạt ảnh.
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.playOnMount && !_mounted) {
      _mounted = true;
      if (!MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0.15);
    }
    _mounted = true;
  }

  bool _mounted = false;

  @override
  void didUpdateWidget(GlassReveal old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0.15);
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
    final glass = GlassScope.maybeOf(context) != null;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        Widget out = child!;
        if (glass && _c.isAnimating) {
          final t = Curves.easeOutCubic.transform(_c.value);
          final sigma = (1 - t) * 7;
          out = Transform.scale(
            scale: 0.985 + 0.015 * t,
            child: sigma > 0.05
                ? ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                    child: out,
                  )
                : out,
          );
        }
        return FadeTransition(opacity: _fade, child: out);
      },
    );
  }
}
