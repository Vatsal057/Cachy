/// The Actions hub (docs/13): every to-do you've followed off a reel, grouped by
/// its source card, split into things still to do and things done.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/spot_art.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/actions_view_model.dart';

class ActionsScreen extends StatelessWidget {
  const ActionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ActionsBody(),
      ),
    );
  }
}

class ActionsBody extends StatelessWidget {
  const ActionsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          ActionsViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _ActionsView(),
    );
  }
}

enum _FilterTab { all, todo, done }

class _ActionsView extends StatefulWidget {
  const _ActionsView();

  @override
  State<_ActionsView> createState() => _ActionsViewState();
}

class _ActionsViewState extends State<_ActionsView> {
  _FilterTab _filter = _FilterTab.all;
  final Set<String> _expandedCardIds = {};

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ActionsViewModel>();
    final theme = Theme.of(context);
    final b = theme.brightness;
    final isDark = b == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () => vm.load(showSpinner: false),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Editorial Header ────────────────────────────────────────── //
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 20, Insets.page, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CACHY',
                    style: Brand.label(
                      size: 10,
                      color: Brand.accentFor(b),
                      weight: FontWeight.w700,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Action\nItems',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 38,
                      height: 1.02,
                      letterSpacing: -1.2,
                      color: isDark ? const Color(0xFFF2EFE9) : Brand.ink,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── Filter Pills Row ──────────────────────────────────── //
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        _FilterPill(
                          label: 'All',
                          selected: _filter == _FilterTab.all,
                          onTap: () => setState(() => _filter = _FilterTab.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: 'To Do',
                          selected: _filter == _FilterTab.todo,
                          onTap: () => setState(() => _filter = _FilterTab.todo),
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: 'Done',
                          selected: _filter == _FilterTab.done,
                          onTap: () => setState(() => _filter = _FilterTab.done),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── States (Loading / Empty / Error / Ready) ────────────────── //
          if (vm.status == ActionsStatus.loading || vm.status == ActionsStatus.idle)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (vm.status == ActionsStatus.error)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Message(
                icon: PhosphorIconsRegular.warning,
                text: "Couldn't load your actions",
                onRetry: vm.load,
              ),
            )
          else if (vm.status == ActionsStatus.empty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _Message(
                icon: PhosphorIconsRegular.listChecks,
                art: ActionsSpot(),
                text: 'No actions yet.\nOpen a card and tap "Follow these actions".',
              ),
            )
          else
            _buildGroupedList(context, vm.groups, isDark),

          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Widget _buildGroupedList(BuildContext context, List<ActionGroup> groups, bool isDark) {
    final filteredSections = <_SectionData>[];
    for (final g in groups) {
      final items = switch (_filter) {
        _FilterTab.all => g.items,
        _FilterTab.todo => g.items.where((i) => !i.done).toList(),
        _FilterTab.done => g.items.where((i) => i.done).toList(),
      };
      if (items.isNotEmpty) {
        filteredSections.add(_SectionData(group: g, items: items));
      }
    }

    if (filteredSections.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Insets.page),
          child: Center(
            child: Text(
              _filter == _FilterTab.todo ? 'No pending action items!' : 'No completed items yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Brand.mutedFor(Theme.of(context).brightness)),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) {
          final section = filteredSections[index];
          final card = section.group.card;
          final accent = ContentAccent.of(card.base.contentType);

          final isExpanded = _expandedCardIds.contains(card.cardId);

          return Padding(
            padding: const EdgeInsets.fromLTRB(Insets.page, 14, Insets.page, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Expandable Section Header ───────────────────────────── //
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCardIds.remove(card.cardId);
                      } else {
                        _expandedCardIds.add(card.cardId);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            card.base.oneLiner.isEmpty ? 'Saved Card' : card.base.oneLiner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isDark ? const Color(0xFFE5E2DA) : Brand.ink,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${section.items.length}',
                            style: Brand.label(
                              size: 11,
                              color: isDark ? Colors.white70 : Colors.black87,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Open reel notes',
                          child: InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ReaderScreen(cardId: card.cardId)),
                            ),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: PhosphorIcon(
                                PhosphorIconsRegular.arrowLineUpRight,
                                size: 15,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: isExpanded ? 0.0 : -0.25,
                          duration: Motion.fast,
                          child: PhosphorIcon(
                            PhosphorIconsRegular.caretDown,
                            size: 16,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Collapsible Item Cards List ────────────────────────── //
                AnimatedCrossFade(
                  firstChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      for (final item in section.items)
                        _ActionItemCard(
                          card: card,
                          item: item,
                          accent: accent,
                          isDark: isDark,
                        ),
                    ],
                  ),
                  secondChild: const SizedBox(width: double.infinity, height: 0),
                  crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  duration: Motion.fast,
                ),
              ],
            ),
          );
        },
        childCount: filteredSections.length,
      ),
    );
  }
}

