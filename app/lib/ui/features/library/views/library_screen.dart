/// The library: a browsable wall of card faces (docs/06), not a feed of text.
/// Two segments — Cards (the grid) and To-do (actions followed off reels, folded
/// in from the old Actions tab). Branded chrome (wordmark, gradient tab
/// indicator), designed empty/loading/error/offline states, and a staggered
/// tile entrance. Capture lives in the shell's center button; search opens a
/// dedicated screen. Tap a tile → reader via a shared-element face transition.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/enums.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_tiles.dart';
import '../../capture/views/capture_sheet.dart';
import '../../graph/views/graph_screen.dart';
import '../../reader/views/reader_screen.dart';
import '../../search/views/search_screen.dart';
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
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: Insets.page,
          title: const CachyWordmark(size: 24),
          actions: [
            if (vm.offline)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Offline — showing saved cards',
                  child: Icon(Icons.cloud_off_rounded, size: 20),
                ),
              ),
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorColor: scheme.primary,
            labelColor: scheme.onSurface,
            unselectedLabelColor: scheme.onSurfaceVariant,
            labelStyle: Brand.label(size: 13, weight: FontWeight.w700),
            unselectedLabelStyle: Brand.label(size: 13, weight: FontWeight.w500),
            tabs: const [
              Tab(text: 'CARDS'),
              Tab(text: 'GRAPH'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CardsTab(),
            GraphScreen(showAppBar: false),
          ],
        ),
      ),
    );
  }
}

class _CardsTab extends StatelessWidget {
  const _CardsTab();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LibraryViewModel>();
    final api = context.read<CardRepository>().api;

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: vm.refresh,
      child: _body(context, vm, api),
    );
  }

  Widget _body(BuildContext context, LibraryViewModel vm, dynamic api) {
    switch (vm.status) {
      case LibraryStatus.loading:
        return const LoadingTiles();
      case LibraryStatus.error:
        return _scrollable(
          ErrorState(
            title: "Can't reach Cachy",
            message: vm.error ?? 'Check your connection and try again.',
            onRetry: vm.load,
          ),
        );
      case LibraryStatus.empty:
        return _scrollable(
          EmptyState(
            showGlyph: true,
            title: 'Your shelf is empty',
            message:
                'Share a reel to Cachy — or paste a link — and watch it become '
                'a card you can actually use.',
            actionLabel: 'Capture your first reel',
            onAction: () => showCaptureSheet(context),
          ),
        );
      case LibraryStatus.idle:
      case LibraryStatus.ready:
        final visible = vm.visibleCards;
        return Column(
          children: [
            if (vm.availableTags.isNotEmpty)
              _TagBar(
                tags: vm.availableTags,
                selected: vm.tagFilter,
                onSelect: vm.setTagFilter,
              ),
            Expanded(
              child: visible.isEmpty
                  ? _scrollable(
                      EmptyState(
                        icon: Icons.filter_alt_off_rounded,
                        title: 'Nothing here',
                        message: vm.tagFilter != null
                            ? 'No cards tagged "${vm.tagFilter}".'
                            : 'No cards match this filter.',
                      ),
                    )
                  : _grid(context, visible, vm, api),
            ),
          ],
        );
    }
  }

  // Keeps empty/error states pull-to-refreshable.
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

  Widget _grid(
      BuildContext context, List<model.Card> cards, LibraryViewModel vm, dynamic api) {
    final width = MediaQuery.of(context).size.width;
    final cols = (width / 200).floor().clamp(2, 5);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        final tile = CardTile(
          card: card,
          api: api,
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => ReaderScreen(cardId: card.cardId),
            ),
          ),
          onDelete: () => vm.delete(card.cardId),
        );
        return tile;
      },
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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Insets.page, 2, Insets.page, 4),
        children: [
          for (final tag in tags)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(tag.toUpperCase()),
                selected: selected == tag,
                onSelected: (_) => onSelect(tag),
                selectedColor: scheme.primary,
                backgroundColor: scheme.surface,
                labelStyle: Brand.label(
                  size: 10,
                  color: selected == tag ? scheme.onPrimary : scheme.onSurfaceVariant,
                  weight: selected == tag ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }
}
