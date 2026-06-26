/// The Cachy brand layer — calm editorial glass direction.
///
/// Palette: warm paper light world / deep charcoal dark world. Accent is
/// muted sage — very low chroma, nearly dissolves into the ground. Glass
/// tokens live here so every glass surface shares them via [Brand.glassFill]
/// and [Brand.glassBorder].
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  // ── Light world — warm paper ──────────────────────────────────────────── //
  static const paperGround = Color(0xFFF5F0E8);
  static const paperRaised = Color(0xFFEBE3D5);
  static const ink = Color(0xFF1C1917);
  static const inkMuted = Color(0xFF6B6259);

  // ── Dark world — deep charcoal ────────────────────────────────────────── //
  static const charcoalGround = Color(0xFF181818);
  static const charcoalRaised = Color(0xFF222120);
  static const cream = Color(0xFFEDE8DF);
  static const creamMuted = Color(0xFF9A928A);

  // ── Accent — muted sage/clay, low chroma ─────────────────────────────── //
  static const sage = Color(0xFF7D8472);
  static const sageDark = Color(0xFF96A885);

  // ── Glass tokens ──────────────────────────────────────────────────────── //
  static const glassBlurSigma = 16.0;
  static const glassBlurSigmaDark = 20.0;

  static Color glassFill(Brightness b) => b == Brightness.dark
      ? const Color(0xFF1C1C1F).withValues(alpha: 0.82)
      : Colors.white.withValues(alpha: 0.72);

  static Color glassBorder(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.55);

  // ── Derived helpers ───────────────────────────────────────────────────── //
  static Color accentFor(Brightness b) =>
      b == Brightness.dark ? sageDark : sage;

  static Color mutedFor(Brightness b) =>
      b == Brightness.dark ? creamMuted : inkMuted;

  static Color hairlineFor(Brightness b) => b == Brightness.dark
      ? cream.withValues(alpha: 0.08)
      : ink.withValues(alpha: 0.08);

  static List<BoxShadow> softShadow({
    double opacity = 0.08,
    double blur = 20,
    double y = 4,
  }) =>
      [
        BoxShadow(
          color: ink.withValues(alpha: opacity),
          blurRadius: blur,
          offset: Offset(0, y),
          spreadRadius: -4,
        ),
      ];

  // ── Type system ───────────────────────────────────────────────────────── //
  // Fraunces → display/headlines  ·  Inter → body  ·  IBM Plex Mono → labels
  static TextTheme textTheme(TextTheme base) {
    final serif = GoogleFonts.frauncesTextTheme(base);
    final body = GoogleFonts.interTextTheme(base);
    return body.copyWith(
      displayLarge: serif.displayLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.0, height: 1.02),
      displayMedium: serif.displayMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.8, height: 1.04),
      displaySmall: serif.displaySmall
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.06),
      headlineLarge: serif.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.1),
      headlineMedium: serif.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.12),
      headlineSmall: serif.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3, height: 1.15),
      titleLarge: serif.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    );
  }

  /// Uppercase mono label — editorial eyebrow / metadata / tags.
  static TextStyle label({
    double size = 11,
    Color? color,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 1.1,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color,
      );

  static TextStyle wordmarkStyle(double size, {Color? color}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        color: color,
      );
}

/// The "catch" glyph: a U bracket cradling a falling reel square. Tinted to
/// sage accent in the new calm editorial direction.
class CachyGlyph extends StatelessWidget {
  const CachyGlyph({
    super.key,
    this.size = 28,
    this.color,
    this.reelColor,
    this.reelDrop = 1.0,
  });

  final double size;
  final Color? color;
  final Color? reelColor;

  /// 0 = reel at top, 1 = resting in bracket (used by splash animation).
  final double reelDrop;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(
          bracket: color ?? Brand.accentFor(b),
          reel: reelColor ?? Brand.accentFor(b).withValues(alpha: 0.55),
          reelDrop: reelDrop,
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.bracket, required this.reel, required this.reelDrop});

  final Color bracket;
  final Color reel;
  final double reelDrop;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.13;

    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = bracket;

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

    final topY = h * 0.06;
    final restY = h * 0.40;
    final cy = topY + (restY - topY) * reelDrop.clamp(0.0, 1.0);
    final reelSize = w * 0.30;
    final reelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.5, cy), width: reelSize, height: reelSize),
      Radius.circular(reelSize * 0.32),
    );
    canvas.drawRRect(reelRect, Paint()..color = reel);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.reelDrop != reelDrop || old.bracket != bracket || old.reel != reel;
}

/// Full wordmark: glyph + "cachy" in the serif display face.
class CachyWordmark extends StatelessWidget {
  const CachyWordmark({super.key, this.size = 26, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final wordColor = onDark ? Brand.cream : Brand.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CachyGlyph(
          size: size * 1.08,
          color: Brand.accentFor(b),
          reelColor: Brand.accentFor(b).withValues(alpha: 0.50),
        ),
        SizedBox(width: size * 0.30),
        Text('cachy', style: Brand.wordmarkStyle(size, color: wordColor)),
      ],
    );
  }
}
