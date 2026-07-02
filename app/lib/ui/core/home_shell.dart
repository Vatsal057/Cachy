/// Root navigation shell — responsive.
/// < 600 dp : floating pill bottom nav (mobile / Android).
/// ≥ 600 dp : glass side rail, compact; ≥ 1100 dp : extended with labels.
/// Phosphor icons: regular inactive, fill active.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../features/actions/views/actions_screen.dart';
import '../features/capture/views/capture_sheet.dart';
import '../features/collections/views/collections_screen.dart';
import '../features/concepts/views/concept_detail_screen.dart';
import '../features/feed/views/connections_screen.dart';
import '../features/feed/views/knowledge_feed_screen.dart';
import '../features/graph/views/graph_screen.dart';
import '../features/library/view_models/library_view_model.dart';
import '../features/library/views/library_chat_screen.dart';
import '../features/library/views/library_screen.dart';
import '../features/presenter/agent_bus.dart';
import '../features/presenter/presenter_controller.dart';
import '../features/presenter/presenter_overlay.dart';
import '../features/presenter/presenter_spotlight.dart';
import '../features/profile/views/profile_screen.dart';
import '../features/reader/views/chat_screen.dart';
import '../features/reader/views/rabbit_hole_screen.dart';
import '../features/reader/views/reader_screen.dart';
import '../features/search/views/search_screen.dart';
import '../../data/repositories/card_repository.dart';
import '../../domain/models/concept.dart';
import '../../domain/models/enums.dart';
import 'brand.dart';
import 'content_accent.dart';
import 'theme.dart';
import 'widgets/adaptive_modal.dart';
import 'widgets/glass.dart';
import 'widgets/selection_action_bar.dart';

// ── Shared nav definitions ─────────────────────────────────────────────────── //

class _NavDef {
  const _NavDef({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final PhosphorIconData icon;
  final PhosphorIconData activeIcon;
  final String label;
}

const _navItems = [
  _NavDef(icon: PhosphorIconsRegular.house,      activeIcon: PhosphorIconsFill.house,      label: 'HOME'),
  _NavDef(icon: PhosphorIconsRegular.folder,     activeIcon: PhosphorIconsFill.folder,     label: 'FOLDERS'),
  _NavDef(icon: PhosphorIconsRegular.listChecks, activeIcon: PhosphorIconsFill.listChecks, label: 'TO-DO'),
  _NavDef(icon: PhosphorIconsRegular.cardsThree, activeIcon: PhosphorIconsFill.cardsThree, label: 'FEED'),
  _NavDef(icon: PhosphorIconsRegular.user,       activeIcon: PhosphorIconsFill.user,       label: 'YOU'),
];

// ── Shell ──────────────────────────────────────────────────────────────────── //

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    LibraryScreen(),     // 0 — HOME
    CollectionsScreen(), // 1 — FOLDERS
    ActionsScreen(),     // 2 — TO-DO
    KnowledgeFeedScreen(inShell: true), // 3 — FEED
    ProfileScreen(),     // 4 — YOU
  ];

  // Present mode: a self-driving spoken tour that navigates the app and answers
  // audience questions. While active, Graph/Search render in-body (not pushed)
  // so the presenter control bar stays visible on top.
  PresenterController? _presenter;
  Widget? _presenterScreen; // GraphScreen/SearchScreen shown during the tour

  // Spotlight anchor for the nav (bottom pill / side rail — only one mounted).
  final GlobalKey _navKey = GlobalKey();

  // Per-tab anchors so the presenter's cursor lands on the exact tab it taps,
  // and the plus button so "add something" reads as a real click.
  static const _navSpotlightIds = ['nav.home', 'nav.folders', 'nav.todo', 'nav.feed', 'nav.you'];
  final List<GlobalKey> _navItemKeys =
      List.generate(_navSpotlightIds.length, (_) => GlobalKey());
  final GlobalKey _plusKey = GlobalKey();

