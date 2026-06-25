/// The design-visual system (docs/07): a calm, coherent frame that dials down so
/// content-visuals (keyframes, maps) carry attention. Material 3, light + dark.
///
/// Bold-branded direction: the *frame* stays calm and flat (content wins), but
/// identity is carried by the brand layer ([Brand], `brand.dart`) — expressive
/// Sora/Inter type, the indigo→violet gradient on chrome, and one elevation tier
/// of brand-tinted glow on interactive surfaces. Dark is first-class: vivid
/// accents are meant to pop on the brand-ink canvas.
library;

import 'package:flutter/material.dart';

import 'brand.dart';

class AppTheme {
  static const seed = Brand.indigo; // restrained indigo seed; accents per type

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      // Brand-ink canvas in dark so vivid accents and gradient chrome pop.
      surface: isDark ? Brand.ink : null,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      // Calm chrome: flat app bar, no heavy elevation competing with content.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: scheme.surfaceContainerLow,
      ),
      // Expressive brand type: Sora display + Inter body (brand.dart). Replaces
      // stock Roboto — this is most of what reads as "branded".
      textTheme: Brand.textTheme(base.textTheme).copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.1,
          ),
        ),
      ),
      // Branded toasts: floating, rounded, consistent everywhere.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

/// Motion tokens (docs/07): fast, purposeful, no idle bounce. One spring accent
/// per interaction (capture press, success pop, check toggle).
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const stagger = Duration(milliseconds: 45); // per-block build-in delay
  static const curve = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack; // gentle overshoot for branded pops
}

class Insets {
  static const page = 20.0;
  static const block = 16.0; // vertical gap between blocks
  static const radius = 16.0;
}
