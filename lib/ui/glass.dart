import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Màu chữ dùng để kiểm tra tương phản trên kính (khớp token của app trong lib/main.dart).
class GlassInk {
  static const lightText = Color(0xFF1C2822), lightMuted = Color(0xFF55615A), lightPrimary = Color(0xFF1E5A3F);
  static const darkText = Color(0xFFE8F0EB), darkMuted = Color(0xFFA7B6AD), darkPrimary = Color(0xFF7FD1A4);
}

/// Nền Liquid Glass: các màu nền đỉnh gradient và màu "đốm sáng" lớn phía sau kính.
/// Các màu này cũng là các điểm xấu nhất khi tính tương phản chữ.
class GlassPalette {
  static const lightBg = [Color(0xFFE6EEFB), Color(0xFFF0E6FA), Color(0xFFFBE8EE)];
  static const darkBg = [Color(0xFF0A1220), Color(0xFF191033), Color(0xFF0D2735)];
  static const lightBlobs = [Color(0xFFB4D3FF), Color(0xFFD9C2FF), Color(0xFFFFC9D8)];
  static const darkBlobs = [Color(0xFF2B4C8C), Color(0xFF4A2D8C), Color(0xFF1B6B7A)];
  static const lightFill = Color(0xFFFFFFFF);
  static const darkFill = Color(0xFF111B28);

  static List<Color> samples(Brightness b) => b == Brightness.dark ? [...darkBg, ...darkBlobs] : [...lightBg, ...lightBlobs];
}

double _lum(Color c) => c.computeLuminance();

/// Tỉ lệ tương phản WCAG giữa hai màu đặc.
double contrastRatio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Thông số kính suy ra từ vị trí thanh trượt (0..1) và sáng/tối.
class GlassTokens {
  /// Sigma blur (px). 0 nghĩa là tắt hẳn BackdropFilter.
  final double sigma;

  /// Độ đục lớp kính của thẻ trên nền (0..1).
  final double cardAlpha;

  /// Độ đục của thanh điều hướng/tấm nổi (không thấp hơn thẻ).
  final double panelAlpha;

  /// Độ đục của hộp thoại, menu, bảng chọn: nằm trên nội dung nên không thấp hơn 0,9.
  final double overlayAlpha;
  final Color fill;
  final Brightness brightness;

  const GlassTokens({
    required this.sigma,
    required this.cardAlpha,
    required this.panelAlpha,
    required this.overlayAlpha,
    required this.fill,
    required this.brightness,
  });

  static const double maxSigma = 40;

  /// Độ đục nhỏ nhất để chữ chính, chữ phụ và màu nhấn đều đạt ≥ 4,5:1 trên mọi điểm nền xấu nhất.
  static final _minCache = <Brightness, double>{};
  static double minAlpha(Brightness b) => _minCache.putIfAbsent(b, () {
    final dark = b == Brightness.dark;
    final fill = dark ? GlassPalette.darkFill : GlassPalette.lightFill;
    final inks = dark
        ? [GlassInk.darkText, GlassInk.darkMuted, GlassInk.darkPrimary]
        : [GlassInk.lightText, GlassInk.lightMuted, GlassInk.lightPrimary];
    for (var a = 0.0; a <= 1.0001; a += 0.01) {
      if (worstContrast(b, a, fill: fill, inks: inks) >= 4.55) return a;
    }
    return 1.0;
  });

  /// Tương phản thấp nhất của các màu chữ trên kính độ đục [alpha] đặt trên các màu nền xấu nhất.
  static double worstContrast(Brightness b, double alpha, {Color? fill, List<Color>? inks}) {
    final dark = b == Brightness.dark;
    fill ??= dark ? GlassPalette.darkFill : GlassPalette.lightFill;
    inks ??= dark
        ? [GlassInk.darkText, GlassInk.darkMuted, GlassInk.darkPrimary]
        : [GlassInk.lightText, GlassInk.lightMuted, GlassInk.lightPrimary];
    var worst = double.infinity;
    for (final bg in GlassPalette.samples(b)) {
      final surface = Color.alphaBlend(fill.withValues(alpha: alpha), bg);
      for (final ink in inks) {
        worst = math.min(worst, contrastRatio(ink, surface));
      }
    }
    return worst;
  }

