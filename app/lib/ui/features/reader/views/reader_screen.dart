/// The reader (docs/06): opens directly on a card, even mid-processing, and
/// renders top-down as content arrives — one_liner + tldr first, blocks beneath,
/// face attaches with extraction. Multi-depth: instant (one_liner) always
/// visible, skim (tldr/blocks) below. The primary action is the dominant control.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/artifact.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/pipeline_event.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/card_face.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/pipeline_progress.dart';
import '../../blocks/block_renderer.dart';
import '../../catalog/services/artifact_lookup.dart';
import '../view_models/reader_view_model.dart';
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Brand.violet)),
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _FaceAppBar(card: card, api: api, accent: accent),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.page, 18, Insets.page, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TypeChip(accent: accent, label: card.base.contentType.label),
                  const SizedBox(height: 12),
                  // Instant layer — the headline, in the brand display face.
                  if (card.base.oneLiner.isNotEmpty)
                    Text(card.base.oneLiner,
                        style: Theme.of(context).textTheme.headlineMedium),
                  // Skim layer.
                  if (card.base.tldr.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      card.base.tldr,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (card.base.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TagChips(tags: card.base.tags, accent: accent),
                  ],
                  const SizedBox(height: 20),
                  if (card.isProcessing) _ProcessingPanel(vm: vm),
                  if (card.isFailed) _FailedPanel(card: card),
                  // Depth layer — the structured blocks.
                  if (card.blocks.isNotEmpty)
                    BlockList(
                      blocks: card.blocks,
                      onToggleChecklist: vm.toggleChecklistItem,
                      onToggleStep: vm.toggleStep,
                      onOpenUrl: (url) => _copyUrl(context, url),
                      artifacts: vm.artifacts,
                      onOpenArtifact: (e) => openLookup(e),
                    ),
                  // Action items (docs/13): follow into the Actions hub, tick off.
                  if (card.isReady && card.actionItems.isPresent)
                    _ActionItemsSection(card: card, accent: accent, vm: vm),
                  // Referenced things (books/products/places) as tappable covers.
                  if (card.isReady) _ReferencesStrip(entries: vm.artifacts),
                  if (card.source.creator != null) ...[
                    const SizedBox(height: 8),
                    _SourceLine(card: card),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: card.isReady ? PrimaryActionBar(card: card) : null,
    );
  }

  void _copyUrl(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied'), duration: Motion.medium),
    );
  }
}

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
          icon: Icons.arrow_back_rounded,
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
            // Scrim so the face melts into the content below + back button reads.
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

/// A translucent circular icon button for overlaying on imagery (reader header).
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
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
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.accent, required this.label});
  final ContentAccent accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(accent.icon, size: 14, color: accent.color),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: accent.color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingPanel extends StatelessWidget {
  const _ProcessingPanel({required this.vm});
  final ReaderViewModel vm;

  @override
  Widget build(BuildContext context) {
    final stage = vm.lastEvent?.stage ?? _stageFromState(vm.card!.state);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Brand.violet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: Brand.violet.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Building your card',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          PipelineProgress(current: stage, detail: vm.lastEvent?.detail ?? ''),
        ],
      ),
    );
  }

  PipelineStage _stageFromState(CardState state) => state == CardState.queued
      ? PipelineStage.snapshot
      : PipelineStage.structuring;
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
          Icon(Icons.error_outline_rounded, color: scheme.error),
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

class _TagChips extends StatelessWidget {
  const _TagChips({required this.tags, required this.accent});
  final List<String> tags;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accent.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '#$tag',
              style: TextStyle(
                color: accent.color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// "References" strip: the artifacts this card mentions, as tappable covers that
/// open a store/lookup (docs/09). Fetched once; renders nothing if there are none
/// or the fetch fails (graceful — never blocks the reader).
class _ReferencesStrip extends StatelessWidget {
  const _ReferencesStrip({required this.entries});
  final List<CatalogEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('References',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
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
        SnackBar(content: Text('Saved “${entry.title}” to catalog')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save to catalog")),
      );
    }
  }

  static const _icons = {
    ArtifactType.book: Icons.menu_book_rounded,
    ArtifactType.movie: Icons.movie_rounded,
    ArtifactType.tvShow: Icons.tv_rounded,
    ArtifactType.podcast: Icons.podcasts_rounded,
    ArtifactType.music: Icons.music_note_rounded,
    ArtifactType.product: Icons.shopping_bag_rounded,
    ArtifactType.place: Icons.place_rounded,
    ArtifactType.app: Icons.apps_rounded,
    ArtifactType.other: Icons.category_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(_icons[entry.type] ?? Icons.category_rounded,
            size: 28, color: theme.colorScheme.onSurfaceVariant),
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
                        errorWidget: (c, _, __) => placeholder,
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Do this" section (docs/13): the concrete to-dos the reel hands you. Unfollowed
/// it's a preview with a Follow button; once followed each item is checkable and
/// the card appears in the Actions hub.
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
    final actions = card.actionItems;
    final followed = actions.followed;
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: accent.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 18, color: accent.color),
              const SizedBox(width: 8),
              Text('Do this',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in actions.items)
            followed
                ? _FollowedActionTile(
                    item: item,
                    accent: accent,
                    onToggle: (v) => vm.toggleActionItem(item.id, v),
                  )
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.circle, size: 7, color: accent.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.text,
                              style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: followed
                ? OutlinedButton.icon(
                    onPressed: () => vm.setActionsFollowed(false),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Following — remove from Actions'),
                  )
                : FilledButton.icon(
                    onPressed: () => vm.setActionsFollowed(true),
                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                    label: const Text('Follow these actions'),
                  ),
          ),
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              item.done
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
          Icon(Icons.person_outline_rounded,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [card.source.creator, platform]
                  .whereType<String>()
                  .join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
