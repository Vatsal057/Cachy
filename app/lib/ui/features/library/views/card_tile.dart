/// A single library tile: a content-visual face with a calm scrim carrying the
/// one-liner and a state badge. Tapping opens the reader via a shared-element
/// transition on the face (docs/07 motion token).
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../data/services/api_client.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/card_face.dart';
import '../../../core/widgets/state_badge.dart';

class CardTile extends StatefulWidget {
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
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = ContentAccent.of(widget.card.base.contentType);
    final title = widget.card.base.oneLiner.isNotEmpty
        ? widget.card.base.oneLiner
        : (widget.card.isProcessing ? 'Working on it…' : 'Untitled');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () => _confirmDelete(context),
        onSecondaryTap: () => _confirmDelete(context),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hovered ? 1.025 : 1.0,
          duration: Motion.fast,
          curve: Motion.spring,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: accent.color.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
              border: _hovered
                  ? Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'card-face-${widget.card.cardId}',
                    child: CardFace(card: widget.card, api: widget.api),
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
                            PhosphorIcon(accent.icon, size: 13, color: Colors.white70),
                            const SizedBox(width: 5),
                            Text(
                              widget.card.base.contentType.label.toUpperCase(),
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
                        if (widget.card.isReady) _MetaPills(card: widget.card),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: StateBadge(
                      state: widget.card.state,
                      reason: widget.card.failureReason,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.confirmTitle),
        content: Text(widget.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.confirmAction),
          ),
        ],
      ),
    );
    if (ok == true) widget.onDelete();
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
