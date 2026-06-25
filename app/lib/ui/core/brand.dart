/// The Cachy brand layer (docs/07, bold-branded direction).
///
/// `theme.dart` is the calm frame that lets *content-visuals* carry attention;
/// this file is the opposite — the small, loud surface that carries *identity*.
/// The brand gradient colors chrome only (capture button, splash, primary CTAs,
/// progress); per-content-type accents (`content_accent.dart`) still color cards.
///
/// Identity = a lowercase `cachy` wordmark + one glyph, "the catch": a rounded
/// bracket that catches a falling reel. Used in the splash, onboarding, the
/// library app bar, and (rasterized) the launcher icon.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  // Signature ramp: electric indigo → violet. Flat seed stays in theme.dart for
  // Material's scheme; the gradient is what reads as "Cachy".
  static const indigo = Color(0xFF5B5BD6);
  static const violet = Color(0xFF7C5CFF);
  static const violetLight = Color(0xFFA38BFF);
  static const ink = Color(0xFF14121F); // brand near-black (splash/dark canvas)

  /// The chrome gradient. Top-left indigo → bottom-right violet.
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, violet],
  );

  /// A slightly brighter variant for pressed/active legs and glows.
  static const gradientBright = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, violetLight],
  );

  /// Soft brand-tinted glow for raised interactive surfaces (capture button,
  /// primary CTA, success pop). One elevation tier — cards stay flat.
  static List<BoxShadow> glow({double opacity = 0.45, double blur = 24, double y = 8}) => [
        BoxShadow(
          color: violet.withValues(alpha: opacity),
          blurRadius: blur,
          offset: Offset(0, y),
          spreadRadius: -4,
        ),
      ];

  // ---- Type ---------------------------------------------------------------- //
  // Expressive display face for headlines/wordmark; clean body face for reading.
  static TextTheme textTheme(TextTheme base) {
    final display = GoogleFonts.sora(textStyle: base.bodyLarge);
    return GoogleFonts.interTextTheme(base).copyWith(
      displayLarge: display.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
      displayMedium: display.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      displaySmall: display.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
      headlineMedium: display.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.12),
      headlineSmall: display.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.15),
      titleLarge: display.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    );
  }

  static TextStyle wordmarkStyle(double size, {Color? color}) => GoogleFonts.sora(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: color,
      );
}

/// The "catch" glyph: a rounded bracket cradling a falling reel-square.
/// Painted (not an asset) so it scales crisply and can be tinted to context —
/// solid brand on light chrome, white on the gradient, mono on the icon.
class CachyGlyph extends StatelessWidget {
  const CachyGlyph({
    super.key,
    this.size = 28,
    this.color,
    this.gradient,
    this.reelDrop = 1.0,
  });

  final double size;

  /// Solid tint. Ignored when [gradient] is set.
  final Color? color;

  /// When set, the bracket strokes with this gradient (used on splash/icon).
  final Gradient? gradient;

  /// 0 = reel up at the top, 1 = reel resting in the bracket. Drives the splash
  /// "catch" animation; defaults to resting.
  final double reelDrop;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Brand.violet;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(color: tint, gradient: gradient, reelDrop: reelDrop),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.color, required this.gradient, required this.reelDrop});

  final Color color;
  final Gradient? gradient;
  final double reelDrop;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.13;
    final rect = Offset.zero & size;

    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (gradient != null) {
      bracketPaint.shader = gradient!.createShader(rect);
    } else {
      bracketPaint.color = color;
    }

    // The bracket: a U that opens upward, catching the reel.
    final path = Path()
      ..moveTo(w * 0.18, h * 0.30)
      ..lineTo(w * 0.18, h * 0.66)
      ..arcToPoint(Offset(w * 0.34, h * 0.82),
          radius: Radius.circular(w * 0.16), clockwise: false)
      ..lineTo(w * 0.66, h * 0.82)
      ..arcToPoint(Offset(w * 0.82, h * 0.66),
          radius: Radius.circular(w * 0.16), clockwise: false)
      ..lineTo(w * 0.82, h * 0.30);
    canvas.drawPath(path, bracketPaint);

    // The reel: a rounded square that falls into the bracket as reelDrop → 1.
    final topY = h * 0.06;
    final restY = h * 0.40;
    final cy = topY + (restY - topY) * reelDrop.clamp(0.0, 1.0);
    final reelSize = w * 0.30;
    final reelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, cy), width: reelSize, height: reelSize),
      Radius.circular(reelSize * 0.32),
    );
    final reelPaint = Paint()..style = PaintingStyle.fill;
    if (gradient != null) {
      reelPaint.shader = gradient!.createShader(rect);
    } else {
      reelPaint.color = color;
    }
    canvas.drawRRect(reelRect, reelPaint);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.reelDrop != reelDrop || old.color != color || old.gradient != gradient;
}

/// The full wordmark: glyph + lowercase `cachy`. Defaults to brand-tinted for
/// light chrome; pass [onGradient] true to render white for the splash/CTA.
class CachyWordmark extends StatelessWidget {
  const CachyWordmark({super.key, this.size = 26, this.onGradient = false});

  final double size;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final color = onGradient ? Colors.white : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CachyGlyph(size: size * 1.08, color: onGradient ? Colors.white : Brand.violet),
        SizedBox(width: size * 0.28),
        Text(
          'cachy',
          style: Brand.wordmarkStyle(
            size,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
