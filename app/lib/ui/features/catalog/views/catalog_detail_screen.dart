/// Catalog item detail: opening a catalogued artifact shows its details here
/// (it does NOT launch a web link — that's a deliberate button). The default
/// view is never blank; it shows what we already know (cover, title, creator,
/// year, type, how many cards reference it). A "Fetch info" button generates an
/// on-demand LLM overview only when the user wants to know more.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/artifact.dart';
import '../../../core/theme.dart';
import '../services/artifact_lookup.dart';

class CatalogDetailScreen extends StatefulWidget {
  const CatalogDetailScreen({super.key, required this.entry});
  final CatalogEntry entry;

  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  late CatalogEntry _entry = widget.entry;
  bool _loading = false;

  Future<void> _fetchInfo() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await context.read<CardRepository>().fetchCatalogInfo(_entry.id);
      if (mounted) setState(() => _entry = updated);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't generate details right now")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchWeb() async {
    final ok = await openLookup(_entry);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open a web search")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasDescription =
        _entry.description != null && _entry.description!.trim().isNotEmpty;
    final sources = _entry.sourceCardIds.length;

    return Scaffold(
      appBar: AppBar(title: Text(_entry.type.sectionLabel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: AspectRatio(
                  aspectRatio: 0.72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _Cover(entry: _entry),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(_entry.title, style: theme.textTheme.titleLarge),
                    if (_entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _entry.subtitle,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _entry.type.sectionLabel,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.onSecondaryContainer),
                      ),
                    ),
                    if (sources > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Referenced in $sources card${sources == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          Text('About', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (hasDescription)
            Text(
              _entry.description!.trim(),
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Insets.radius),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Text(
                "No detailed write-up yet. Tap “Fetch info” to have the AI "
                'generate an overview of what this is and what it’s about.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _loading ? null : _fetchInfo,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(
              _loading
                  ? 'Generating…'
                  : hasDescription
                      ? 'Regenerate info'
                      : 'Fetch info',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _searchWeb,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Search the web'),
          ),
        ],
      ),
    );
  }
}

/// Cover with a typed placeholder fallback (mirrors the catalog grid tile).
class _Cover extends StatelessWidget {
  const _Cover({required this.entry});
  final CatalogEntry entry;

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
            size: 30, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
    final thumb = entry.thumbnail;
    if (thumb == null || thumb.isEmpty) return placeholder;
    return Image.network(
      thumb,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => placeholder,
      loadingBuilder: (c, child, p) => p == null ? child : placeholder,
    );
  }
}
