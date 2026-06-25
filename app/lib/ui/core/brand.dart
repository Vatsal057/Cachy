/// The Cachy brand layer — editorial / magazine direction.
///
/// One bold color world: **cream + ink**, accented by a single **rust**. Light is
/// cream ground / ink text; dark is the nocturnal version of the same world —
/// ink ground / cream text. The accent (rust) is constant across both.
///
/// `theme.dart` wires these tokens into Material's [ColorScheme]; this file is the
/// single source of truth for the palette, the three-face type system (serif
/// display + sans body + mono labels), and the masthead identity (the painted
/// "catch" glyph + the `cachy` wordmark, both flat — no gradient).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  // ---- Palette ------------------------------------------------------------- //
  // Light world.
  static const creamGround = Color(0xFFF4EFE6); // scaffold
  static const creamRaised = Color(0xFFECE4D5); // cards / sheets
  static const ink = Color(0xFF1A1714); // text on cream
  static const inkMuted = Color(0xFF6B6359); // secondary text on cream

  // Dark world.
  static const inkGround = Color(0xFF1A1714); // scaffold
  static const inkRaised = Color(0xFF232019); // cards / sheets
  static const cream = Color(0xFFF4EFE6); // text on ink
  static const creamMuted = Color(0xFFA89F92); // secondary text on ink

  // The constant accent.
  static const rust = Color(0xFFC8412B); // light
  static const rustBright = Color(0xFFD9543B); // dark (slightly lifted)

  /// The accent for a given brightness.
  static Color accentFor(Brightness b) =>
      b == Brightness.dark ? rustBright : rust;

  /// Secondary/muted text color for a given brightness.
  static Color mutedFor(Brightness b) =>
      b == Brightness.dark ? creamMuted : inkMuted;

  /// Hairline color (borders, rules, dividers) for a given brightness.
  static Color hairlineFor(Brightness b) => b == Brightness.dark
      ? cream.withValues(alpha: 0.14)
      : ink.withValues(alpha: 0.12);

  /// One subtle paper shadow for genuinely raised surfaces (capture sheet,
  /// primary action bar). Cards stay flat with a hairline instead.
  static List<BoxShadow> softShadow({double opacity = 0.12, double blur = 20, double y = 6}) => [
        BoxShadow(
          color: ink.withValues(alpha: opacity),
          blurRadius: blur,
          offset: Offset(0, y),
          spreadRadius: -6,
        ),
      ];

  // ---- Type: serif display + sans body + mono labels ----------------------- //
  // Fraunces carries the editorial headlines; Inter is the calm reading body;
  // IBM Plex Mono sets uppercase metadata (eyebrows, timestamps, tags, labels).
  static TextTheme textTheme(TextTheme base) {
    final serif = GoogleFonts.frauncesTextTheme(base);
    final body = GoogleFonts.interTextTheme(base);
    return body.copyWith(
      displayLarge: serif.displayLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.0, height: 1.02),
      displayMedium: serif.displayMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.8, height: 1.04),
      displaySmall: serif.displaySmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.06),
      headlineLarge: serif.headlineLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.1),
      headlineMedium: serif.headlineMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4, height: 1.12),
      headlineSmall: serif.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.3, height: 1.15),
      titleLarge: serif.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    );
  }

  /// Uppercase mono label — the editorial "eyebrow". Used for metadata, section
  /// labels, type chips, timestamps, tags. Callers pass already-cased text; this
  /// just supplies the face, tracking and weight.
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

  /// The `cachy` wordmark face — the serif display, tight.
  static TextStyle wordmarkStyle(double size, {Color? color}) => GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
        color: color,
      );
}

/// The "catch" glyph: a rounded bracket cradling a falling reel-square. Painted
/// (not an asset) so it scales crisply and tints to context. Editorial direction:
/// flat ink or rust, no gradient.
class CachyGlyph extends StatelessWidget {
  const CachyGlyph({
    super.key,
    this.size = 28,
    this.color,
    this.reelColor,
    this.reelDrop = 1.0,
  });

  final double size;

  /// Bracket tint. Defaults to ink.
  final Color? color;

  /// Reel tint. Defaults to the rust accent, for a two-tone editorial mark.
  final Color? reelColor;

  /// 0 = reel up at the top, 1 = reel resting in the bracket (splash animation).
  final double reelDrop;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(
          bracket: color ?? Brand.ink,
          reel: reelColor ?? Brand.rust,
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
    canvas.drawRRect(reelRect, Paint()..color = reel);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.reelDrop != reelDrop || old.bracket != bracket || old.reel != reel;
}

/// The full wordmark: glyph + lowercase `cachy`, set in the serif display face.
/// Defaults to ink/rust for cream chrome; pass [onDark] for the ink ground.
class CachyWordmark extends StatelessWidget {
  const CachyWordmark({super.key, this.size = 26, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final wordColor = onDark ? Brand.cream : Brand.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CachyGlyph(
          size: size * 1.08,
          color: wordColor,
          reelColor: onDark ? Brand.rustBright : Brand.rust,
        ),
        SizedBox(width: size * 0.30),
        Text('cachy', style: Brand.wordmarkStyle(size, color: wordColor)),
      ],
    );
  }
}
