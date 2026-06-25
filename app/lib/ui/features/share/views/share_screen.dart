/// The share receiver — the visible pipeline (docs/06). On receiving a shared or
/// pasted URL it POSTs to /cards and shows the live stage progression so the user
/// watches the work happening, then offers to open the finished card.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/pipeline_event.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/pipeline_progress.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/share_view_model.dart';

class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key, required this.sharedUrl});
  final String sharedUrl;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          ShareViewModel(repository: ctx.read<CardRepository>())
            ..submit(sharedUrl),
      child: _ShareView(sharedUrl: sharedUrl),
    );
  }
}

class _ShareView extends StatelessWidget {
  const _ShareView({required this.sharedUrl});
  final String sharedUrl;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShareViewModel>();

    // Auto-advance into the reader the moment dedup resolves to an existing card.
    if (vm.status == ShareStatus.ready &&
        vm.cardId != null &&
        vm.stage == PipelineStage.snapshot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _openReader(context, vm.cardId!);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saving reel')),
      body: Padding(
        padding: const EdgeInsets.all(Insets.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UrlChip(url: sharedUrl),
            const SizedBox(height: 24),
            Expanded(child: _content(context, vm)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ShareViewModel vm) {
    switch (vm.status) {
      case ShareStatus.submitting:
        return const _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Sending to backend…'),
            ],
          ),
        );

      case ShareStatus.queuedOffline:
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48),
              const SizedBox(height: 14),
              Text('Saved offline',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                "We'll process this reel as soon as you're back online.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );

      case ShareStatus.failed:
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 14),
              Text("Couldn't process this reel",
                  style: Theme.of(context).textTheme.titleLarge),
              if (vm.failureReason != null) ...[
                const SizedBox(height: 8),
                Text(vm.failureReason!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        );

      case ShareStatus.ready:
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 14),
              Text('Card ready',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: vm.cardId == null
                    ? null
                    : () => _openReader(context, vm.cardId!),
                child: const Text('Open card'),
              ),
            ],
          ),
        );

      case ShareStatus.idle:
      case ShareStatus.processing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Building your card',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'You can leave — it keeps working in the background.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 28),
            PipelineProgress(current: vm.stage, detail: vm.detail),
            const Spacer(),
            if (vm.cardId != null)
              OutlinedButton(
                onPressed: () => _openReader(context, vm.cardId!),
                child: const Text('Open while it builds'),
              ),
          ],
        );
    }
  }

  void _openReader(BuildContext context, String cardId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReaderScreen(cardId: cardId)),
    );
  }
}

class _UrlChip extends StatelessWidget {
  const _UrlChip({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}