  /// [blur] 0..1: 0 = trong và nhẹ (không blur), 1 = mờ và dày.
  /// [reduceTransparency] (độ tương phản cao): bỏ blur, kính gần đặc. [reduceMotion]: giảm một nửa blur.
  factory GlassTokens.of(Brightness b, double blur, {bool reduceTransparency = false, bool reduceMotion = false}) {
    final t = blur.clamp(0.0, 1.0).toDouble();
    final floor = minAlpha(b);
    var sigma = t * maxSigma;
    if (reduceMotion) sigma *= 0.5;
    var card = math.max(ui.lerpDouble(0.46, 0.86, t)!, floor);
    if (reduceTransparency) {
      sigma = 0;
      card = math.max(card, 0.96);
    }
    return GlassTokens(
      sigma: sigma,
      cardAlpha: card,
      panelAlpha: math.min(1.0, card + 0.04),
      overlayAlpha: math.max(0.92, card),
      fill: b == Brightness.dark ? GlassPalette.darkFill : GlassPalette.lightFill,
      brightness: b,
    );
  }
}

/// Cung cấp thông số kính cho cây widget (null = kiểu Cổ điển, không có kính).
class GlassScope extends InheritedWidget {
  final GlassTokens? tokens;
  const GlassScope({super.key, required this.tokens, required super.child});

  static GlassTokens? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.tokens;

  @override
  bool updateShouldNotify(GlassScope old) =>
      old.tokens?.sigma != tokens?.sigma ||
      old.tokens?.cardAlpha != tokens?.cardAlpha ||
      old.tokens?.brightness != tokens?.brightness ||
      (old.tokens == null) != (tokens == null);
}

/// Nền Liquid Glass: gradient lạnh cùng vài đốm sáng lớn, vẽ một lần (RepaintBoundary) phía sau toàn app.
class GlassBackground extends StatelessWidget {
  final Brightness brightness;
  final Widget child;
  const GlassBackground({super.key, required this.brightness, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? GlassPalette.darkBg : GlassPalette.lightBg;
    final blobs = dark ? GlassPalette.darkBlobs : GlassPalette.lightBlobs;
    Widget blob(Alignment at, Color c, double size) => Align(
      alignment: at,
      child: FractionallySizedBox(
        widthFactor: size,
        heightFactor: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: 0.9), c.withValues(alpha: 0)]),
          ),
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                blob(const Alignment(-0.9, -0.8), blobs[0], 0.7),
                blob(const Alignment(0.95, -0.2), blobs[1], 0.6),
                blob(const Alignment(-0.2, 1.0), blobs[2], 0.65),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Tấm kính nổi (thanh icon dọc, thanh điều hướng dưới): blur nền nếu sigma > 0, nền bán trong suốt, viền sáng mảnh,
/// highlight phản chiếu ở mép trên và bóng mềm. Nền blur hỏng/không hỗ trợ vẫn đọc được nhờ nền bán trong suốt.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  const GlassPanel({super.key, required this.child, this.radius = const BorderRadius.all(Radius.circular(28))});

  @override
  Widget build(BuildContext context) {
    final g = GlassScope.maybeOf(context);
    if (g == null) return child;
    final dark = g.brightness == Brightness.dark;
    final rim = (dark ? Colors.white : Colors.white).withValues(alpha: dark ? 0.16 : 0.85);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: g.fill.withValues(alpha: g.panelAlpha),
        border: Border.all(color: rim, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.07 : 0.35),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.5],
        ),
      ),
      child: child,
    );
    if (g.sigma > 0) {
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: g.sigma, sigmaY: g.sigma),
          child: surface,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: surface,
    );
  }
}
