/// The Connections view — the serendipity engine's own surface. A scrollable
/// deck of "aha" links between pairs of the user's cards: two cards you'd never
/// think to compare, and one sentence on the surprising thread between them.
/// Tap either card to read it; "Find more" spends a little AI budget to surface
/// fresh links.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/feed.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/rich_text.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/connections_view_model.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          ConnectionsViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _ConnectionsView(),
    );
  }
}

class _ConnectionsView extends StatelessWidget {
  const _ConnectionsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectionsViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        actions: [
          IconButton(
            tooltip: 'Find more',
            onPressed: vm.refreshing ? null : () => vm.load(refresh: true),
            icon: vm.refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const PhosphorIcon(PhosphorIconsRegular.sparkle),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context, vm),
    );
  }

  Widget _body(BuildContext context, ConnectionsViewModel vm) {
    if (vm.loading && vm.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && vm.isEmpty) {
      return ErrorState(
        title: "Can't load connections",
        message: vm.error!,
        onRetry: vm.load,
      );
    }
    if (vm.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.link,
        title: 'No connections yet',
        message:
            'Connections surface surprising links between your cards. Save a few '
            'more from different topics, then tap Find more.',
        actionLabel: 'Find connections',
        onAction: () => vm.load(refresh: true),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.readingColumn),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 40),
          itemCount: vm.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (ctx, i) {
            if (i == 0) return const _Intro();
            return _ConnectionCard(connection: vm.items[i - 1])
                .animate()
                .fadeIn(duration: 300.ms, delay: (30 * i).ms)
                .slideY(begin: 0.03, end: 0);
          },
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        'Surprising threads Cachy found between cards across your library.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.connection});
  final Connection connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniCard(ref: connection.cardA),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              children: [
                PhosphorIcon(PhosphorIconsRegular.linkSimple,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Container(width: 24, height: 1, color: scheme.outlineVariant),
              ],
            ),
          ),
          _MiniCard(ref: connection.cardB),
          const SizedBox(height: 14),
          RichInlineText(
            connection.blurb,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.ref});
  final FeedCardRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = ContentAccent.of(ref.contentType);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderScreen(cardId: ref.cardId)),
      ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: PhosphorIcon(accent.icon, size: 18, color: accent.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(ref.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            PhosphorIcon(PhosphorIconsRegular.arrowUpRight,
                size: 15, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
