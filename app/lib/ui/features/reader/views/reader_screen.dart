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
import '../../../../domain/models/collection.dart';
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/pipeline_event.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/card_face.dart';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (vm.error != null && vm.card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 12),
              const Text("Couldn't load this card"),
              const SizedBox(height: 16),
              FilledButton(onPressed: vm.retry, child: const Text('Retry')),
            ],
          ),
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
                  // Instant layer.
                  if (card.base.oneLiner.isNotEmpty)
                    Text(card.base.oneLiner,
                        style: Theme.of(context).textTheme.headlineSmall),
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
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      stretch: true,
      actions: [
        if (card.isReady)
          IconButton(
            tooltip: 'Add to collection',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () => _addToCollection(context, card),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Hero(
          tag: 'card-face-${card.cardId}',
          child: CardFace(card: card, api: api),
        ),
      ),
    );
  }

  Future<void> _addToCollection(BuildContext context, model.Card card) async {
    final repo = context.read<CardRepository>();
    List<Collection> collections;
    try {
      collections = await repo.listCollections();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load collections")),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<_CollectionChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Add to collection',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New collection…'),
              onTap: () => Navigator.pop(ctx, const _CollectionChoice.create()),
            ),
            for (final c in collections)
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, _CollectionChoice.existing(c.id)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    var collectionId = choice.id;
    if (choice.isCreate) {
      final name = await _promptName(context);
      if (name == null || name.trim().isEmpty || !context.mounted) return;
      try {
        collectionId = (await repo.createCollection(name.trim())).id;
      } catch (_) {
        return;
      }
    }
    if (collectionId == null) return;
    try {
      await repo.addCardToCollection(collectionId, card.cardId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to collection')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't add to collection")),
        );
      }
    }
  }

  Future<String?> _promptName(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
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
  }
}

/// A pick from the add-to-collection sheet: an existing collection or "create".
class _CollectionChoice {
  const _CollectionChoice.existing(this.id) : isCreate = false;
  const _CollectionChoice.create()
      : id = null,
        isCreate = true;
  final String? id;
  final bool isCreate;
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Insets.radius),
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
