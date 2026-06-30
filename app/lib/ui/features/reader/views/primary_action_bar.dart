/// The card's action area (docs/13). Always offers **Ask** (grounded chat) and
/// a content-aware "more" menu; when the server derived a dominant action it
/// also shows it as the primary button. Handlers run on-device against the
/// card's own blocks (see [CardActions]) — share/copy/Maps/calendar, all free.
library;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../domain/models/card.dart';
import '../../../core/widgets/adaptive_modal.dart';
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
                icon: const PhosphorIcon(PhosphorIconsRegular.chatCircle),
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
                  icon: const PhosphorIcon(PhosphorIconsRegular.chatCircle),
                  label: const Text('Ask this card'),
                ),
              ),
            if (hasPrimary) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryActionButton(
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
              icon: const PhosphorIcon(PhosphorIconsRegular.dotsThree),
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
    final specs = _actions
        .available(card)
        .where((s) => s.type != primaryType)
        .toList();
    final scheme = Theme.of(context).colorScheme;
    final chosen = await showAdaptiveModal<CardActionType>(
      context: context,
      builder: (ctx, dialog) => SafeArea(
        top: false,
        child: Container(
          decoration: dialog
              ? BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant),
                )
              : null,
          padding: dialog ? const EdgeInsets.symmetric(vertical: 8) : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in specs)
                ListTile(
                  leading: PhosphorIcon(s.icon),
                  title: Text(s.label),
                  onTap: () => Navigator.pop(ctx, s.type),
                ),
            ],
          ),
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
      ActionResult.done => null,
      ActionResult.copied => 'Copied to clipboard',
      ActionResult.empty => 'Nothing in this card for that',
      ActionResult.failed => "Couldn't complete that action",
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  PhosphorIconData _iconFor(CardActionType type) {
    switch (type) {
      case CardActionType.share:
        return PhosphorIconsRegular.export;
      case CardActionType.shoppingList:
        return PhosphorIconsRegular.shoppingCart;
      case CardActionType.openMaps:
        return PhosphorIconsRegular.mapPin;
      case CardActionType.addToCalendar:
        return PhosphorIconsRegular.calendarCheck;
      case CardActionType.copy:
        return PhosphorIconsRegular.copy;
      case CardActionType.openOriginal:
        return PhosphorIconsRegular.playCircle;
      case CardActionType.openLinks:
        return PhosphorIconsRegular.link;
    }
  }
}

/// The dominant action — flat sage, the loudest control in the reader.
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.busy,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool busy;
  final PhosphorIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onTap,
      icon: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, valueColor: AlwaysStoppedAnimation(scheme.onPrimary)),
            )
          : PhosphorIcon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
