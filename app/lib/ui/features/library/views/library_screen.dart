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
import 'library_chat_screen.dart';

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
          IconButton(
            tooltip: 'Ask your library',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LibraryChatScreen()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            108 + (vm.availableTags.isEmpty || vm.searching ? 0 : 46),
          ),
          child: Column(
            children: [
              _SearchField(
                query: vm.query,
                busy: vm.searchBusy,
                onChanged: vm.setQuery,
                onClear: vm.clearSearch,
              ),
              _FilterBar(
                selected: vm.filter,
                onSelect: vm.setFilter,
              ),
              if (vm.availableTags.isNotEmpty && !vm.searching)
                _TagBar(
                  tags: vm.availableTags,
                  selected: vm.tagFilter,
                  onSelect: vm.setTagFilter,
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openPaste(context),
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Add link'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.refresh,
        child: _body(context, vm, api),
      ),
    );
  }

  Widget _body(BuildContext context, LibraryViewModel vm, api) {
    // An active search overrides the normal library/status views.
    if (vm.searching) {
      if (vm.searchBusy && vm.results.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (vm.results.isEmpty) {
        return _Message(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          subtitle: 'Nothing in your library matches “${vm.query.trim()}”.',
        );
      }
      return _grid(context, vm.results, vm, api);
    }

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
          subtitle: 'Share or paste any link — a reel, article, or post.',
        );
      case LibraryStatus.idle:
      case LibraryStatus.ready:
        final visible = vm.visibleCards;
        if (visible.isEmpty && vm.tagFilter != null) {
          return _Message(
            icon: Icons.label_off_rounded,
            title: 'No cards tagged “${vm.tagFilter}”',
            subtitle: 'Clear the tag to see your whole library.',
            action: FilledButton(
              onPressed: () => vm.setTagFilter(vm.tagFilter),
              child: const Text('Clear tag'),
            ),
          );
        }
        return _grid(context, visible, vm, api);
    }
  }

  Widget _grid(
      BuildContext context, List cards, LibraryViewModel vm, api) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
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
            Text('Paste a link',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Reel, article, post, or page — any source.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://…',
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

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.query,
    required this.busy,
    required this.onChanged,
    required this.onClear,
  });
  final String query;
  final bool busy;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.page, 4, Insets.page, 4),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {}); // refresh the clear-button affordance
          widget.onChanged(v);
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search your cards',
          prefixIcon: widget.busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search_rounded),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    widget.onClear();
                  },
                ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
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

class _TagBar extends StatelessWidget {
  const _TagBar({
    required this.tags,
    required this.selected,
    required this.onSelect,
  });
  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.page),
        children: [
          for (final tag in tags)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('#$tag'),
                selected: selected == tag,
                onSelected: (_) => onSelect(tag),
                visualDensity: VisualDensity.compact,
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
