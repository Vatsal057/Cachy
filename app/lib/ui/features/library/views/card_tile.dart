/// A single library tile: a content-visual face with a calm scrim carrying the
/// one-liner and a state badge. Tapping opens the reader via a shared-element
/// transition on the face (docs/07 motion token).
library;

import 'package:flutter/material.dart';

import '../../../../data/services/api_client.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/widgets/card_face.dart';
import '../../../core/widgets/state_badge.dart';

class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.api,
    required this.onTap,
    required this.onDelete,
    this.confirmTitle = 'Delete card?',
    this.confirmBody = 'This removes the card and its media.',
    this.confirmAction = 'Delete',
  });

  final model.Card card;
  final ApiClient api;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Long-press confirm copy; overridable so the same tile can mean "remove"
  /// rather than "delete the card" depending on context.
  final String confirmTitle;
  final String confirmBody;
  final String confirmAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ContentAccent.of(card.base.contentType);
    final title = card.base.oneLiner.isNotEmpty
        ? card.base.oneLiner
        : (card.isProcessing ? 'Working on it…' : 'Untitled');

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _confirmDelete(context),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'card-face-${card.cardId}',
              child: CardFace(card: card, api: api),
            ),
            // Bottom scrim so text stays legible over any face.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(accent.icon, size: 13, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(
                        card.base.contentType.label.toUpperCase(),
                        style: Brand.label(size: 9, color: Colors.white70, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  if (card.isReady) _MetaPills(card: card),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: StateBadge(
                state: card.state,
                reason: card.failureReason,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirmTitle),
        content: Text(confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmAction),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}

/// Compact at-a-glance counts on a tile scrim — how much a card carries before
/// you open it (actions to do, steps inside, deeper analysis). Renders nothing
/// when the card has none.
class _MetaPills extends StatelessWidget {
  const _MetaPills({required this.card});
  final model.Card card;

  @override
  Widget build(BuildContext context) {
    final actions = card.actionItems.items.length;
    var steps = 0;
    for (final b in card.rawBlocks) {
      final type = b['type'];
      if (type == 'step_list') steps += (b['steps'] as List?)?.length ?? 0;
      if (type == 'checklist') steps += (b['items'] as List?)?.length ?? 0;
    }
    final hasInsight = card.insight?.hasContent ?? false;

    final pills = <String>[
      if (actions > 0) '$actions ${actions == 1 ? 'action' : 'actions'}',
      if (steps > 0) '$steps steps',
    ];
    if (pills.isEmpty && !hasInsight) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in pills) _Pill(label: p),
          if (hasInsight) const _Pill(label: 'Deep', highlight: true),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Brand.label(
          size: 9.5,
          color: highlight ? Colors.black87 : Colors.white,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}
