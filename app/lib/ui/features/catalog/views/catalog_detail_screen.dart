/// Catalog item detail: opening a catalogued artifact shows its details here
/// (it does NOT launch a web link — that's a deliberate button). The default
/// view is never blank; it shows what we already know (cover, title, creator,
/// year, type, how many cards reference it). A "Fetch info" button generates an
/// on-demand LLM overview only when the user wants to know more.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/artifact.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../reader/views/reader_screen.dart';
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

  // Backlink browsing (best-effort, async): the cards that reference this thing,
  // and other catalog entries that co-occur in those same cards.
  List<({String id, String title})> _appearsIn = const [];
  List<CatalogEntry> _related = const [];

  @override
  void initState() {
    super.initState();
    _loadBacklinks();
  }

  Future<void> _loadBacklinks() async {
    final repo = context.read<CardRepository>();
    final ids = _entry.sourceCardIds;
    // "Appears in": resolve source cards to titles (cap to keep it light).
    final cards = await Future.wait(
      ids.take(12).map(
            (id) => repo.getCard(id).then<model.Card?>((c) => c).catchError((_) => null),
          ),
    );
    final appears = <({String id, String title})>[];
    for (final c in cards) {
      if (c == null) continue;
      final title = c.base.oneLiner.isNotEmpty ? c.base.oneLiner : 'Untitled card';
      appears.add((id: c.cardId, title: title));
    }
    // "Related": catalog entries sharing at least one source card with this one.
    var related = const <CatalogEntry>[];
    try {
      final all = await repo.catalog();
      final mine = _entry.sourceCardIds.toSet();
      related = all
          .where((e) => e.id != _entry.id && e.sourceCardIds.any(mine.contains))
          .take(12)
          .toList();
    } catch (_) {/* related is optional */}
    if (mounted) {
      setState(() {
        _appearsIn = appears;
        _related = related;
      });
    }
  }

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
                : const PhosphorIcon(PhosphorIconsRegular.sparkle, size: 18),
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
            icon: const PhosphorIcon(PhosphorIconsRegular.arrowUpRight, size: 18),
            label: const Text('Search the web'),
          ),

          if (_appearsIn.isNotEmpty) ...[
            const SizedBox(height: 28),
            _label(theme, 'Appears in'),
            const SizedBox(height: 8),
            for (final c in _appearsIn)
              _AppearsRow(
                title: c.title,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReaderScreen(cardId: c.id)),
                ),
              ),
          ],

          if (_related.isNotEmpty) ...[
            const SizedBox(height: 28),
            _label(theme, 'Related'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _related)
                  _RelatedChip(
                    entry: e,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CatalogDetailScreen(entry: e)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Text(
        text.toUpperCase(),
        style: Brand.label(
          size: 11,
          color: theme.colorScheme.onSurfaceVariant,
          weight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );
}

class _AppearsRow extends StatelessWidget {
  const _AppearsRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                PhosphorIcon(PhosphorIconsRegular.article, size: 18, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                ),
                PhosphorIcon(PhosphorIconsRegular.caretRight,
                    size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RelatedChip extends StatelessWidget {
  const _RelatedChip({required this.entry, required this.onTap});
  final CatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.type.sectionLabel,
                style: Brand.label(size: 9, color: scheme.primary, weight: FontWeight.w700)),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover with a typed placeholder fallback (mirrors the catalog grid tile).
class _Cover extends StatelessWidget {
  const _Cover({required this.entry});
  final CatalogEntry entry;

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
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: PhosphorIcon(_icons[entry.type] ?? PhosphorIconsRegular.shapes,
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