class _SectionData {
  const _SectionData({required this.group, required this.items});
  final ActionGroup group;
  final List<model.ActionItem> items;
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final isDark = b == Brightness.dark;

    final activeBg = isDark ? const Color(0xFFE8C364) : Theme.of(context).colorScheme.primary;
    final activeFg = isDark ? const Color(0xFF181818) : Theme.of(context).colorScheme.onPrimary;

    final inactiveBg = isDark ? const Color(0xFF22211F) : const Color(0xFFEBE5DA);
    final inactiveFg = isDark ? const Color(0xFF9A928A) : const Color(0xFF6B6259);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.spring,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? activeBg : inactiveBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.transparent : (isDark ? Colors.white10 : Colors.black12),
            ),
          ),
          child: Text(
            label,
            style: Brand.label(
              size: 12,
              color: selected ? activeFg : inactiveFg,
              weight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionItemCard extends StatefulWidget {
  const _ActionItemCard({
    required this.card,
    required this.item,
    required this.accent,
    required this.isDark,
  });
  final model.Card card;
  final model.ActionItem item;
  final ContentAccent accent;
  final bool isDark;

  @override
  State<_ActionItemCard> createState() => _ActionItemCardState();
}

class _ActionItemCardState extends State<_ActionItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<ActionsViewModel>();
    final done = widget.item.done;
    final isDark = widget.isDark;
    final accent = widget.accent;

    final bg = isDark ? const Color(0xFF1E1D1B) : const Color(0xFFEFEADF);
    final hoverBg = isDark ? const Color(0xFF262523) : const Color(0xFFE5DFD3);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => vm.toggle(widget.card.cardId, widget.item.id, !done),
        child: AnimatedContainer(
          duration: Motion.fast,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? hoverBg : bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hovered
                  ? accent.color.withValues(alpha: 0.45)
                  : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05)),
              width: _hovered ? 1.2 : 1.0,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: accent.color.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // ── Circle Checkbox ───────────────────────────────────── //
              AnimatedContainer(
                duration: Motion.fast,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? accent.color : Colors.transparent,
                  border: Border.all(
                    color: done ? accent.color : (isDark ? Colors.white30 : Colors.black26),
                    width: 1.5,
                  ),
                ),
                child: done ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              ),
              const SizedBox(width: 14),
              // ── Text ──────────────────────────────────────────────── //
              Expanded(
                child: Text(
                  widget.item.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: done
                            ? (isDark ? Colors.white38 : Colors.black38)
                            : (isDark ? const Color(0xFFECE9E2) : const Color(0xFF22201C)),
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              // ── Source Category Tag Pill ──────────────────────────── //
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2D2B28) : const Color(0xFFE2DDD2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(accent.icon, size: 11, color: isDark ? Colors.white70 : Colors.black87),
                    const SizedBox(width: 5),
                    Text(
                      widget.card.base.contentType.label.toUpperCase(),
                      style: Brand.label(
                        size: 9,
                        color: isDark ? Colors.white70 : Colors.black87,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry, this.art});
  final PhosphorIconData icon;
  final String text;
  final VoidCallback? onRetry;

  /// Optional spot illustration shown in place of the icon.
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          art ??
              PhosphorIcon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
