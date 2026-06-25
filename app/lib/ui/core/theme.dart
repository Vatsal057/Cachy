/// The editorial design system: a calm cream+ink frame (magazine direction) that
/// lets content carry attention. Two palettes of one world — light (cream ground /
/// ink text) and dark (ink ground / cream text) — both accented by rust.
///
/// Surfaces are flat: cards and sections carry a hairline rule rather than
/// elevation. Type is the three-face system from [Brand] — Fraunces serif display,
/// Inter body, IBM Plex Mono labels.
library;

import 'package:flutter/material.dart';

import 'brand.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = Brand.accentFor(brightness);
    final ground = isDark ? Brand.inkGround : Brand.creamGround;
    final raised = isDark ? Brand.inkRaised : Brand.creamRaised;
    final onGround = isDark ? Brand.cream : Brand.ink;
    final muted = Brand.mutedFor(brightness);
    final hairline = Brand.hairlineFor(brightness);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Brand.creamGround,
      primaryContainer: accent.withValues(alpha: isDark ? 0.22 : 0.12),
      onPrimaryContainer: isDark ? Brand.cream : Brand.ink,
      secondary: onGround,
      onSecondary: ground,
      secondaryContainer: raised,
      onSecondaryContainer: onGround,
      tertiary: accent,
      onTertiary: Brand.creamGround,
      error: const Color(0xFFB23A2A),
      onError: Brand.creamGround,
      errorContainer: const Color(0xFFB23A2A).withValues(alpha: 0.14),
      onErrorContainer: isDark ? Brand.cream : const Color(0xFF7A271B),
      surface: ground,
      onSurface: onGround,
      onSurfaceVariant: muted,
      surfaceContainerLowest: ground,
      surfaceContainerLow: raised,
      surfaceContainer: raised,
      surfaceContainerHigh: isDark ? const Color(0xFF2A261E) : const Color(0xFFE6DCC9),
      surfaceContainerHighest: isDark ? const Color(0xFF322D24) : const Color(0xFFDED3BD),
      outline: muted.withValues(alpha: 0.6),
      outlineVariant: hairline,
      shadow: Brand.ink,
      scrim: Brand.ink,
      inverseSurface: onGround,
      onInverseSurface: ground,
      inversePrimary: accent,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: ground,
      // Flat editorial chrome: the app bar is part of the page, not a banner.
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        foregroundColor: onGround,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: Brand.textTheme(base.textTheme).titleLarge?.copyWith(color: onGround),
      ),
      // Cards are flat with a hairline — print, not plastic.
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Insets.radius),
          side: BorderSide(color: hairline),
        ),
        color: raised,
      ),
      textTheme: Brand.textTheme(base.textTheme).copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55, color: onGround),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5, color: onGround),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Brand.creamGround,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onGround,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: raised,
        side: BorderSide(color: hairline),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: onGround,
        contentTextStyle: TextStyle(color: ground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.all(16),
      ),
      // Calm, editorial route motion: fade-through on every push.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Motion tokens: fast, purposeful, no idle bounce. One spring accent per
/// interaction (capture press, success pop, check toggle).
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const stagger = Duration(milliseconds: 45); // per-block build-in delay
  static const curve = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack; // gentle overshoot for editorial pops
}

class Insets {
  static const page = 24.0; // generous editorial margin
  static const block = 16.0; // vertical gap between blocks
  static const radius = 14.0;

  /// Max text measure for a comfortable reading column (reader/chat/share). On
  /// wider screens the content centers within this width.
  static const readingColumn = 680.0;
}
