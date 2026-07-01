/// [SelectionActionBar] — floating glass bulk-action bar shown while one or
/// more library cards are selected.
///
/// Presentational only: it takes a [selectedCount] plus action callbacks and
/// holds no reference to any view model, so it compiles and tests in isolation.
/// The owning screen wires the callbacks to the selection view model.
///
/// Requirements: 8.6 (count + "Delete Selected"/"Move to Folder" actions),
/// 8.7 (delete confirmation flow is triggered via [onDeleteSelected]).
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../brand.dart';
import '../theme.dart';
import 'glass.dart';

/// A floating glass bar summarising the current multi-selection and offering
/// bulk actions. Show this while a selection is active; hide it otherwise.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.selectedCount,
    required this.onDeleteSelected,
    required this.onMoveToFolder,
    required this.onClose,
  });

  /// Number of currently selected cards, rendered as "{n} selected".
  final int selectedCount;

  /// Invoked when the user activates "Delete Selected".
  final VoidCallback onDeleteSelected;

  /// Invoked when the user activates "Move to Folder".
  final VoidCallback onMoveToFolder;

  /// Invoked when the user clears the selection via the leading close control.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Insets.radius),
        boxShadow: Brand.softShadow(opacity: 0.16, blur: 28, y: 8),
      ),
      child: Glass.rounded(
        radius: Insets.radius,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          // mainAxisSize.max so the row fills the Glass container's width,
          // which is required for Spacer to work. The container's own width
          // is driven by the Positioned constraints in the parent Stack.
          children: [
            // Leading: clear selection.
            IconButton(
              icon: const PhosphorIcon(PhosphorIconsRegular.x, size: 20),
              tooltip: 'Clear selection',
              onPressed: onClose,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$selectedCount selected',
                overflow: TextOverflow.ellipsis,
                style: Brand.label(
                  size: 12,
                  color: scheme.onSurface,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const Spacer(),
            // Actions.
            _BarAction(
              icon: PhosphorIconsRegular.folder,
              label: 'Move to Folder',
              color: scheme.onSurface,
              onPressed: onMoveToFolder,
            ),
            const SizedBox(width: 4),
            _BarAction(
              icon: PhosphorIconsRegular.trash,
              label: 'Delete Selected',
              color: scheme.error,
              onPressed: onDeleteSelected,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single labelled icon action inside the [SelectionActionBar].
class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final PhosphorIconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: PhosphorIcon(icon, size: 18, color: color),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: Brand.label(size: 11, letterSpacing: 0.4),
        ),
      ),
    );
  }
}
