/// The share receiver — the visible pipeline (docs/06). On receiving a shared or
/// pasted URL it POSTs to /cards and shows the live stage progression so the user
/// watches the work happening, then offers to open the finished card. Reached
/// from the OS share sheet (main.dart) and the in-app Capture sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../core/brand.dart';
import '../../../core/source_platform.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/pipeline_progress.dart';
import '../../../core/widgets/processing_glyph.dart';
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

class _ShareView extends StatefulWidget {
  const _ShareView({required this.sharedUrl});
  final String sharedUrl;

  @override
  State<_ShareView> createState() => _ShareViewState();
}

class _ShareViewState extends State<_ShareView> {
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ShareViewModel>();
    final theme = Theme.of(context);
    final isProcessing = vm.status == ShareStatus.idle || vm.status == ShareStatus.processing;

    // Auto-advance into the reader as soon as the card is ready.
    if (vm.status == ShareStatus.ready && vm.cardId != null && !_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openReader(context, vm.cardId!);
      });
    }

    if (isProcessing) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.4),
              radius: 1.3,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ResponsiveCenter(child: _content(context, vm)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Capturing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.page),
          child: ResponsiveCenter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UrlChip(url: widget.sharedUrl),
                const SizedBox(height: 24),
                Expanded(child: _content(context, vm)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ShareViewModel vm) {
    final theme = Theme.of(context);
    switch (vm.status) {
      case ShareStatus.submitting:
        final source = SourcePlatform.detect(widget.sharedUrl);
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProcessingGlyph(size: 132, icon: source.icon, badgeColor: source.color),
              const SizedBox(height: 20),
              Text('Sending to Cachy…', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                '${source.label.toUpperCase()} · ${source.ingestingLabel}',
                style: Brand.label(size: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );

      case ShareStatus.queuedOffline:
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(PhosphorIconsRegular.cloudSlash, size: 48),
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
        return _FailedView(
          url: widget.sharedUrl,
          reason: vm.failureReason,
          onRetry: () => context.read<ShareViewModel>().submit(widget.sharedUrl),
          onCancel: () => Navigator.pop(context),
        );

      case ShareStatus.ready:
        return _ReadyView(
          onOpen: vm.cardId == null ? null : () => _openReader(context, vm.cardId!),
        );

      case ShareStatus.idle:
      case ShareStatus.processing:
        final progress = PipelineProgress.calculateProgress(vm.stage);
        final source = SourcePlatform.detect(widget.sharedUrl);
        return Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 6,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: progress),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, val, _) => CircularProgressIndicator(
                            value: val,
                            strokeWidth: 6,
                            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      ),
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: source.color.withValues(alpha: 0.12),
                        ),
                        child: Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: source.color,
                              boxShadow: [
                                BoxShadow(
                                  color: source.color.withValues(alpha: 0.45),
                                  blurRadius: 28,
                                ),
                              ],
                            ),
                            child: PhosphorIcon(
                              source.icon,
                              color: ThemeData.estimateBrightnessForColor(source.color) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Brand.ink,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Building your card',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'From ${source.label} · usually under 30 seconds',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: PipelineProgress(current: vm.stage, detail: vm.detail),
                ),
                const SizedBox(height: 28),
                if (vm.cardId != null) ...[
                  OutlinedButton(
                    onPressed: () => _openReader(context, vm.cardId!),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Open while it builds'),
                  ),
                  const SizedBox(height: 12),
                ],
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Cancel',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
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
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              boxShadow: Brand.softShadow(opacity: 0.2, blur: 26, y: 8),
            ),
            child: PhosphorIcon(PhosphorIconsRegular.check, size: 46, color: scheme.onPrimary),
          )
              .animate()
              .scale(
                duration: Motion.medium,
                curve: Motion.spring,
                begin: const Offset(0.3, 0.3),
                end: const Offset(1, 1),
              )
              .fadeIn(duration: Motion.fast),
          const SizedBox(height: 24),
          Text('Card ready', style: theme.textTheme.headlineMedium)
              .animate()
              .fadeIn(delay: 120.ms)
              .moveY(begin: 8, end: 0),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onOpen,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 0),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
            ),
            child: const Text('Open card'),
          ).animate().fadeIn(delay: 220.ms).moveY(begin: 8, end: 0),
        ],
      ),
    );
  }
}

/// Capture failure — never a dead end. A calm ringed warning, a named error with
/// a plain-language explanation, and two ways forward: retry the same URL or back
/// out. Adapted from the prototype's failure screen into the editorial world.
class _FailedView extends StatelessWidget {
  const _FailedView({
    required this.url,
    required this.reason,
    required this.onRetry,
    required this.onCancel,
  });

  final String url;
  final String? reason;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        const Center(child: _WarningGlyph(size: 132)),
        const SizedBox(height: 26),
        Text(
          'Something went wrong',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          "We couldn't process this reel",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(Insets.radius),
            border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PhosphorIcon(PhosphorIconsRegular.warning, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Text(
                    'Unsupported content',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The video may be private, unavailable in your region, or '
                "the link format isn't supported.",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    reason!,
                    style: Brand.label(
                      size: 11,
                      color: scheme.error,
                      weight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Spacer(flex: 3),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const PhosphorIcon(PhosphorIconsRegular.arrowClockwise, size: 20),
          label: const Text('Try again'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A static, calm warning mark: a ringed error badge. The still counterpart to
/// [ProcessingGlyph] — same concentric-ring language, no animation.
class _WarningGlyph extends StatelessWidget {
  const _WarningGlyph({this.size = 132});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = size * 0.46;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.error.withValues(alpha: 0.10), width: 1.4),
            ),
          ),
          Container(
            width: size * 0.74,
            height: size * 0.74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.error.withValues(alpha: 0.18), width: 1.4),
            ),
          ),
          Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.error.withValues(alpha: 0.12),
              border: Border.all(color: scheme.error.withValues(alpha: 0.5), width: 1.6),
            ),
            child: PhosphorIcon(PhosphorIconsRegular.warning, size: badge * 0.5, color: scheme.error),
          ),
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
    final source = SourcePlatform.detect(url);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          PhosphorIcon(source.icon, size: 18, color: source.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            source.label,
            style: Brand.label(size: 10, color: scheme.onSurfaceVariant, weight: FontWeight.w600),
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
