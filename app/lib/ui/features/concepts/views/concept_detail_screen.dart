/// Concept detail: name, definition (on-demand), "Appears in" backlinks,
/// related concepts, and an "Explore" button that seeds library chat.
/// Mirrors CatalogDetailScreen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/concept.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../library/views/library_chat_screen.dart';
import '../../reader/views/reader_screen.dart';

class ConceptDetailScreen extends StatefulWidget {
  const ConceptDetailScreen({super.key, required this.entry});
  final ConceptEntry entry;

  @override
  State<ConceptDetailScreen> createState() => _ConceptDetailScreenState();
}

class _ConceptDetailScreenState extends State<ConceptDetailScreen> {
  late ConceptEntry _entry = widget.entry;
  bool _loading = false;

  List<({String id, String title})> _appearsIn = const [];
  List<ConceptEntry> _related = const [];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final repo = context.read<CardRepository>();
    // Fetch server-computed related and full entry.
    try {
      final detail = await repo.conceptDetail(_entry.id);
      final ids = detail.entry.sourceCardIds;
      final cards = await Future.wait(
        ids.take(12).map(
              (id) => repo
                  .getCard(id)
                  .then<model.Card?>((c) => c)
                  .catchError((_) => null),
            ),
      );
      final appears = <({String id, String title})>[];
      for (final c in cards) {
        if (c == null) continue;
        final title =
            c.base.oneLiner.isNotEmpty ? c.base.oneLiner : 'Untitled card';
        appears.add((id: c.cardId, title: title));
      }
      if (mounted) {
        setState(() {
          _entry = detail.entry;
          _appearsIn = appears;
          _related = detail.related;
        });
      }
    } catch (_) {/* detail is best-effort */}
  }

  Future<void> _define() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await context.read<CardRepository>().defineConcept(_entry.id);
      if (mounted) setState(() => _entry = updated);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't generate definition right now")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _explore() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryChatScreen(seedQuery: _entry.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasDefinition =
        _entry.definition != null && _entry.definition!.trim().isNotEmpty;
    final sources = _entry.sourceCardIds.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Concept')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 40),
        children: [
          // Header.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.lightbulb_rounded,
                    size: 32, color: scheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(_entry.name, style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                    if (sources > 0) ...[
                      const SizedBox(height: 6),
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

          // Definition section.
          _label(theme, 'Definition'),
          const SizedBox(height: 10),
          if (hasDefinition)
            Text(
              _entry.definition!.trim(),
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
                'No definition yet. Tap "Define" to generate a concise overview.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 20),

          // Action buttons.
          FilledButton.icon(
            onPressed: _loading ? null : _define,
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
                  : hasDefinition
                      ? 'Regenerate'
                      : 'Define',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _explore,
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: const Text('Explore'),
          ),

          // Appears in.
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

          // Related concepts.
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
                      MaterialPageRoute(
                          builder: (_) => ConceptDetailScreen(entry: e)),
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
                Icon(Icons.description_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                ),
                Icon(Icons.chevron_right_rounded,
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
  final ConceptEntry entry;
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
            Icon(Icons.lightbulb_rounded, size: 12, color: scheme.primary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(entry.name,
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