  void _startPresenting() {
    final repo = context.read<CardRepository>();
    final bus = context.read<AgentBus>()
      ..registerSpotlight('nav', _navKey)
      ..registerSpotlight('home.plus', _plusKey)
      ..onNavigate = _goToView
      ..onOpenCard = _openCardInPresenter
      ..onCreateCard = _createCardInPresenter
      ..onOpenConcept = _openConceptInPresenter
      ..onOpenRabbitHole = _openRabbitHoleInPresenter
      ..onOpenCardChat = _openCardChatInPresenter
      ..onOpenLibraryChat = _openLibraryChatInPresenter;
    for (var i = 0; i < _navSpotlightIds.length; i++) {
      bus.registerSpotlight(_navSpotlightIds[i], _navItemKeys[i]);
    }
    final controller = PresenterController(repository: repo, bus: bus);
    setState(() => _presenter = controller);
    controller.addListener(_onPresenterChanged);
    controller.start();
  }

  /// Open a card in the reader as a presenter overlay (kept under the agent
  /// glyph, not pushed as a route) so the agent stays in control.
  Future<void> _openCardInPresenter(String cardId) async {
    if (!mounted) return;
    setState(() => _presenterScreen = ReaderScreen(cardId: cardId));
  }

  /// Open a concept's detail under the glyph (definition is generated by the
  /// agent before opening so it shows immediately).
  Future<void> _openConceptInPresenter(String conceptId, String name) async {
    if (!mounted) return;
    setState(() => _presenterScreen =
        ConceptDetailScreen(entry: ConceptEntry(id: conceptId, name: name)));
  }

  /// Open the rabbit-hole explorer under the glyph, seeded with a topic it
  /// auto-explores.
  Future<void> _openRabbitHoleInPresenter(String cardId, String seed) async {
    if (!mounted) return;
    setState(() => _presenterScreen = RabbitHoleScreen(
          cardId: cardId,
          seed: seed,
          accent: ContentAccent.of(ContentType.other),
        ));
  }

  /// Open the grounded per-card chat under the glyph, seeded with a question it
  /// auto-asks.
  Future<void> _openCardChatInPresenter(
      String cardId, String title, String seed) async {
    if (!mounted) return;
    setState(() =>
        _presenterScreen = ChatScreen(cardId: cardId, title: title, seed: seed));
  }

  /// Open the whole-library chat under the glyph, seeded with a question.
  Future<void> _openLibraryChatInPresenter(String seed) async {
    if (!mounted) return;
    setState(() => _presenterScreen = LibraryChatScreen(seedQuery: seed));
  }

  /// Submit a URL to the live pipeline and open the streaming card so the
  /// audience watches it fill in.
  Future<String?> _createCardInPresenter(String url) async {
    final repo = context.read<CardRepository>();
    try {
      final result = await repo.share(url);
      if (mounted && result.cardId.isNotEmpty) {
        setState(() => _presenterScreen = ReaderScreen(cardId: result.cardId));
      }
      return result.cardId;
    } catch (e, st) {
      // Live demo: don't crash the tour if the pipeline is down, but the
      // failure shouldn't vanish silently either.
      debugPrint('[Presenter] create_card($url) failed: $e');
      debugPrintStack(stackTrace: st, label: '[Presenter] create_card');
      return null;
    }
  }

  void _onPresenterChanged() {
    if (_presenter?.phase == PresenterPhase.done) {
      final c = _presenter;
      c?.removeListener(_onPresenterChanged);
      final bus = context.read<AgentBus>()
        ..unregisterSpotlight('nav', _navKey)
        ..unregisterSpotlight('home.plus', _plusKey);
      for (var i = 0; i < _navSpotlightIds.length; i++) {
        bus.unregisterSpotlight(_navSpotlightIds[i], _navItemKeys[i]);
      }
      setState(() {
        _presenter = null;
        _presenterScreen = null;
      });
      c?.dispose();
    }
  }

