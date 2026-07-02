/// The library: a browsable wall of card faces (docs/06), not a feed of text.
/// Two segments — Cards (the grid) and To-do (actions followed off reels, folded
/// in from the old Actions tab). Branded chrome (wordmark, gradient tab
/// indicator), designed empty/loading/error/offline states, and a staggered
/// tile entrance. Capture lives in the shell's center button; search opens a
/// dedicated screen. Tap a tile → reader via a shared-element face transition.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/highlight_store.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/highlight.dart';
import '../../../core/app_controller.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/adaptive_modal.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_tiles.dart';
import '../../../core/widgets/selection_action_bar.dart';
import '../../../core/widgets/split_pane.dart';
import '../../../core/widgets/spot_art.dart';
import '../../capture/views/capture_sheet.dart';
import '../../catalog/views/catalog_screen.dart';
import '../../concepts/views/concepts_screen.dart';
import '../../graph/views/graph_screen.dart';
import '../../library/views/library_chat_screen.dart';
import '../../presenter/agent_bus.dart';
import '../../reader/views/reader_screen.dart';
import '../../search/views/search_screen.dart';
import '../view_models/library_view_model.dart';
import 'card_tile.dart';
import 'grid_navigation.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // LibraryViewModel is provided by HomeShell so the shell can also watch
    // selection state for the mobile nav slot. No provider needed here.
    return const _LibraryView();
  }
}

class _LibraryView extends StatefulWidget {
  const _LibraryView();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  // Presenter spotlight anchors: the top segments and top-bar icons the agent
  // taps live here. Registered while mounted; the presenter's cursor resolves
  // them to real geometry.
  final _conceptsTabKey = GlobalKey();
  final _catalogTabKey = GlobalKey();
  final _graphKey = GlobalKey();
  final _chatKey = GlobalKey();
  final _searchKey = GlobalKey();
  AgentBus? _bus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bus != null) return;
    _bus = context.read<AgentBus>()
      ..onLibraryTab = (i) {
        if (i >= 0 && i < _tabs.length) _tabs.animateTo(i);
      }
      ..registerSpotlight('library.tab.concepts', _conceptsTabKey)
      ..registerSpotlight('library.tab.catalog', _catalogTabKey)
      ..registerSpotlight('top.graph', _graphKey)
      ..registerSpotlight('top.chat', _chatKey)
      ..registerSpotlight('top.search', _searchKey);
  }

  @override
  void dispose() {
    _bus
      ?..onLibraryTab = null
      ..unregisterSpotlight('library.tab.concepts', _conceptsTabKey)
      ..unregisterSpotlight('library.tab.catalog', _catalogTabKey)
      ..unregisterSpotlight('top.graph', _graphKey)
      ..unregisterSpotlight('top.chat', _chatKey)
      ..unregisterSpotlight('top.search', _searchKey);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LibraryViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= Insets.desktop;

    return Scaffold(
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
              key: _graphKey,
              tooltip: 'Graph',
              icon: const PhosphorIcon(PhosphorIconsRegular.graph),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GraphScreen()),
              ),
            ),
            IconButton(
              key: _chatKey,
              tooltip: 'Chat',
              icon: const PhosphorIcon(PhosphorIconsRegular.chats),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryChatScreen()),
              ),
            ),
            IconButton(
              key: _searchKey,
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
                      controller: _tabs,
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
                      tabs: [
                        const Tab(text: 'CARDS'),
                        Tab(key: _conceptsTabKey, text: 'CONCEPTS'),
                        Tab(key: _catalogTabKey, text: 'CATALOG'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: const [
            _CardsTab(),
            ConceptsScreen(),
            CatalogScreen(),
          ],
        ),
      );
  }
}

class _CardsTab extends StatefulWidget {
  const _CardsTab();

  @override
  State<_CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends State<_CardsTab> {
  late double _fraction;

  /// Focus nodes for each grid tile (cards + CTA tile at the end).
  final List<FocusNode> _focusNodes = [];

  /// The grid index that most recently received keyboard focus.
  int _lastFocusedIndex = 0;

  // Presenter agent: expose the grid's scroll so the agent can browse the
  // library while narrating.
  final _gridScroll = ScrollController();
  final _firstCardKey = GlobalKey();
  AgentBus? _bus;

  @override
  void initState() {
    super.initState();
    _fraction = context.read<AppController>().splitPaneFraction;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bus != null) return;
    _bus = context.read<AgentBus>()
      ..registerScrollable('library', _gridScroll)
      ..registerSpotlight('card.first', _firstCardKey);
  }

