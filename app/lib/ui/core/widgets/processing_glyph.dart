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
  });

  final double size;
  final PhosphorIconData icon;

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
                _ring(scheme, (_c.value + i / _ringCount) % 1.0, badge),
              child!,
            ],
          );
        },
        // Center badge: a rounded square that breathes gently.
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
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(badge * 0.3),
                  boxShadow: Brand.softShadow(opacity: 0.22, blur: 22, y: 6),
                ),
                child: PhosphorIcon(widget.icon, size: badge * 0.5, color: scheme.onPrimary),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _ring(ColorScheme scheme, double t, double base) {
    final diameter = base * (1.0 + t * 1.4);
    final opacity = (1.0 - t) * 0.35;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.primary.withValues(alpha: opacity),
          width: 1.4,
        ),
      ),
    );
  }
}
