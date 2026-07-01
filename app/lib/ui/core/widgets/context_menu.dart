/// Desktop right-click / mobile long-press context menu for library and
/// highlight cards. The action *sets* are assembled by pure builder functions
/// (unit/PBT-testable, free of [BuildContext]); [showCardContextMenu] renders a
/// Material [showMenu] at the pointer and runs the selected action safely.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A single entry in a card context menu.
///
/// Pure data: a [label], a phosphor [icon], an async [onSelected] callback run
/// when the entry is chosen, and a [destructive] flag that tints the entry with
/// the theme error color (e.g. "Delete").
class ContextMenuAction {
  const ContextMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final PhosphorIconData icon;
  final Future<void> Function() onSelected;
  final bool destructive;
}

/// Assemble the context-menu action set for a content [CardTile].
///
/// Order is always: Open, Open in New Tab (desktop only), Copy Link, Delete.
/// "Open in New Tab" is present if and only if [isDesktopPlatform] is true.
/// "Delete" is destructive.
List<ContextMenuAction> buildCardMenuActions({
  required bool isDesktopPlatform,
  required Future<void> Function() onOpen,
  required Future<void> Function() onOpenNewTab,
  required Future<void> Function() onCopyLink,
  required Future<void> Function() onDelete,
}) {
  return [
    ContextMenuAction(
      label: 'Open',
      icon: PhosphorIconsRegular.arrowSquareOut,
      onSelected: onOpen,
    ),
    if (isDesktopPlatform)
      ContextMenuAction(
        label: 'Open in New Tab',
        icon: PhosphorIconsRegular.plusSquare,
        onSelected: onOpenNewTab,
      ),
    ContextMenuAction(
      label: 'Copy Link',
      icon: PhosphorIconsRegular.copy,
      onSelected: onCopyLink,
    ),
    ContextMenuAction(
      label: 'Delete',
      icon: PhosphorIconsRegular.trash,
      onSelected: onDelete,
      destructive: true,
    ),
  ];
}

/// Assemble the context-menu action set for a highlight card.
///
/// Always exactly: Copy Text, Delete. "Delete" is destructive.
List<ContextMenuAction> buildHighlightMenuActions({
  required Future<void> Function() onCopyText,
  required Future<void> Function() onDelete,
}) {
  return [
    ContextMenuAction(
      label: 'Copy Text',
      icon: PhosphorIconsRegular.textT,
      onSelected: onCopyText,
    ),
    ContextMenuAction(
      label: 'Delete',
      icon: PhosphorIconsRegular.trash,
      onSelected: onDelete,
      destructive: true,
    ),
  ];
}

/// Show a Material context menu anchored at [globalPosition] and run the
/// selected [ContextMenuAction].
///
/// Tapping outside or pressing Escape dismisses the menu without running any
/// action (native [showMenu] behavior — it returns null). If the selected
/// action throws, the menu is already dismissed, an error [SnackBar] describes
/// the failure, and no mutation is applied (Requirement 5.6).
Future<void> showCardContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required List<ContextMenuAction> actions,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final theme = Theme.of(context);
  final position = RelativeRect.fromRect(
    globalPosition & const Size(40, 40),
    Offset.zero & overlay.size,
  );

  final selected = await showMenu<ContextMenuAction>(
    context: context,
    position: position,
    items: [
      for (final action in actions)
        PopupMenuItem<ContextMenuAction>(
          value: action,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                action.icon,
                size: 18,
                color: action.destructive ? theme.colorScheme.error : null,
              ),
              const SizedBox(width: 12),
              Text(
                action.label,
                style: action.destructive
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
            ],
          ),
        ),
    ],
  );

  if (selected == null) return;

  try {
    await selected.onSelected();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not ${selected.label.toLowerCase()}: $error')),
    );
  }
}