  /// Grows or shrinks [_focusNodes] to exactly [count] nodes.
  /// New nodes are equipped with a listener that updates [_lastFocusedIndex].
  void _ensureFocusNodes(int count) {
    while (_focusNodes.length < count) {
      final index = _focusNodes.length;
      final node = FocusNode();
      // Track which node is focused so arrow-key navigation knows where to start.
      node.addListener(() {
        if (node.hasFocus) _lastFocusedIndex = index;
      });
      _focusNodes.add(node);
    }
    while (_focusNodes.length > count) {
      _focusNodes.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    _bus
      ?..unregisterScrollable('library', _gridScroll)
      ..unregisterSpotlight('card.first', _firstCardKey);
    _gridScroll.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

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

    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          final vm = context.read<LibraryViewModel>();
          if (vm.selectionActive) vm.clearSelection();
        },
      },
      child: Focus(
        autofocus: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < Insets.splitPane) return list;
            return SplitPane(
              fraction: _fraction,
              list: list,
              detail: vm.selectedCardId == null
                  ? const _ReaderPaneEmpty()
                  : ReaderScreen(
                      key: ValueKey(vm.selectedCardId),
                      cardId: vm.selectedCardId!,
                      embedded: true,
                      onClose: () => vm.selectCard(null),
                    ),
              onFractionChanged: (f) {
                setState(() => _fraction = f);
                context.read<AppController>().setSplitPaneFraction(f);
              },
            );
          },
        ),
      ),
    );

    if (!vm.selectionActive) return content;

    // On desktop/wide viewports, float the bar inside the content area.
    // On mobile the shell's bottomNavigationBar slot handles it instead
    // (avoids overlapping the FAB and nav bar).
    final isDesktop = MediaQuery.sizeOf(context).width >= Insets.desktop;
    if (!isDesktop) return content;

    // Desktop: overlay the action bar at the bottom of the content area.
    return Stack(
      children: [
        content,
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: SelectionActionBar(
            selectedCount: vm.selectedCount,
            onClose: () => context.read<LibraryViewModel>().clearSelection(),
            onMoveToFolder: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Move to Folder coming soon')),
              );
            },
            onDeleteSelected: () => _confirmBulkDelete(context),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmBulkDelete(BuildContext context) async {
    final vm = context.read<LibraryViewModel>();
    final count = vm.selectedCount;
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
    if (ok == true && context.mounted) {
      await context.read<LibraryViewModel>().bulkDelete();
      // If bulkDelete surfaced an error (vm.error != null), show it.
      if (context.mounted) {
        final error = context.read<LibraryViewModel>().error;
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $error')),
          );
        }
      }
    }
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

        // Sync focus node pool to the current tile count (cards + CTA).
        _ensureFocusNodes(cards.length + 1);

        return Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.arrowUp):
                const _GridMoveIntent(GridDirection.up),
            LogicalKeySet(LogicalKeyboardKey.arrowDown):
                const _GridMoveIntent(GridDirection.down),
            LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                const _GridMoveIntent(GridDirection.left),
            LogicalKeySet(LogicalKeyboardKey.arrowRight):
                const _GridMoveIntent(GridDirection.right),
          },
          child: Actions(
            actions: {
              _GridMoveIntent: CallbackAction<_GridMoveIntent>(
                onInvoke: (intent) {
                  final current =
                      _lastFocusedIndex.clamp(0, cards.length);
                  final next = nextGridIndex(
                    columnCount: cols,
                    itemCount: cards.length + 1,
                    currentIndex: current,
                    direction: intent.direction,
                  );
                  if (next >= 0 && next < _focusNodes.length) {
                    _focusNodes[next].requestFocus();
                  }
                  _lastFocusedIndex = next;
                  return null;
                },
              ),
            },
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: GridView.builder(
                controller: _gridScroll,
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
                  final isDesktopPlatform = !kIsWeb &&
                      (Platform.isMacOS ||
                          Platform.isWindows ||
                          Platform.isLinux);
                  final tile = CardTile(
                    focusNode: _focusNodes[i],
                    card: card,
                    api: api,
                    selected: vm.isSelected(card.cardId),
                    onEnterSelectionMode: () =>
                        vm.enterSelectionMode(card.cardId),
                    onSelectToggle: () => vm.toggleSelection(card.cardId),
                    onRangeSelect: () => vm.selectRange(card.cardId),
                    onTap: () {
                      // Desktop: check keyboard modifiers for selection
                      if (isDesktopPlatform && vm.selectionActive) {
                        vm.toggleSelection(card.cardId);
                        return;
                      }
                      if (isDesktopPlatform &&
                          HardwareKeyboard.instance.isControlPressed) {
                        vm.toggleSelection(card.cardId);
                        return;
                      }
                      if (isDesktopPlatform &&
                          HardwareKeyboard.instance.isMetaPressed) {
                        vm.toggleSelection(card.cardId);
                        return;
                      }
                      if (isDesktopPlatform &&
                          HardwareKeyboard.instance.isShiftPressed) {
                        vm.selectRange(card.cardId);
                        return;
                      }
                      // Mobile: if in selection mode, tap = toggle
                      if (!isDesktopPlatform && vm.selectionMode) {
                        vm.toggleSelection(card.cardId);
                        return;
                      }
                      // Normal open behavior
                      if (MediaQuery.sizeOf(ctx).width >= Insets.splitPane) {
                        vm.selectCard(card.cardId);
                        return;
                      }
                      Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ReaderScreen(cardId: card.cardId),
                        ),
                      );
                    },
                    onDelete: () => vm.delete(card.cardId),
                  );
                  // Anchor the first tile so the presenter's cursor lands on a
                  // real card before opening it.
                  return i == 0
                      ? KeyedSubtree(key: _firstCardKey, child: tile)
                      : tile;
                },
              ),
            ),
          ),
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

// ──────────────────────────────────────────────────────────────────────────── //
// Grid keyboard navigation intent — used by Shortcuts + Actions to move focus
// ──────────────────────────────────────────────────────────────────────────── //

/// Intent fired by the arrow-key [Shortcuts] binding around the library grid.
/// The [Actions] handler resolves the target index via [nextGridIndex] and
/// requests focus on the corresponding [FocusNode].
class _GridMoveIntent extends Intent {
  const _GridMoveIntent(this.direction);

  /// The direction the user wants to move focus.
  final GridDirection direction;
}
