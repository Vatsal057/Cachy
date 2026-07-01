/// The catalog: a browsable wall of artifact covers (docs/12) — every book,
/// movie, podcast, product, and place referenced across the user's cards,
/// deduplicated and grouped by type. Thumbnails are remote (free image APIs)
/// and degrade to a typed placeholder when absent or unreachable.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/artifact.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/spot_art.dart';
import '../view_models/catalog_view_model.dart';
import 'catalog_detail_screen.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          CatalogViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _CatalogView(),
    );
  }
}

class _CatalogView extends StatelessWidget {
  const _CatalogView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CatalogViewModel>();
    // No AppBar — this widget is a tab inside LibraryScreen which owns the bar.
    return RefreshIndicator(
      onRefresh: vm.refresh,
      child: ResponsiveCenter(
        child: _body(context, vm),
      ),
    );
  }

  Widget _body(BuildContext context, CatalogViewModel vm) {
    switch (vm.status) {
      case CatalogStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case CatalogStatus.error:
        return _Message(
          icon: PhosphorIconsRegular.wifiX,
          title: "Can't reach the backend",
          subtitle: vm.error ?? '',
          action: FilledButton(onPressed: vm.load, child: const Text('Retry')),
        );
      case CatalogStatus.empty:
        return const _Message(
          icon: PhosphorIconsRegular.books,
          art: CatalogSpot(),
          title: 'Nothing saved yet',
          subtitle:
              'Long-press any reference on a card to save it here — books, '
              'movies, apps, products, places and more.',
        );
      case CatalogStatus.idle:
      case CatalogStatus.ready:
        final sections = vm.sections;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: sections.length + 2,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              // Compact inline header: filter chips + small stats
              return _CatalogHeader(vm: vm);
            }
            if (i == sections.length + 1) {
              return const Padding(
                padding: EdgeInsets.only(top: 36),
                child: Center(child: CatalogSpot()),
              );
            }
            return _Section(section: sections[i - 1], vm: vm);
          },
        );
    }
  }
}

/// Compact header row: inline stats + filter chips, no double app bar.
class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({required this.vm});
  final CatalogViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact stats row
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _StatChip(value: '${vm.entryCount}', label: 'entries'),
              const SizedBox(width: 8),
              _StatChip(value: '${vm.typeCount}', label: 'types'),
              const SizedBox(width: 8),
              _StatChip(
                  value: '${vm.referencedCardCount}', label: 'from cards'),
            ],
          ),
        ),
        // Filter chips
        if (vm.availableTypes.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: vm.filter == null,
                    onSelected: (_) => vm.setFilter(null),
                  ),
                ),
                for (final type in vm.availableTypes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(type.sectionLabel),
                      selected: vm.filter == type,
                      onSelected: (_) => vm.setFilter(type),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: Brand.label(
                  size: 13, color: scheme.onSurface, weight: FontWeight.w700),
            ),
            TextSpan(
              text: label,
              style: Brand.label(
                  size: 11,
                  color: scheme.onSurfaceVariant,
                  weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section, required this.vm});
  final CatalogSection section;
  final CatalogViewModel vm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 12),
          child: Text(
            section.type.sectionLabel.toUpperCase(),
            style: Brand.label(size: 12, color: theme.colorScheme.onSurface, weight: FontWeight.w700),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = (constraints.maxWidth / 130).floor().clamp(3, 6);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.58,
              ),
              itemCount: section.entries.length,
              itemBuilder: (ctx, i) => _ArtifactTile(
                entry: section.entries[i],
                onDelete: () => vm.delete(section.entries[i].id),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ArtifactTile extends StatelessWidget {
  const _ArtifactTile({required this.entry, required this.onDelete});
  final CatalogEntry entry;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _openDetail(context),
      onLongPress: () => _confirmDelete(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _Cover(entry: entry),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
          ),
          if (entry.subtitle.isNotEmpty)
            Text(
              entry.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CatalogDetailScreen(entry: entry)),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from catalog?'),
        content: Text('“${entry.title}” will be removed from the catalog.'),
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

/// The cover image with a typed placeholder fallback. `Image.network` errors
/// (offline, dead hotlink, 404) degrade to the placeholder, never crash.
class _Cover extends StatelessWidget {
  const _Cover({required this.entry});
  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final thumb = entry.thumbnail;
    if (thumb == null || thumb.isEmpty) return _Placeholder(type: entry.type);
    return Image.network(
      thumb,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => _Placeholder(type: entry.type),
      loadingBuilder: (ctx, child, progress) =>
          progress == null ? child : _Placeholder(type: entry.type),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.type});
  final ArtifactType type;

  static const _icons = <ArtifactType, PhosphorIconData>{
    ArtifactType.book: PhosphorIconsRegular.bookOpen,
    ArtifactType.movie: PhosphorIconsRegular.filmSlate,
    ArtifactType.tvShow: PhosphorIconsRegular.television,
    ArtifactType.podcast: PhosphorIconsRegular.microphone,
    ArtifactType.music: PhosphorIconsRegular.musicNote,
    ArtifactType.product: PhosphorIconsRegular.shoppingBag,
    ArtifactType.place: PhosphorIconsRegular.mapPin,
    ArtifactType.app: PhosphorIconsRegular.appWindow,
    ArtifactType.other: PhosphorIconsRegular.shapes,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: PhosphorIcon(
          _icons[type] ?? PhosphorIconsRegular.shapes,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.art,
  });
  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  /// Optional spot illustration shown in place of the icon.
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Center(
          child: art ??
              PhosphorIcon(icon, size: 52, color: theme.colorScheme.outline),
        ),
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
