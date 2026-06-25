/// The card's action area (docs/13). Always offers **Ask** (grounded chat) and
/// a content-aware "more" menu; when the server derived a dominant action it
/// also shows it as the primary button. Handlers run on-device against the
/// card's own blocks (see [CardActions]) — share/copy/Maps/calendar, all free.
library;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';

import '../../../../domain/models/card.dart';
import '../../../core/brand.dart';
import '../services/card_actions.dart';
import 'chat_screen.dart';

class PrimaryActionBar extends StatefulWidget {
  const PrimaryActionBar({super.key, required this.card});
  final Card card;

  @override
  State<PrimaryActionBar> createState() => _PrimaryActionBarState();
}

class _PrimaryActionBarState extends State<PrimaryActionBar> {
  static const _actions = CardActions();
  bool _busy = false;

  Card get card => widget.card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryType = _actions.primaryType(card);
    final hasPrimary =
        card.primaryAction.isPresent && primaryType != null;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            if (hasPrimary)
              OutlinedButton.icon(
                onPressed: _openChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Ask'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              )
            else
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Ask this card'),
                ),
              ),
            if (hasPrimary) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _GradientActionButton(
                  busy: _busy,
                  icon: _iconFor(primaryType),
                  label: card.primaryAction.label,
                  onTap: _busy ? null : () => _run(primaryType),
                ),
              ),
            ],
            const SizedBox(width: 6),
            IconButton.filledTonal(
              onPressed: _busy ? null : () => _openMore(primaryType),
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: 'More actions',
              style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(cardId: card.cardId, title: card.base.oneLiner),
      ),
    );
  }

  Future<void> _openMore(CardActionType? primaryType) async {
    // The "more" sheet lists every available action except the one already
    // shown as the primary button.
    final specs = _actions
        .available(card)
        .where((s) => s.type != primaryType)
        .toList();
    final chosen = await showModalBottomSheet<CardActionType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in specs)
              ListTile(
                leading: Icon(s.icon),
                title: Text(s.label),
                onTap: () => Navigator.pop(ctx, s.type),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _run(chosen);
  }

  Future<void> _run(CardActionType type) async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final result = await _actions.perform(card, type);
    if (!mounted) return;
    setState(() => _busy = false);

    final message = switch (result) {
      ActionResult.done => null, // the OS sheet/app is the feedback
      ActionResult.copied => 'Copied to clipboard',
      ActionResult.empty => 'Nothing in this card for that',
      ActionResult.failed => "Couldn't complete that action",
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  IconData _iconFor(CardActionType type) {
    switch (type) {
      case CardActionType.share:
        return Icons.ios_share_rounded;
      case CardActionType.shoppingList:
        return Icons.add_shopping_cart_rounded;
      case CardActionType.openMaps:
        return Icons.map_rounded;
      case CardActionType.addToCalendar:
        return Icons.event_available_rounded;
      case CardActionType.copy:
        return Icons.copy_rounded;
      case CardActionType.openOriginal:
        return Icons.play_circle_outline_rounded;
      case CardActionType.openLinks:
        return Icons.link_rounded;
    }
  }
}

/// The dominant action — brand-gradient, the loudest control in the reader.
class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.busy,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool busy;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.7 : 1,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: Brand.gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: Brand.glow(opacity: 0.32, blur: 16, y: 5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                )
              else
                Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