  /// Navigation the agent drives. Tabs switch the shell; graph/search/catalog/
  /// concepts/reader render in-body under the agent glyph.
  void _goToView(String view) {
    setState(() {
      switch (view) {
        case 'feed':
          _presenterScreen = null;
          _index = 3;
        case 'collections':
          _presenterScreen = null;
          _index = 1;
        case 'actions':
          _presenterScreen = null;
          _index = 2;
        case 'profile':
          _presenterScreen = null;
          _index = 4;
        case 'graph':
          _presenterScreen = const GraphScreen();
        case 'search':
          _presenterScreen = const SearchScreen();
        case 'catalog':
          // Concepts and Catalog are the library's own top tabs — flip the real
          // tab (via the hook the library registers) instead of overlaying a
          // separate screen, so it reads as a tap on the segment.
          _presenterScreen = null;
          _index = 0;
          context.read<AgentBus>().onLibraryTab?.call(2);
        case 'concepts':
          _presenterScreen = null;
          _index = 0;
          context.read<AgentBus>().onLibraryTab?.call(1);
        case 'connections':
          _presenterScreen = const ConnectionsScreen();
        case 'library':
        default:
          _presenterScreen = null;
          _index = 0;
          context.read<AgentBus>().onLibraryTab?.call(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LibraryViewModel>(
      create: (ctx) =>
          LibraryViewModel(repository: ctx.read())..load(),
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => showCaptureSheet(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => showCaptureSheet(context),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => _select(0),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _select(0),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => _select(1),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _select(1),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => _select(2),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _select(2),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => _select(3),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () => _select(3),
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () => _select(4),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () => _select(4),
        // 6/7 push Search/Graph (not shell tabs) — used by the presenter agent
        // to switch the visible screen live during a demo Q&A.
        const SingleActivator(LogicalKeyboardKey.digit6, meta: true): () => _openSearch(context),
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () => _openSearch(context),
        const SingleActivator(LogicalKeyboardKey.digit7, meta: true): () => _openGraph(context),
        const SingleActivator(LogicalKeyboardKey.digit7, control: true): () => _openGraph(context),
      },
      child: Focus(
        autofocus: true,
        // Builder gives _mobileShell / _desktopShell a context that is a
        // descendant of the ChangeNotifierProvider<LibraryViewModel> created
        // in build(), so context.watch<LibraryViewModel>() works correctly.
        child: Builder(
          builder: (innerCtx) => LayoutBuilder(
            builder: (_, constraints) => constraints.maxWidth >= Insets.desktop
                ? _desktopShell(innerCtx)
                : _mobileShell(innerCtx),
          ),
        ),
      ),
    );
  }

  Widget _mobileShell(BuildContext context) {
    // On mobile, when the library has an active card selection, replace the
    // FAB and bottom nav with the SelectionActionBar so nothing overlaps.
    final vm = context.watch<LibraryViewModel>();
    final selecting = _index == 0 && vm.selectionActive;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          IndexedStack(index: _index, children: _screens),
          if (_presenterScreen != null) Positioned.fill(child: _presenterScreen!),
          ..._presenterLayers(context),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: selecting
          ? null
          : KeyedSubtree(
              key: _plusKey,
              child: _CaptureButton(onTap: () => showCaptureSheet(context)),
            ),
      bottomNavigationBar: selecting
          ? _SelectionNavSlot(
              vm: vm,
              onConfirmDelete: () => _confirmBulkDelete(context, vm),
            )
          : KeyedSubtree(
              key: _navKey,
              child: _GlassNav(
                index: _index,
                onSelect: _select,
                itemKeys: _navItemKeys,
              ),
            ),
    );
  }

  Future<void> _confirmBulkDelete(
      BuildContext context, LibraryViewModel vm) async {
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
      await vm.bulkDelete();
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

  Widget _desktopShell(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          Positioned.fill(
            child: Row(
              children: [
                KeyedSubtree(
                  key: _navKey,
                  child: _GlassRail(
                    index: _index,
                    onSelect: _select,
                    onCapture: () => showCaptureSheet(context),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      IndexedStack(index: _index, children: _screens),
                      if (_presenterScreen != null)
                        Positioned.fill(child: _presenterScreen!),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ..._presenterLayers(context),
        ],
      ),
    );
  }

  /// Overlay layers shared by both shells: the control bar while presenting, or a
  /// "Present" launch chip when idle.
  List<Widget> _presenterLayers(BuildContext context) {
    if (_presenter != null) {
      return [
        PresenterSpotlight(
          controller: _presenter!,
          bus: context.read<AgentBus>(),
        ),
        PresenterOverlay(controller: _presenter!),
      ];
    }
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _PresentButton(onTap: _startPresenting),
            ),
          ),
        ),
      ),
    ];
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openGraph(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GraphScreen()));
  }
}

// ── "Present" launch chip ──────────────────────────────────────────────────── //

