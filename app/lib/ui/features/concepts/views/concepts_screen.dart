/// The concepts browser: a flat list of evergreen ideas mined from all cards,
/// deduplicated across the library. Tap a chip to open its detail screen.
/// Mirrors CatalogScreen — no thumbnails, just labeled chips.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/concept.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/stat_strip.dart';
import '../view_models/concepts_view_model.dart';
import 'concept_detail_screen.dart';

class ConceptsScreen extends StatelessWidget {
  const ConceptsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          ConceptsViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _ConceptsView(),
    );
  }
}

class _ConceptsView extends StatelessWidget {
  const _ConceptsView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConceptsViewModel>();
    return RefreshIndicator(
      onRefresh: vm.refresh,
      child: _body(context, vm),
    );
  }

  Widget _body(BuildContext context, ConceptsViewModel vm) {
    switch (vm.status) {
      case ConceptsStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ConceptsStatus.error:
        return _Message(
          icon: PhosphorIconsRegular.wifiX,
          title: "Can't reach the backend",
          subtitle: vm.error ?? '',
          action: FilledButton(
            onPressed: vm.load,
            child: const Text('Retry'),
          ),
        );
      case ConceptsStatus.empty:
        return const _Message(
          icon: PhosphorIconsRegular.lightbulb,
          title: 'No concepts yet',
          subtitle:
              'Concepts emerge automatically once recurring themes connect across '
              'multiple saved reels. Keep capturing idea-rich content!',
        );
      case ConceptsStatus.idle:
      case ConceptsStatus.ready:
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 96),
          children: [
            StatStrip(stats: [
              Stat(
                  value: '${vm.entryCount}',
                  label: 'Concepts',
                  emphasize: true),
              Stat(value: '${vm.referencedCardCount}', label: 'From cards'),
            ]),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in vm.entries)
                  _ConceptChip(
                    entry: entry,
                    onDelete: () => vm.delete(entry.id),
                  ),
              ],
            ),
          ],
        );
    }
  }
}

class _ConceptChip extends StatelessWidget {
  const _ConceptChip({required this.entry, required this.onDelete});
  final ConceptEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ConceptDetailScreen(entry: entry)),
      ),
      onLongPress: () => _confirmDelete(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(PhosphorIconsRegular.lightbulb, size: 14, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              entry.name,
              style: Brand.label(
                  size: 13,
                  color: scheme.onSecondaryContainer,
                  weight: FontWeight.w600),
            ),
            if (entry.sourceCardIds.length > 1) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${entry.sourceCardIds.length}',
                  style: Brand.label(
                      size: 10,
                      color: scheme.onPrimary,
                      weight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove concept?'),
        content: Text('"${entry.name}" will be removed from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        PhosphorIcon(icon, size: 52, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        if (action != null) ...[
          const SizedBox(height: 20),
          Center(child: action!),
        ],
      ],
    );
  }
}
