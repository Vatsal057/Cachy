/// Designed zero-states, used everywhere a list can be empty (library, search,
/// graph, to-do). One component so every empty screen feels intentional rather
/// than blank. The glyph + a single CTA; nothing more.
library;

import 'package:flutter/material.dart';

import '../brand.dart';
import '../theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.showGlyph = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData? icon;

  /// Show the brand glyph instead of a Material icon (used on the library's
  /// first-ever empty state for a branded welcome).
  final bool showGlyph;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.page * 1.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showGlyph)
              const CachyGlyph(size: 64)
            else
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon ?? Icons.inbox_rounded,
                    size: 34, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
