/// The reader (docs/06): opens directly on a card, even mid-processing, and
/// renders top-down as content arrives — one_liner + tldr first, blocks beneath,
/// face attaches with extraction. Editorial layout — eyebrow labels, left-border
/// callouts, category pills, meta strip — inspired by calm magazine structure.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/highlight_store.dart';
import '../../../../domain/models/artifact.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/concept.dart';
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/highlight.dart';
import '../../../../domain/models/pipeline_event.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/card_face.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/pipeline_progress.dart';
import '../../blocks/block_renderer.dart';
import '../../catalog/services/artifact_lookup.dart';
import '../../concepts/views/concept_detail_screen.dart';
import '../view_models/reader_view_model.dart';
import 'insight_section.dart';
import 'primary_action_bar.dart';

class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.cardId});
  final String cardId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => ReaderViewModel(
        repository: ctx.read<CardRepository>(),
        cardId: cardId,
      )..init(),
      child: const _ReaderView(),
    );
  }
}

class _ReaderView extends StatelessWidget {
  const _ReaderView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReaderViewModel>();
    final api = context.read<CardRepository>().api;

    if (vm.isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    if (vm.error != null && vm.card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          title: "Couldn't load this card",
          message: 'It may still be processing, or the connection dropped.',
          onRetry: vm.retry,
        ),
      );
    }

    final card = vm.card!;
    final accent = ContentAccent.of(card.base.contentType);
    final readMins = _estimateReadMinutes(card);
    final highlightStore = context.read<HighlightStore>();

    void onHighlight(String text) {
      highlightStore.add(Highlight(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        cardId: card.cardId,
        cardTitle: card.base.oneLiner,
        text: text,
        colorIndex: highlightStore.highlights.length % 5,
        createdAt: DateTime.now(),
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to highlights'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _FaceAppBar(card: card, api: api, accent: accent),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Insets.readingColumn),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.page, 22, Insets.page, 128),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Slim pipeline status — visible while building
                      if (card.isProcessing) ...[
                        _BuildingStatusStrip(vm: vm),
                        const SizedBox(height: 4),
                      ],

                      // Category chips: content type pill + tag pills
                      _CategoryBar(
                        accent: accent,
                        contentLabel: card.base.contentType.label,
                        tags: card.base.tags,
                      ),
                      const SizedBox(height: 20),

                      // Headline — skeleton while building, fades in on arrival
                      if (card.base.oneLiner.isNotEmpty) ...[
                        _fadeIn(Text(card.base.oneLiner,
                            style: Theme.of(context).textTheme.headlineLarge)),
                        const SizedBox(height: 12),
                      ] else if (card.isProcessing) ...[
                        const _SkeletonHeadline(),
                        const SizedBox(height: 12),
                      ],

                      // Meta strip: read time badge
                      _MetaStrip(readMinutes: readMins),

                      const SizedBox(height: 28),

                      if (card.isFailed) _FailedPanel(card: card),

                      // CORE TAKEAWAY — skeleton while building, fades in on arrival
                      if (card.base.tldr.isNotEmpty)
                        _fadeIn(_CoreTakeawayCard(text: card.base.tldr, accent: accent))
                      else if (card.isProcessing)
                        const _SkeletonTldrCard(),

                      // Ornamental divider + highlight hint (once card is ready)
                      if (card.isReady && card.blocks.isNotEmpty) ...[
                        const _OrnamentalDivider(),
                        const _HighlightHint(),
                      ],

                      // Structured blocks — skeleton while building, fades in on arrival
                      if (card.blocks.isNotEmpty) ...[
                        _fadeIn(BlockList(
                          blocks: card.blocks,
                          onToggleChecklist: vm.toggleChecklistItem,
                          onToggleStep: vm.toggleStep,
                          onOpenUrl: (url) => _copyUrl(context, url),
                          artifacts: vm.artifacts,
                          onOpenArtifact: (e) => openLookup(e),
                          onHighlight: card.isReady ? onHighlight : null,
                        )),
                        if (card.isProcessing) ...[
                          const SizedBox(height: 12),
                          const _SkeletonBox(height: 70, radius: Insets.radius),
                        ],
                      ] else if (card.isProcessing)
                        const _SkeletonBlocks(),

                      // Skeleton placeholders for insight/refs/concepts (arrive at done)
                      if (card.isProcessing) const _SkeletonBottomSections(),

                      // DO THIS NOW — action items
                      if (card.isReady && card.actionItems.isPresent)
                        _ActionItemsSection(card: card, accent: accent, vm: vm),

                      // Deep-analysis layer
                      if (card.isReady &&
                          card.insight != null &&
                          card.insight!.hasContent)
                        InsightSection(
                          insight: card.insight!,
                          accent: accent,
                          cardId: card.cardId,
                          cardTitle: card.base.oneLiner,
                          readMinutes: readMins,
                        ),

                      // Referenced catalog items
                      if (card.isReady) _ReferencesStrip(entries: vm.artifacts),

                      // Concepts this card contributed to
                      if (card.isReady) _ConceptsStrip(entries: vm.concepts),

                      if (card.source.creator != null) ...[
                        const SizedBox(height: 8),
                        _SourceLine(card: card),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomSheet: card.isReady ? PrimaryActionBar(card: card) : null,
    );
  }

  int _estimateReadMinutes(model.Card card) {
    var words = card.base.tldr.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    for (final b in card.rawBlocks) {
      void add(Object? v) {
        if (v is String) words += v.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      }
      add(b['text']);
      for (final it in (b['items'] as List?) ?? const []) {
        add(it is Map ? it['text'] : it);
      }
      for (final st in (b['steps'] as List?) ?? const []) {
        add(st is Map ? st['text'] : st);
      }
    }
    return (words / 200).ceil();
  }

  void _copyUrl(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied'), duration: Motion.medium),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// App bar
// ────────────────────────────────────────────────────────────────────────────

class _FaceAppBar extends StatelessWidget {
  const _FaceAppBar({
    required this.card,
    required this.api,
    required this.accent,
  });
  final model.Card card;
  final dynamic api;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      stretch: true,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _CircleButton(
          icon: PhosphorIconsRegular.arrowLeft,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'card-face-${card.cardId}',
              child: CardFace(card: card, api: api),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.transparent,
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final PhosphorIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: PhosphorIcon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Editorial structure widgets
// ────────────────────────────────────────────────────────────────────────────

/// Category pills: content type (accent-tinted) + tag pills in a wrap.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.accent,
    required this.contentLabel,
    required this.tags,
  });
  final ContentAccent accent;
  final String contentLabel;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Content type — accent-tinted
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: accent.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(accent.icon, size: 11, color: accent.color),
              const SizedBox(width: 5),
              Text(
                contentLabel.toUpperCase(),
                style: Brand.label(
                  size: 10,
                  color: accent.color,
                  weight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        // Tags — neutral pills
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              tag.toUpperCase(),
              style: Brand.label(
                size: 10,
                color: scheme.onSurfaceVariant,
                weight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
      ],
    );
  }
}

/// Read time badge below the headline.
class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.readMinutes});
  final int readMinutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mins = readMinutes < 1 ? 1 : readMinutes;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(PhosphorIconsRegular.clock, size: 11,
                  color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                '$mins min read',
                style: Brand.label(size: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Section eyebrow — 3 px accent bar + small-caps label. Used throughout the
/// card body to introduce sections like "Core Takeaway", "Action Items", etc.
class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 13,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          label.toUpperCase(),
          style: Brand.label(
            size: 10,
            color: color,
            weight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

/// CORE TAKEAWAY — the tldr in a left-border editorial card.
class _CoreTakeawayCard extends StatelessWidget {
  const _CoreTakeawayCard({required this.text, required this.accent});
  final String text;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionEyebrow(label: 'Core Takeaway', color: accent.color),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(Insets.radius),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.65,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Processing / Failed panels
// ────────────────────────────────────────────────────────────────────────────

class _BuildingStatusStrip extends StatelessWidget {
  const _BuildingStatusStrip({required this.vm});
  final ReaderViewModel vm;

  PipelineStage get _stage =>
      vm.lastEvent?.stage ?? _stageFromState(vm.card!.state);

  PipelineStage _stageFromState(CardState state) =>
      state == CardState.queued ? PipelineStage.snapshot : PipelineStage.structuring;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = _stage;
    final progress = PipelineProgress.calculateProgress(stage);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulsingDot(color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage.description.isNotEmpty ? stage.description : stage.label,
                  style: Brand.label(size: 12, color: scheme.onSurface, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progress * 100).round()}%',
                style: Brand.label(size: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: Motion.medium,
              curve: Curves.easeOutCubic,
              builder: (_, val, _) => LinearProgressIndicator(
                value: val,
                minHeight: 3,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
          begin: 0.5,
          end: 1.0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
  }
}

class _FailedPanel extends StatelessWidget {
  const _FailedPanel({required this.card});
  final model.Card card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Insets.radius),
      ),
      child: Row(
        children: [
          PhosphorIcon(PhosphorIconsRegular.warning, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              card.failureReason?.label ?? "This reel couldn't be processed",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Action items section
// ────────────────────────────────────────────────────────────────────────────

class _ActionItemsSection extends StatelessWidget {
  const _ActionItemsSection({
    required this.card,
    required this.accent,
    required this.vm,
  });
  final model.Card card;
  final ContentAccent accent;
  final ReaderViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = card.actionItems;
    final followed = actions.followed;
    final count = actions.items.length;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionEyebrow(label: 'Actions', color: accent.color),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: Brand.label(size: 10, color: accent.color, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (!followed) ...[
            // ── Unfollowed preview: left-border card listing all items ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Insets.radius),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < actions.items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: PhosphorIcon(
                            PhosphorIconsFill.circle,
                            size: 6,
                            color: accent.color.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            actions.items[i].text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => vm.setActionsFollowed(true),
                style: FilledButton.styleFrom(
                  backgroundColor: accent.color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const PhosphorIcon(PhosphorIconsRegular.listChecks, size: 18),
                label: const Text('Track in Actions'),
              ),
            ),
          ] else ...[
            // ── Followed: interactive checklist ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  for (final item in actions.items)
                    _FollowedActionTile(
                      item: item,
                      accent: accent,
                      onToggle: (v) => vm.toggleActionItem(item.id, v),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => vm.setActionsFollowed(false),
                icon: const PhosphorIcon(PhosphorIconsFill.checkCircle, size: 18),
                label: const Text('Following — remove from Actions'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowedActionTile extends StatelessWidget {
  const _FollowedActionTile({
    required this.item,
    required this.accent,
    required this.onToggle,
  });
  final model.ActionItem item;
  final ContentAccent accent;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onToggle(!item.done),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhosphorIcon(
              item.done ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square,
              size: 22,
              color: item.done ? accent.color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  color: item.done ? theme.colorScheme.onSurfaceVariant : null,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Concepts strip
// ────────────────────────────────────────────────────────────────────────────

class _ConceptsStrip extends StatelessWidget {
  const _ConceptsStrip({required this.entries});
  final List<ConceptEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionEyebrow(label: 'Concepts', color: scheme.primary),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((entry) {
              final isMultiReel = entry.sourceCardIds.length > 1;
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConceptDetailScreen(entry: entry),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isMultiReel
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isMultiReel
                          ? scheme.primary.withValues(alpha: 0.8)
                          : scheme.outlineVariant.withValues(alpha: 0.6),
                      width: isMultiReel ? 1.5 : 1.0,
                    ),
                    boxShadow: isMultiReel
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(
                        isMultiReel
                            ? PhosphorIconsFill.lightbulb
                            : PhosphorIconsRegular.lightbulb,
                        size: 13,
                        color: isMultiReel ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        entry.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: isMultiReel ? FontWeight.w700 : FontWeight.w500,
                          color: isMultiReel
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (isMultiReel) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${entry.sourceCardIds.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// References strip
// ────────────────────────────────────────────────────────────────────────────

class _ReferencesStrip extends StatelessWidget {
  const _ReferencesStrip({required this.entries});
  final List<CatalogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionEyebrow(label: 'References', color: scheme.primary),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (ctx, i) => _ReferenceTile(entry: entries[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceTile extends StatelessWidget {
  const _ReferenceTile({required this.entry});
  final CatalogEntry entry;

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CardRepository>().saveCatalogEntry(entry.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Saved "${entry.title}" to catalog')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save to catalog")),
      );
    }
  }

  static const _icons = <ArtifactType, PhosphorIconData>{
    ArtifactType.book: PhosphorIconsRegular.bookOpen,
    ArtifactType.movie: PhosphorIconsRegular.filmSlate,
    ArtifactType.tvShow: PhosphorIconsRegular.television,
    ArtifactType.podcast: PhosphorIconsRegular.microphone,
    ArtifactType.music: PhosphorIconsRegular.musicNote,
    ArtifactType.product: PhosphorIconsRegular.shoppingBag,
    ArtifactType.place: PhosphorIconsRegular.mapPin,
    ArtifactType.app: PhosphorIconsRegular.appWindow,
    ArtifactType.other: PhosphorIconsRegular.shapes,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: PhosphorIcon(
          _icons[entry.type] ?? PhosphorIconsRegular.shapes,
          size: 28,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return GestureDetector(
      onTap: () => openLookup(entry),
      onLongPress: () => _save(context),
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (entry.thumbnail == null || entry.thumbnail!.isEmpty)
                    ? placeholder
                    : CachedNetworkImage(
                        imageUrl: entry.thumbnail!,
                        fit: BoxFit.cover,
                        placeholder: (c, _) => placeholder,
                        errorWidget: (c, _, _) => placeholder,
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Flexible(
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Source line
// ────────────────────────────────────────────────────────────────────────────

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.card});
  final model.Card card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = card.source.platform;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          PhosphorIcon(PhosphorIconsRegular.user,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [card.source.creator, platform].whereType<String>().join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Editorial ornament + highlight hint
// ────────────────────────────────────────────────────────────────────────────

class _OrnamentalDivider extends StatelessWidget {
  const _OrnamentalDivider();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          Expanded(child: Divider(color: c, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PhosphorIcon(PhosphorIconsRegular.asterisk, size: 10, color: c),
          ),
          Expanded(child: Divider(color: c, height: 1)),
        ],
      ),
    );
  }
}

class _HighlightHint extends StatelessWidget {
  const _HighlightHint();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          PhosphorIcon(PhosphorIconsRegular.pencilSimple, size: 12, color: c),
          const SizedBox(width: 6),
          Text(
            'Hold any line to save a highlight',
            style: Brand.label(size: 10, color: c, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Fade-in helper — wraps a widget so it animates in when first inserted
// ────────────────────────────────────────────────────────────────────────────

Widget _fadeIn(Widget child) => child
    .animate()
    .fadeIn(duration: Motion.medium)
    .slideY(begin: 0.04, end: 0.0, duration: Motion.medium, curve: Curves.easeOut);

// ────────────────────────────────────────────────────────────────────────────
// Skeleton widgets — shown while card is building, replaced by real content
// ────────────────────────────────────────────────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    this.width = double.infinity,
    required this.height,
    this.radius = 6.0,
  });
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: const Duration(milliseconds: 1200),
          color: scheme.surfaceContainerHighest,
        );
  }
}

class _SkeletonHeadline extends StatelessWidget {
  const _SkeletonHeadline();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(height: 30),
          SizedBox(height: 10),
          _SkeletonBox(width: 220, height: 30),
        ],
      ),
    );
  }
}

class _SkeletonTldrCard extends StatelessWidget {
  const _SkeletonTldrCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Insets.radius),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonBox(height: 15),
            SizedBox(height: 9),
            _SkeletonBox(height: 15),
            SizedBox(height: 9),
            _SkeletonBox(height: 15),
            SizedBox(height: 9),
            _SkeletonBox(width: 160, height: 15),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlocks extends StatelessWidget {
  const _SkeletonBlocks();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBox(height: 70, radius: Insets.radius),
        SizedBox(height: 12),
        _SkeletonBox(height: 90, radius: Insets.radius),
        SizedBox(height: 12),
        _SkeletonBox(height: 55, radius: Insets.radius),
      ],
    );
  }
}

class _SkeletonBottomSections extends StatelessWidget {
  const _SkeletonBottomSections();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 100, height: 12, radius: 4),
          SizedBox(height: 12),
          _SkeletonBox(height: 110, radius: Insets.radius),
          SizedBox(height: 28),
          _SkeletonBox(width: 90, height: 12, radius: 4),
          SizedBox(height: 12),
          _SkeletonBox(height: 80, radius: Insets.radius),
        ],
      ),
    );
  }
}
