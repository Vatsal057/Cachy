/// The library: a browsable wall of card faces (docs/06), not a feed of text.
/// Two segments — Cards (the grid) and To-do (actions followed off reels, folded
/// in from the old Actions tab). Branded chrome (wordmark, gradient tab
/// indicator), designed empty/loading/error/offline states, and a staggered
/// tile entrance. Capture lives in the shell's center button; search opens a
/// dedicated screen. Tap a tile → reader via a shared-element face transition.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/highlight_store.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/highlight.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_tiles.dart';
import '../../../core/widgets/spot_art.dart';
import '../../capture/views/capture_sheet.dart';
import '../../concepts/views/concepts_screen.dart';
import '../../graph/views/graph_screen.dart';
import '../../library/views/library_chat_screen.dart';
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
    final isDesktop = MediaQuery.sizeOf(context).width >= Insets.desktop;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: Insets.page,
          title: const CachyWordmark(size: 24),
          actions: [
            if (vm.offline)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: 'Offline — showing saved cards',
                  child: PhosphorIcon(PhosphorIconsRegular.cloudSlash, size: 20),
                ),
              ),
            IconButton(
              tooltip: 'Chat',
              icon: const PhosphorIcon(PhosphorIconsRegular.chats),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryChatScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Search',
              icon: const PhosphorIcon(PhosphorIconsRegular.magnifyingGlass),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 360 : double.infinity),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(3),
                      labelColor: scheme.onSurface,
                      unselectedLabelColor: scheme.onSurfaceVariant,
                      labelStyle: Brand.label(size: 12, weight: FontWeight.w700),
                      unselectedLabelStyle: Brand.label(size: 12, weight: FontWeight.w500),
                      tabs: const [
                        Tab(text: 'CARDS'),
                        Tab(text: 'CONCEPTS'),
                        Tab(text: 'GRAPH'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _CardsTab(),
            ConceptsScreen(),
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
    final scheme = Theme.of(context).colorScheme;

    final list = RefreshIndicator(
      color: scheme.primary,
      onRefresh: vm.refresh,
      child: _body(context, vm, api),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Insets.splitPane) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 420, child: list),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: vm.selectedCardId == null
                  ? const _ReaderPaneEmpty()
                  : ReaderScreen(
                      key: ValueKey(vm.selectedCardId),
                      cardId: vm.selectedCardId!,
                      embedded: true,
                      onClose: () => vm.selectCard(null),
                    ),
            ),
          ],
        );
      },
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
            halo: true,
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
            const _HighlightsSection(),
            Expanded(
              child: visible.isEmpty
                  ? _scrollable(
                      EmptyState(
                        icon: PhosphorIconsRegular.funnelX,
                        title: 'Nothing here',
                        message: vm.tagFilter != null
                            ? 'No cards tagged "${vm.tagFilter}".'
                            : 'No cards match this filter.',
                        art: const LibrarySpot(),
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
    // Available width, not the window's — this grid may be the narrow pane
    // of a desktop split layout, not the full screen.
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 200).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: cards.length + 1,
          itemBuilder: (ctx, i) {
            if (i == cards.length) {
              return _CtaCard(onTap: () => showCaptureSheet(context));
            }
            final card = cards[i];
            return CardTile(
              card: card,
              api: api,
              onTap: () {
                if (MediaQuery.sizeOf(ctx).width >= Insets.splitPane) {
                  vm.selectCard(card.cardId);
                  return;
                }
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderScreen(cardId: card.cardId),
                  ),
                );
              },
              onDelete: () => vm.delete(card.cardId),
            );
          },
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────── //
// Highlights section — horizontal scroll of saved highlight cards
// ──────────────────────────────────────────────────────────────────────────── //

class _HighlightsSection extends StatelessWidget {
  const _HighlightsSection();

  @override
  Widget build(BuildContext context) {
    final highlights = context.watch<HighlightStore>().highlights;
    if (highlights.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, 14, Insets.page, 10),
          child: Text(
            'HIGHLIGHTS',
            style: Brand.label(
              size: 10,
              color: scheme.onSurfaceVariant,
              weight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, 0),
            itemCount: highlights.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) => _HighlightCard(highlight: highlights[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 0),
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.highlight});
  final Highlight highlight;

  static const _bgColors = [
    Color(0xFFD9ECCC),
    Color(0xFFFBEFCC),
    Color(0xFFCCD8EC),
    Color(0xFFECCCD4),
    Color(0xFFDACCEC),
  ];
  static const _fgColors = [
    Color(0xFF2D5A1E),
    Color(0xFF5A4A10),
    Color(0xFF1E3A5A),
    Color(0xFF5A1E2D),
    Color(0xFF3A1E5A),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = highlight.colorIndex % _bgColors.length;
    final bg = _bgColors[idx];
    final fg = _fgColors[idx];
    final store = context.read<HighlightStore>();
    final title = highlight.cardTitle.length > 22
        ? '${highlight.cardTitle.substring(0, 22)}…'
        : highlight.cardTitle;

    return Dismissible(
      key: Key(highlight.id),
      direction: DismissDirection.up,
      onDismissed: (_) => store.delete(highlight.id),
      child: Container(
        width: 158,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                highlight.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: fg,
                  height: 1.4,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '— $title',
              style: Brand.label(
                size: 9,
                color: fg.withValues(alpha: 0.55),
                weight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────── //
// Reader pane placeholder — shown when no card is selected in split-pane mode
// ──────────────────────────────────────────────────────────────────────────── //

class _ReaderPaneEmpty extends StatelessWidget {
  const _ReaderPaneEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(PhosphorIconsRegular.bookOpenText,
              size: 36, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text(
            'Select a card to read',
            style: Brand.label(size: 11, color: scheme.onSurfaceVariant, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────── //
// CTA card — last grid tile, prompts the user to capture more
// ──────────────────────────────────────────────────────────────────────────── //

class _CtaCard extends StatelessWidget {
  const _CtaCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: PhosphorIcon(
                PhosphorIconsRegular.plus,
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Capture\nanother reel',
              textAlign: TextAlign.center,
              style: Brand.label(
                size: 9.5,
                color: scheme.onSurfaceVariant,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
                shape: const StadiumBorder(),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }
}
