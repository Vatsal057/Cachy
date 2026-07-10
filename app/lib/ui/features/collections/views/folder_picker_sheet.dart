/// Bulk "Move to Folder" picker — an adaptive sheet listing the user's folders
/// (plus "New folder…" and "Remove from folders"). Replaces the old
/// coming-soon stub in the selection action bar.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/collection.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/adaptive_modal.dart';
import '../../library/view_models/library_view_model.dart';

/// Present the folder picker for the current selection. Moves every selected
/// card into the chosen folder and shows a confirmation. No-op if nothing is
/// selected.
Future<void> showFolderPicker(BuildContext context, LibraryViewModel vm) async {
  if (!vm.selectionActive) return;
  final count = vm.selectedCount;
  final repo = context.read<CardRepository>();
  final messenger = ScaffoldMessenger.of(context);

  await showAdaptiveModal<void>(
    context: context,
    builder: (ctx, dialog) => _FolderPicker(
      repo: repo,
      dialog: dialog,
      onPick: (collectionId, label) async {
        Navigator.pop(ctx);
        await vm.bulkMove(collectionId);
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Moved $count ${count == 1 ? 'card' : 'cards'}'
            '${label == null ? ' out of folders' : ' to "$label"'}',
          ),
        ));
      },
    ),
  );
}

class _FolderPicker extends StatelessWidget {
  const _FolderPicker({
    required this.repo,
    required this.dialog,
    required this.onPick,
  });

  final CardRepository repo;
  final bool dialog;

  /// (collectionId, label): collectionId null = remove from all folders.
  final Future<void> Function(String? collectionId, String? label) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: dialog
            ? BorderRadius.circular(Insets.radius)
            : const BorderRadius.vertical(top: Radius.circular(Insets.radius)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!dialog)
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Move to folder', style: theme.textTheme.titleMedium),
            ),
          ),
          Flexible(
            child: FutureBuilder<List<CollectionEntry>>(
              future: repo.listCollections(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  );
                }
                final folders = snap.data ?? const <CollectionEntry>[];
                return ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final f in folders)
                      ListTile(
                        leading: const PhosphorIcon(PhosphorIconsRegular.folder),
                        title: Text(f.name),
                        onTap: () => onPick(f.id, f.name),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      leading: PhosphorIcon(PhosphorIconsRegular.folderPlus,
                          color: scheme.primary),
                      title: Text('New folder…',
                          style: TextStyle(color: scheme.primary)),
                      onTap: () => _createAndMove(context),
                    ),
                    if (folders.isNotEmpty)
                      ListTile(
                        leading: const PhosphorIcon(PhosphorIconsRegular.folderMinus),
                        title: const Text('Remove from folders'),
                        onTap: () => onPick(null, null),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createAndMove(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final created = await repo.createCollection(name);
    await onPick(created.id, created.name);
  }
}
