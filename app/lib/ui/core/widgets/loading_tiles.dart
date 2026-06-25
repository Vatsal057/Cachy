/// Shimmer placeholder tiles for the library grid while the first load resolves.
/// Matches the real grid's shape so the transition to content doesn't reflow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme.dart';

class LoadingTiles extends StatelessWidget {
  const LoadingTiles({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      padding: const EdgeInsets.all(Insets.page),
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: Insets.block,
      crossAxisSpacing: Insets.block,
      childAspectRatio: 0.72,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Insets.radius),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: const Duration(milliseconds: 1100),
                delay: Duration(milliseconds: i * 90),
                color: scheme.surfaceContainerHighest,
              ),
      ],
    );
  }
}
