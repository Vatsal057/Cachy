/// The signature "working" mark (docs/06): a center badge carrying a spark glyph,
/// haloed by concentric rings that ripple outward — the calm pulse shown while a
/// reel is processed. Adapted from the Insightr prototype's star/processing motif,
/// reskinned into the cream/ink world (brand primary, flat — no neon glow).
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../brand.dart';

class ProcessingGlyph extends StatefulWidget {
  const ProcessingGlyph({
    super.key,
    this.size = 132,
    this.icon = PhosphorIconsRegular.sparkle,
    this.badgeColor,
  });

  final double size;
  final PhosphorIconData icon;

  /// Overrides the badge fill (defaults to the theme's primary color). Lets the
  /// glyph carry the detected source platform's brand color, so the "sending"
  /// moment previews *what* is being fetched, not just a generic spark.
  final Color? badgeColor;

  @override
  State<ProcessingGlyph> createState() => _ProcessingGlyphState();
}

class _ProcessingGlyphState extends State<ProcessingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  static const _ringCount = 3;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = widget.badgeColor ?? scheme.primary;
    final badgeFill = widget.badgeColor ?? scheme.primary;
    final onBadge = ThemeData.estimateBrightnessForColor(badgeFill) == Brightness.dark
        ? Colors.white
        : Brand.ink;
    final badge = widget.size * 0.42;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Rippling halo rings, each offset in phase so they radiate steadily.
              for (var i = 0; i < _ringCount; i++)
                _ring(ringColor, (_c.value + i / _ringCount) % 1.0, badge),
              child!,
            ],
          );
        },
        // Center badge: a circle that breathes gently, carrying the source icon.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (context, t, _) {
            final pulse = 1.0 + 0.04 * (1 - (2 * (_c.value) - 1).abs());
            return Transform.scale(
              scale: t * pulse,
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: badgeFill,
                  shape: BoxShape.circle,
                  boxShadow: Brand.softShadow(opacity: 0.22, blur: 22, y: 6),
                ),
                child: PhosphorIcon(widget.icon, size: badge * 0.5, color: onBadge),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _ring(Color color, double t, double base) {
    final diameter = base * (1.0 + t * 1.4);
    final opacity = (1.0 - t) * 0.35;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1.4,
        ),
      ),
    );
  }
}
