/// A compact dashboard strip: a row of boxed value/label cells. Used for vault
/// stats (Profile, Catalog) and the insight stat trio atop deep cards. Editorial,
/// flat — bordered cells on the surface, no glow.
library;

import 'package:flutter/material.dart';

import '../brand.dart';
import '../theme.dart';

class Stat {
  const Stat({required this.value, required this.label, this.emphasize = false});
  final String value;
  final String label;

  /// Tint the value in the brand accent (used for the headline stat).
  final bool emphasize;
}

class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats});
  final List<Stat> stats;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _Cell(stat: stats[i])),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.stat});
  final Stat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: stat.emphasize ? scheme.primary : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: Brand.label(
              size: 9.5,
              color: scheme.onSurfaceVariant,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
