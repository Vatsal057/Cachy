library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_tiles.dart';
import '../view_models/collections_view_model.dart';
import 'collection_detail_screen.dart';
import 'folder_tile.dart';

class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          CollectionsViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _CollectionsView(),
    );
  }
}

class _CollectionsView extends StatelessWidget {
  const _CollectionsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CollectionsViewModel>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: Insets.page,
        title: Text(
          'COLLECTIONS',
          style: Brand.label(
            size: 15,
            color: scheme.onSurface,
            weight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showNewFolderDialog(context, vm),
            tooltip: 'New folder',
            icon: const PhosphorIcon(PhosphorIconsRegular.folderPlus),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(context, vm),
    );
  }

  Widget _body(BuildContext context, CollectionsViewModel vm) {
    switch (vm.status) {
      case CollectionsStatus.loading:
        return const LoadingTiles();
      case CollectionsStatus.error:
        return _scrollable(
          ErrorState(
            title: "Can't load collections",
            message: vm.error ?? 'Check your connection and try again.',
            onRetry: vm.load,
          ),
        );
      case CollectionsStatus.empty:
        return _scrollable(
          const EmptyState(
            showGlyph: true,
            halo: true,
            title: 'No collections yet',
            message:
                'Save a reel and Cachy will auto-sort it into a folder based '
                'on what it is — recipes, workouts, tips, and more.',
          ),
        );
      case CollectionsStatus.idle:
      case CollectionsStatus.ready:
        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: vm.refresh,
          child: _grid(context, vm),
        );
    }
  }

  Widget _scrollable(Widget child) => LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: child,
            ),
          ],
        ),
      );

  Widget _grid(BuildContext context, CollectionsViewModel vm) {
    final api = context.read<CardRepository>().api;
    final width = MediaQuery.of(context).size.width;
    final cols = (width / 180).floor().clamp(2, 7);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.9,
      ),
      itemCount: vm.collections.length,
      itemBuilder: (ctx, i) {
        final col = vm.collections[i];
        return FolderTile(
          collection: col,
          api: api,
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => CollectionDetailScreen(collection: col),
            ),
          ),
          onLongPress: () => _showRenameDialog(ctx, vm, col),
        );
      },
    );
  }

  Future<void> _showRenameDialog(
      BuildContext context, CollectionsViewModel vm, Collection col) async {
    final controller = TextEditingController(text: col.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename folder'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.isNotEmpty && newName != col.name) {
      try {
        await vm.rename(col.id, newName);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not rename folder')),
          );
        }
      }
    }
  }

  Future<void> _showNewFolderDialog(
      BuildContext context, CollectionsViewModel vm) async {
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
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      try {
        await vm.createFolder(name);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not create folder')),
          );
        }
      }
    }
  }
}
