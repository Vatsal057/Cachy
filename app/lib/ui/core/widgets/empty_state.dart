/// Designed zero-states, used everywhere a list can be empty (library, search,
/// graph, to-do). One component so every empty screen feels intentional rather
/// than blank. The glyph + a single CTA; nothing more.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../brand.dart';
import '../theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.art,
    this.showGlyph = false,
    this.halo = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final PhosphorIconData? icon;

  /// Optional screen-specific spot illustration, shown beneath the message.
  /// Each empty screen passes its own so no two feel templated.
  final Widget? art;

  /// Show the brand glyph instead of a Material icon (used on the library's
  /// first-ever empty state for a branded welcome).
  final bool showGlyph;

  /// Wrap the mark in two concentric accent rings — a calm halo that makes a
  /// first-run zero-state feel deliberate (the "vault" welcome).
  final bool halo;
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
            _Mark(
              halo: halo,
              accent: scheme.primary,
              child: showGlyph
                  ? const CachyGlyph(size: 64)
                  : Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: PhosphorIcon(icon ?? PhosphorIconsRegular.tray,
                          size: 34, color: scheme.onSurfaceVariant),
                    ),
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
            if (art != null) ...[
              const SizedBox(height: 22),
              art!,
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 20),
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

/// The empty-state mark, optionally haloed by two concentric accent rings.
class _Mark extends StatelessWidget {
  const _Mark({required this.child, required this.halo, required this.accent});
  final Widget child;
  final bool halo;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (!halo) return child;
    return SizedBox(
      width: 176,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.10), width: 1.4),
            ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.18), width: 1.4),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
