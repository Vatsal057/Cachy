/// Shared bulk-selection dialogs for the library. Extracted so the mobile shell
/// and the desktop overlay invoke the exact same confirmation flow instead of
/// each carrying its own copy.
library;

import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_modal.dart';
import '../view_models/library_view_model.dart';

/// Confirm and perform a bulk delete of the currently-selected cards. Surfaces
/// a snackbar if the delete fails.
Future<void> confirmBulkDelete(BuildContext context, LibraryViewModel vm) async {
  final count = vm.selectedCount;
  if (count == 0) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showAdaptiveModal<bool>(
    context: context,
    builder: (ctx, dialog) => AlertDialog(
      title: Text('Delete $count ${count == 1 ? 'card' : 'cards'}?'),
      content: const Text(
          'This removes the cards and their media. This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await vm.bulkDelete();
    if (vm.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(vm.error!)));
    }
  }
}
