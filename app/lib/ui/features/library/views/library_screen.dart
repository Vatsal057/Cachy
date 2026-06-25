/// The library: a browsable wall of card faces (docs/06), not a feed of text.
/// Grid of [CardTile]s with state badges, state filter, pull-to-refresh, and a
/// paste entry point (link-paste fallback, P1).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/enums.dart';
import '../../../core/theme.dart';
import '../../reader/views/reader_screen.dart';
import '../../share/views/share_screen.dart';
import '../view_models/library_view_model.dart';
import 'card_tile.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          LibraryViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _LibraryView(),
    );
  }
}

class _LibraryView extends StatelessWidget {
  const _LibraryView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LibraryViewModel>();
    final api = context.read<CardRepository>().api;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cachy'),
        actions: [
          if (vm.offline)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Offline — showing saved cards',
                child: Icon(Icons.cloud_off_rounded, size: 20),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _FilterBar(
            selected: vm.filter,
            onSelect: vm.setFilter,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPaste(context),
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Add reel'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.refresh,
        child: _body(context, vm, api),
      ),
    );
  }

  Widget _body(BuildContext context, LibraryViewModel vm, api) {
    switch (vm.status) {
      case LibraryStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LibraryStatus.error:
        return _Message(
          icon: Icons.wifi_off_rounded,
          title: "Can't reach the backend",
          subtitle: vm.error ?? '',
          action: FilledButton(onPressed: vm.load, child: const Text('Retry')),
        );
      case LibraryStatus.empty:
        return const _Message(
          icon: Icons.video_library_outlined,
          title: 'No cards yet',
          subtitle: 'Share a reel or paste a link to make your first card.',
        );
      case LibraryStatus.idle:
      case LibraryStatus.ready:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
              Insets.page, 12, Insets.page, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: vm.cards.length,
          itemBuilder: (ctx, i) {
            final card = vm.cards[i];
            return CardTile(
              card: card,
              api: api,
              onTap: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(cardId: card.cardId),
                ),
              ),
              onDelete: () => vm.delete(card.cardId),
            );
          },
        );
    }
  }

  Future<void> _openPaste(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste a reel link',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://instagram.com/reel/…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Make card'),
            ),
          ],
        ),
      ),
    );
    if (url == null || url.trim().isEmpty || !context.mounted) return;
    final libraryVm = context.read<LibraryViewModel>();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShareScreen(sharedUrl: url.trim())),
    );
    await libraryVm.refresh();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});
  final CardState? selected;
  final ValueChanged<CardState?> onSelect;

  @override
  Widget build(BuildContext context) {
    final filters = <(String, CardState?)>[
      ('All', null),
      ('Ready', CardState.ready),
      ('Working', CardState.processing),
      ('Failed', CardState.failed),
    ];
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.page),
        children: [
          for (final (label, state) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: selected == state,
                onSelected: (_) => onSelect(state),
              ),
            ),
        ],
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
      // ListView so RefreshIndicator works even on the empty/error state.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Icon(icon, size: 52, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge),
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
