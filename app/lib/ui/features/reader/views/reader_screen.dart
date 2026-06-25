/// The reader (docs/06): opens directly on a card, even mid-processing, and
/// renders top-down as content arrives — one_liner + tldr first, blocks beneath,
/// face attaches with extraction. Multi-depth: instant (one_liner) always
/// visible, skim (tldr/blocks) below. The primary action is the dominant control.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/pipeline_event.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/card_face.dart';
import '../../../core/widgets/pipeline_progress.dart';
import '../../blocks/block_renderer.dart';
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
                    ),
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
      bottomSheet: card.primaryAction.isPresent && card.isReady
          ? PrimaryActionBar(action: card.primaryAction)
          : null,
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
      flexibleSpace: FlexibleSpaceBar(
        background: Hero(
          tag: 'card-face-${card.cardId}',
          child: CardFace(card: card, api: api),
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
