/// The Actions hub (docs/13): every to-do you've followed off a reel, grouped by
/// its source card, split into things still to do and things done. Tick items off
/// here or jump back to the card. Cards you haven't followed never appear.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/actions_view_model.dart';

class ActionsScreen extends StatelessWidget {
  const ActionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          ActionsViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _ActionsView(),
    );
  }
}

class _ActionsView extends StatelessWidget {
  const _ActionsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ActionsViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Actions'),
        actions: [
          if (vm.pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${vm.pendingCount} to do',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => vm.load(showSpinner: false),
        child: switch (vm.status) {
          ActionsStatus.loading || ActionsStatus.idle =>
            const Center(child: CircularProgressIndicator()),
          ActionsStatus.error => _Message(
              icon: Icons.error_outline_rounded,
              text: "Couldn't load your actions",
              onRetry: vm.load,
            ),
          ActionsStatus.empty => const _Message(
              icon: Icons.checklist_rounded,
              text: 'No actions yet.\nOpen a card and tap “Follow these actions”.',
            ),
          ActionsStatus.ready => ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Insets.page, 12, Insets.page, 32),
              itemCount: vm.groups.length,
              itemBuilder: (ctx, i) => _GroupCard(group: vm.groups[i]),
            ),
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final ActionGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.read<ActionsViewModel>();
    final card = group.card;
    final accent = ContentAccent.of(card.base.contentType);
    final pending = group.items.where((i) => !i.done).toList();
    final done = group.items.where((i) => i.done).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Insets.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — tap to open the card.
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderScreen(cardId: card.cardId),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Thumb(url: card.thumbnail, accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.base.oneLiner.isEmpty
                              ? 'Saved card'
                              : card.base.oneLiner,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.allDone
                              ? 'All done'
                              : '${group.pending} to do',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: group.allDone
                                ? accent.color
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (_) => vm.unfollow(card.cardId),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'unfollow',
                        child: Text('Stop following'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              children: [
                for (final item in pending)
                  _ActionRow(
                    text: item.text,
                    done: false,
                    accent: accent,
                    onToggle: () => vm.toggle(card.cardId, item.id, true),
                  ),
                for (final item in done)
                  _ActionRow(
                    text: item.text,
                    done: true,
                    accent: accent,
                    onToggle: () => vm.toggle(card.cardId, item.id, false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.text,
    required this.done,
    required this.accent,
    required this.onToggle,
  });
  final String text;
  final bool done;
  final ContentAccent accent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              done
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 22,
              color: done ? accent.color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.accent});
  final String? url;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: accent.color.withValues(alpha: 0.14),
      child: Icon(accent.icon, color: accent.color, size: 22),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: (url == null || url!.isEmpty)
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (c, _) => placeholder,
                errorWidget: (c, _, __) => placeholder,
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ListView so RefreshIndicator still works on the empty/error states.
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.28),
        Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ),
        ],
      ],
    );
  }
}
