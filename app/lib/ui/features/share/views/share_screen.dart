/// The share receiver — the visible pipeline (docs/06). On receiving a shared or
/// pasted URL it POSTs to /cards and shows the live stage progression so the user
/// watches the work happening, then offers to open the finished card. Reached
/// from the OS share sheet (main.dart) and the in-app Capture sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/pipeline_event.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/error_state.dart';
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
      appBar: AppBar(title: const Text('Capturing')),
      body: SafeArea(
        child: Padding(
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
      ),
    );
  }

  Widget _content(BuildContext context, ShareViewModel vm) {
    final theme = Theme.of(context);
    switch (vm.status) {
      case ShareStatus.submitting:
        return const _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Brand.violet),
              SizedBox(height: 16),
              Text('Sending to Cachy…'),
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
              Text('Saved offline', style: theme.textTheme.titleLarge),
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
        return ErrorState(
          title: "Couldn't capture this reel",
          icon: Icons.error_outline_rounded,
          message: vm.failureReason ??
              'The source may be private, removed, or unsupported.',
          retryLabel: 'Back',
          onRetry: () => Navigator.pop(context),
        );

      case ShareStatus.ready:
        return _ReadyView(
          onOpen: vm.cardId == null ? null : () => _openReader(context, vm.cardId!),
        );

      case ShareStatus.idle:
      case ShareStatus.processing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Building your card', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'You can leave — it keeps working in the background.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            PipelineProgress(current: vm.stage, detail: vm.detail),
            const Spacer(),
            if (vm.cardId != null)
              OutlinedButton(
                onPressed: () => _openReader(context, vm.cardId!),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
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

/// Success: a spring pop + haptic, then the open CTA. The payoff of capture.
class _ReadyView extends StatefulWidget {
  const _ReadyView({required this.onOpen});
  final VoidCallback? onOpen;

  @override
  State<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends State<_ReadyView> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: Brand.gradient,
              shape: BoxShape.circle,
              boxShadow: Brand.glow(opacity: 0.5, blur: 26, y: 8),
            ),
            child: const Icon(Icons.check_rounded, size: 46, color: Colors.white),
          )
              .animate()
              .scale(
                duration: Motion.medium,
                curve: Motion.spring,
                begin: const Offset(0.3, 0.3),
                end: const Offset(1, 1),
              )
              .fadeIn(duration: Motion.fast),
          const SizedBox(height: 20),
          Text('Card ready', style: theme.textTheme.headlineSmall)
              .animate()
              .fadeIn(delay: 120.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: widget.onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
              decoration: BoxDecoration(
                gradient: Brand.gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: Brand.glow(opacity: 0.35, blur: 18, y: 6),
              ),
              child: Text('Open card',
                  style: Brand.wordmarkStyle(16, color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w700)),
            ),
          ).animate().fadeIn(delay: 220.ms).moveY(begin: 8, end: 0),
        ],
      ),
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
