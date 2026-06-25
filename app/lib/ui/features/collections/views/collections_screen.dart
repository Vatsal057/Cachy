/// Collections: the user's named groups of cards (docs/09). A list of
/// collections; tapping one opens a grid of its member cards. Creating a
/// collection is a single name prompt; cards are added from the reader.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/collection.dart';
import '../../../core/theme.dart';
import '../../library/views/card_tile.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/collections_view_model.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptCreate(context, vm),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.refresh,
        child: _body(context, vm),
      ),
    );
  }

  Widget _body(BuildContext context, CollectionsViewModel vm) {
    switch (vm.status) {
      case CollectionsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case CollectionsStatus.error:
        return _Message(
          icon: Icons.wifi_off_rounded,
          title: "Can't reach the backend",
          subtitle: vm.error ?? '',
          action: FilledButton(onPressed: vm.load, child: const Text('Retry')),
        );
      case CollectionsStatus.empty:
        return const _Message(
          icon: Icons.folder_open_rounded,
          title: 'No collections yet',
          subtitle: 'Group related cards — tap New, then add cards from a card.',
        );
      case CollectionsStatus.idle:
      case CollectionsStatus.ready:
        final items = vm.collections;
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) => _CollectionRow(collection: items[i], vm: vm),
        );
    }
  }

  Future<void> _promptCreate(
      BuildContext context, CollectionsViewModel vm) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Recipes to try'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) await vm.create(name);
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.collection, required this.vm});
  final Collection collection;
  final CollectionsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_rounded),
      title: Text(collection.name),
      subtitle: Text('${collection.count} '
          '${collection.count == 1 ? 'card' : 'cards'}'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => _confirmDelete(context),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CollectionDetailScreen(
            collectionId: collection.id,
            name: collection.name,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete collection?'),
        content: Text('“${collection.name}” will be removed. '
            'The cards themselves are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) vm.delete(collection.id);
  }
}

/// A collection's member cards, fetched on open. Reuses the library [CardTile].
class CollectionDetailScreen extends StatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.name,
  });
  final String collectionId;
  final String name;

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  CollectionDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail =
          await context.read<CardRepository>().getCollection(widget.collectionId);
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _remove(String cardId) async {
    await context
        .read<CardRepository>()
        .removeCardFromCollection(widget.collectionId, cardId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<CardRepository>().api;
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _error != null
          ? Center(child: Text("Couldn't load this collection"))
          : detail == null
              ? const Center(child: CircularProgressIndicator())
              : detail.cards.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No cards yet. Open a card and use "Add to collection".',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          Insets.page, 12, Insets.page, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: detail.cards.length,
                      itemBuilder: (ctx, i) {
                        final card = detail.cards[i];
                        return CardTile(
                          card: card,
                          api: api,
                          confirmTitle: 'Remove from collection?',
                          confirmBody:
                              'The card stays in your library; it just leaves '
                              'this collection.',
                          confirmAction: 'Remove',
                          onTap: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ReaderScreen(cardId: card.cardId),
                            ),
                          ),
                          onDelete: () => _remove(card.cardId),
                        );
                      },
                    ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Icon(icon, size: 52, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (action != null) ...[
          const SizedBox(height: 20),
          Center(child: action!),
        ],
      ],
    );
  }
}
