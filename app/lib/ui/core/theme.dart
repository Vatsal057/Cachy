/// The design-visual system (docs/07): a calm, coherent frame that dials down so
/// content-visuals (keyframes, maps) carry attention. Material 3, light + dark.
library;

import 'package:flutter/material.dart';

class AppTheme {
  static const seed = Color(0xFF5B5BD6); // restrained indigo; accents per type

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
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
      // Tighter, more deliberate typography (optical, slightly negative tracking
      // on display sizes — make-interfaces-feel-better).
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.15,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
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
    );
  }
}

/// Motion tokens (docs/07): fast, purposeful, no bounce.
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const stagger = Duration(milliseconds: 45); // per-block build-in delay
  static const curve = Curves.easeOutCubic;
}

class Insets {
  static const page = 20.0;
  static const block = 16.0; // vertical gap between blocks
  static const radius = 16.0;
}
