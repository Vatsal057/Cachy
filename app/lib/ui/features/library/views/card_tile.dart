/// A single library tile: a content-visual face with a calm scrim carrying the
/// one-liner and a state badge. Tapping opens the reader via a shared-element
/// transition on the face (docs/07 motion token).
library;

import 'package:flutter/material.dart';

import '../../../../data/services/api_client.dart';
import '../../../../domain/models/card.dart' as model;
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
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
