/// The rabbit-hole explorer screen (docs/14): a generative, branching journey
/// down a thread. Unlike ask-the-card chat, answers are NOT confined to the card
/// — each step explains the tapped thread from general knowledge and offers fresh
/// threads to keep going. A breadcrumb trail tracks the path and lets the reader
/// jump back to branch differently.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/rich_text.dart';
import '../view_models/rabbit_hole_view_model.dart';

class RabbitHoleScreen extends StatelessWidget {
  const RabbitHoleScreen({
    super.key,
    required this.cardId,
    required this.seed,
    required this.accent,
  });

  final String cardId;

  /// The thread the reader tapped to enter the rabbit hole.
  final String seed;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => RabbitHoleViewModel(
        repository: ctx.read<CardRepository>(),
        cardId: cardId,
      )..start(seed),
      child: _RabbitHoleView(accent: accent),
    );
  }
}

class _RabbitHoleView extends StatelessWidget {
  const _RabbitHoleView({required this.accent});
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RabbitHoleViewModel>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rabbit hole'),
            Text(
              'AI-GENERATED · MAY CONTAIN ERRORS',
              style: Brand.label(size: 9, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Insets.readingColumn),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 48),
            children: [
              _Breadcrumbs(vm: vm, accent: accent),
              const SizedBox(height: 16),
              if (vm.loading && vm.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (vm.current != null) _StepView(step: vm.current!, vm: vm, accent: accent),
              if (vm.busy) _LoadingStep(topic: vm.pendingTopic, accent: accent),
              if (vm.error != null) _ErrorStep(vm: vm, accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The path taken so far, tappable to backtrack. The first crumb is the card
/// itself (the anchor the journey started from).
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.vm, required this.accent});
  final RabbitHoleViewModel vm;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = vm.steps;
    if (steps.isEmpty && vm.pendingTopic == null) return const SizedBox.shrink();

    final crumbs = <Widget>[
      _Crumb(
        label: 'Card',
        icon: PhosphorIconsRegular.cardsThree,
        active: false,
        onTap: () => Navigator.of(context).pop(),
        accent: accent,
      ),
    ];
    for (var i = 0; i < steps.length; i++) {
      final isLast = i == steps.length - 1;
      crumbs.add(_chevron(theme));
      crumbs.add(_Crumb(
        label: steps[i].topic,
        active: isLast,
        onTap: isLast ? null : () => vm.jumpTo(i),
        accent: accent,
      ));
    }
    if (vm.busy && vm.pendingTopic != null && vm.steps.isNotEmpty) {
      crumbs.add(_chevron(theme));
      crumbs.add(_Crumb(label: vm.pendingTopic!, active: true, accent: accent, dim: true));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: crumbs),
    );
  }

  Widget _chevron(ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: PhosphorIcon(PhosphorIconsRegular.caretRight,
            size: 12, color: theme.colorScheme.onSurfaceVariant),
      );
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.accent,
    this.icon,
    this.active = false,
    this.onTap,
    this.dim = false,
  });
  final String label;
  final ContentAccent accent;
  final PhosphorIconData? icon;
  final bool active;
  final VoidCallback? onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = active ? accent.color : scheme.onSurfaceVariant;
    final ic = icon;
    return Material(
      color: active ? accent.color.withValues(alpha: 0.12) : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ic != null) ...[
                PhosphorIcon(ic, size: 13, color: color),
                const SizedBox(width: 5),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: dim ? color.withValues(alpha: 0.6) : color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One explored step: the topic heading, its explanation, and the follow-on
/// threads that branch onward.
class _StepView extends StatelessWidget {
  const _StepView({required this.step, required this.vm, required this.accent});
  final RabbitHoleStep step;
  final RabbitHoleViewModel vm;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step.topic,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        RichInlineText(
          step.explanation,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        if (step.threads.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              PhosphorIcon(PhosphorIconsRegular.compass, size: 15, color: accent.color),
              const SizedBox(width: 7),
              Text('KEEP GOING',
                  style: Brand.label(size: 11, color: accent.color, weight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final thread in step.threads)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ThreadButton(
                label: thread,
                accent: accent,
                enabled: !vm.busy,
                onTap: () => vm.dive(thread),
              ),
            ),
        ] else if (!vm.busy) ...[
          const SizedBox(height: 20),
          Text(
            'This thread bottoms out here. Hop back to a crumb above to branch another way.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _ThreadButton extends StatelessWidget {
  const _ThreadButton({
    required this.label,
    required this.accent,
    required this.onTap,
    required this.enabled,
  });
  final String label;
  final ContentAccent accent;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Insets.radius),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(Insets.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Insets.radius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, height: 1.3)),
              ),
              const SizedBox(width: 8),
              PhosphorIcon(PhosphorIconsRegular.arrowDown, size: 15, color: accent.color),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingStep extends StatelessWidget {
  const _LoadingStep({required this.topic, required this.accent});
  final String? topic;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              topic == null ? 'Digging…' : 'Digging into "$topic"…',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorStep extends StatelessWidget {
  const _ErrorStep({required this.vm, required this.accent});
  final RabbitHoleViewModel vm;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(vm.error!, style: TextStyle(color: theme.colorScheme.error)),
          if (vm.canRetry) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: vm.retry,
              icon: const PhosphorIcon(PhosphorIconsRegular.arrowClockwise, size: 16),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(foregroundColor: accent.color),
            ),
          ],
        ],
      ),
    );
  }
}
