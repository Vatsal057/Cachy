/// The one dominant action per card (docs/04 primary_action, docs/06). The kind
/// is derived server-side from content type. Phase-1 handlers acknowledge the
/// action locally; deep integrations (calendar, Notion export) are P2.
library;

import 'package:flutter/material.dart';

import '../../../../domain/models/card.dart';
import '../../../../domain/models/enums.dart';

class PrimaryActionBar extends StatelessWidget {
  const PrimaryActionBar({super.key, required this.action});
  final PrimaryAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: () => _run(context),
            icon: Icon(_icon),
            label: Text(action.label),
          ),
        ),
      ),
    );
  }

  IconData get _icon {
    switch (action.kind) {
      case PrimaryActionKind.shoppingList:
        return Icons.add_shopping_cart_rounded;
      case PrimaryActionKind.schedule:
        return Icons.event_available_rounded;
      case PrimaryActionKind.savePlace:
        return Icons.bookmark_add_rounded;
      case PrimaryActionKind.reminder:
        return Icons.notifications_active_rounded;
      case PrimaryActionKind.export:
        return Icons.ios_share_rounded;
      case PrimaryActionKind.none:
        return Icons.bolt_rounded;
    }
  }

  void _run(BuildContext context) {
    // Phase-1: acknowledge. P2 wires real shopping-list/calendar/export targets.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${action.label} — coming soon')),
    );
  }
}
