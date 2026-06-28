/// Design tokens: the calm cream+charcoal palette wired into Material's
/// [ColorScheme], plus motion and layout tokens used across all screens.
library;

import 'package:flutter/material.dart';

import 'brand.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = Brand.accentFor(brightness);
    final ground = isDark ? Brand.charcoalGround : Brand.paperGround;
    final raised = isDark ? Brand.charcoalRaised : Brand.paperRaised;
    final onGround = isDark ? Brand.cream : Brand.ink;
    final muted = Brand.mutedFor(brightness);
    final hairline = Brand.hairlineFor(brightness);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: isDark ? Brand.charcoalGround : Brand.paperGround,
      primaryContainer: accent.withValues(alpha: isDark ? 0.20 : 0.12),
      onPrimaryContainer: onGround,
      secondary: onGround,
      onSecondary: ground,
      secondaryContainer: raised,
      onSecondaryContainer: onGround,
      tertiary: accent,
      onTertiary: isDark ? Brand.charcoalGround : Brand.paperGround,
      error: const Color(0xFFAF3A2A),
      onError: Brand.paperGround,
      errorContainer: const Color(0xFFAF3A2A).withValues(alpha: 0.12),
      onErrorContainer: isDark ? Brand.cream : const Color(0xFF7A231B),
      surface: ground,
      onSurface: onGround,
      onSurfaceVariant: muted,
      surfaceContainerLowest: ground,
      surfaceContainerLow: raised,
      surfaceContainer: raised,
      surfaceContainerHigh: isDark
          ? const Color(0xFF2A2826)
          : const Color(0xFFE3D9C8),
      surfaceContainerHighest: isDark
          ? const Color(0xFF322E2C)
          : const Color(0xFFD8CDB9),
      outline: muted.withValues(alpha: 0.5),
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
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: IOSPageTransitionsBuilder(),
          TargetPlatform.iOS: IOSPageTransitionsBuilder(),
          TargetPlatform.macOS: IOSPageTransitionsBuilder(),
          TargetPlatform.windows: IOSPageTransitionsBuilder(),
          TargetPlatform.linux: IOSPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onGround,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            Brand.textTheme(base.textTheme).titleLarge?.copyWith(color: onGround),
      ),
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
        bodyLarge: base.textTheme.bodyLarge
            ?.copyWith(height: 1.55, color: onGround),
        bodyMedium: base.textTheme.bodyMedium
            ?.copyWith(height: 1.5, color: onGround),
      ),
      dividerTheme:
          DividerThemeData(color: hairline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor:
              isDark ? Brand.charcoalGround : Brand.paperGround,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onGround,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
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
    );
  }
}

/// Motion tokens: purposeful, never idle. One spring per interaction.
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const stagger = Duration(milliseconds: 45);
  static const curve = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;
}

/// Layout tokens: generous editorial margins.
class Insets {
  static const page = 24.0;
  static const block = 16.0;
  static const radius = 14.0;
  static const readingColumn = 680.0;
}

/// Custom transition builder allowing swipe-right-to-go-back from ANYWHERE
/// on the screen, while preserving iOS slide transitions.
class IOSPageTransitionsBuilder extends PageTransitionsBuilder {
  const IOSPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      _SwipeBackGate(child: child),
    );
  }
}

class _SwipeBackGate extends StatefulWidget {
  const _SwipeBackGate({required this.child});
  final Widget child;

  @override
  State<_SwipeBackGate> createState() => _SwipeBackGateState();
}

class _SwipeBackGateState extends State<_SwipeBackGate> {
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) {
        _dragDistance += details.delta.dx;
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if ((velocity > 300 || _dragDistance > 70) && _dragDistance > 0) {
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
          }
        }
        _dragDistance = 0;
      },
      child: widget.child,
    );
  }
}