class _PresentButton extends StatelessWidget {
  const _PresentButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.slideshow_rounded, size: 18, color: theme.colorScheme.onPrimary),
              const SizedBox(width: 6),
              Text('Present',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Desktop glass side rail ────────────────────────────────────────────────── //

class _GlassRail extends StatelessWidget {
  const _GlassRail({
    required this.index,
    required this.onSelect,
    required this.onCapture,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final extended = width >= 1100;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Brand.glassFill(b),
            border: Border(
              right: BorderSide(color: Brand.glassBorder(b), width: 0.8),
            ),
          ),
          child: SafeArea(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: index,
              onDestinationSelected: onSelect,
              extended: extended,
              minWidth: 72,
              minExtendedWidth: 180,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              selectedIconTheme: IconThemeData(color: scheme.primary),
              unselectedIconTheme:
                  IconThemeData(color: scheme.onSurfaceVariant),
              selectedLabelTextStyle: Brand.label(
                size: 10,
                color: scheme.primary,
                weight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
              unselectedLabelTextStyle: Brand.label(
                size: 10,
                color: scheme.onSurfaceVariant,
                weight: FontWeight.w500,
                letterSpacing: 0.7,
              ),
              useIndicator: true,
              indicatorColor: scheme.primary.withValues(alpha: 0.10),
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                child: Tooltip(
                  message: 'New capture (⌘N)',
                  child: _CaptureButton(onTap: onCapture),
                ),
              ),
              destinations: [
                for (final item in _navItems)
                  NavigationRailDestination(
                    icon: Tooltip(
                      message: item.label,
                      child: PhosphorIcon(item.icon, size: 22),
                    ),
                    selectedIcon: Tooltip(
                      message: item.label,
                      child: PhosphorIcon(item.activeIcon, size: 22),
                    ),
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile floating pill nav ───────────────────────────────────────────────── //

class _GlassNav extends StatelessWidget {
  const _GlassNav({
    required this.index,
    required this.onSelect,
    this.itemKeys = const [],
  });
  final int index;
  final ValueChanged<int> onSelect;

  /// Per-tab spotlight anchors so the presenter's cursor lands on the exact
  /// tab it taps. Empty when not presenting.
  final List<GlobalKey> itemKeys;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.07),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Brand.glassFill(b),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Brand.glassBorder(b), width: 0.8),
              ),
              child: SizedBox(
                height: 64,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _navItems.length; i++)
                      Expanded(
                        child: KeyedSubtree(
                          key: i < itemKeys.length ? itemKeys[i] : null,
                          child: _NavBtn(
                            def: _navItems[i],
                            selected: index == i,
                            onTap: () => onSelect(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.def,
    required this.selected,
    required this.onTap,
  });
  final _NavDef def;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Tooltip(
      message: def.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.10 : 1.0,
                duration: Motion.fast,
                curve: Motion.spring,
                child: PhosphorIcon(
                  selected ? def.activeIcon : def.icon,
                  size: 22,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                def.label,
                style: Brand.label(
                  size: 9,
                  color: color,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Selection nav slot — replaces the pill nav on mobile during selection ─── //

/// Fills the same visual slot as [_GlassNav] but shows [SelectionActionBar]
/// instead. Using `bottomNavigationBar` ensures it sits above the system
/// navigation area automatically and nothing overlaps the FAB slot (which is
/// also hidden during selection).
class _SelectionNavSlot extends StatelessWidget {
  const _SelectionNavSlot({
    required this.vm,
    required this.onConfirmDelete,
  });
  final LibraryViewModel vm;
  final VoidCallback onConfirmDelete;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 12),
      child: SelectionActionBar(
        selectedCount: vm.selectedCount,
        onClose: vm.clearSelection,
        onMoveToFolder: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Move to Folder coming soon')),
        ),
        onDeleteSelected: onConfirmDelete,
      ),
    );
  }
}

class _CaptureButton extends StatefulWidget {
  const _CaptureButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.08 : 1.0,
          duration: Motion.fast,
          curve: Motion.spring,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: _hovered ? 0.45 : 0.28),
                  blurRadius: _hovered ? 44 : 36,
                  spreadRadius: _hovered ? 8 : 6,
                ),
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: PhosphorIcon(
              PhosphorIconsRegular.plus,
              color: scheme.onPrimary,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
