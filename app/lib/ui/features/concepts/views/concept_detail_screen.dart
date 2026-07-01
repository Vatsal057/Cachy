/// Concept detail: name, summary (on-demand), "Appears in" backlinks,
/// related concepts, and an "Explore in chat" bottom CTA.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/concept.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/responsive_center.dart';
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

  List<({String id, String title, DateTime? date})> _appearsIn = const [];
  bool _showAllAppears = false;
  List<ConceptEntry> _related = const [];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final repo = context.read<CardRepository>();
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
      final appears = <({String id, String title, DateTime? date})>[];
      for (final c in cards) {
        if (c == null) continue;
        final title =
            c.base.oneLiner.isNotEmpty ? c.base.oneLiner : 'Untitled card';
        appears.add((id: c.cardId, title: title, date: c.meta.createdAt));
      }
      if (mounted) {
        setState(() {
          _entry = detail.entry;
          _appearsIn = appears;
          _related = detail.related;
        });
      }
    } catch (_) {/* best-effort */}
  }

  Future<void> _define() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated =
          await context.read<CardRepository>().defineConcept(_entry.id);
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
    final count = _entry.sourceCardIds.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const PhosphorIcon(PhosphorIconsRegular.chats, size: 22),
            tooltip: 'Explore in chat',
            onPressed: _explore,
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 12),
          child: FilledButton.icon(
            onPressed: _explore,
            icon: const PhosphorIcon(PhosphorIconsRegular.chats, size: 18),
            label: const Text('Explore in chat'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99)),
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: ListView(
        padding:
            const EdgeInsets.fromLTRB(Insets.page, 4, Insets.page, 32),
        children: [
          // "Concept" pill
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'CONCEPT',
                style: Brand.label(
                  size: 10,
                  color: scheme.onPrimaryContainer,
                  weight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Name headline
          Text(
            _entry.name,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
          ),
          const SizedBox(height: 10),

          // Meta: "in X cards"
          if (count > 0)
            Row(
              children: [
                Text(
                  'Last updated',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count ${count == 1 ? 'entry' : 'entries'}',
                    style: Brand.label(
                      size: 11,
                      color: scheme.onPrimaryContainer,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),

          // Summary / definition card
          _SummaryCard(
            entry: _entry,
            loading: _loading,
            hasDefinition: hasDefinition,
            onDefine: _define,
          ),

          // Appears in
          if (_appearsIn.isNotEmpty) ...[
            const SizedBox(height: 32),
            _SectionHeaderWithAction(
              label: 'Appears in',
              actionLabel: !_showAllAppears && _appearsIn.length > 4
                  ? 'See all'
                  : null,
              onAction: () => setState(() => _showAllAppears = true),
            ),
            const SizedBox(height: 12),
            for (final c in (_showAllAppears
                ? _appearsIn
                : _appearsIn.take(4).toList()))
              _AppearsRow(
                title: c.title,
                date: c.date,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ReaderScreen(cardId: c.id)),
                ),
              ),
          ],

          // Related concepts
          if (_related.isNotEmpty) ...[
            const SizedBox(height: 32),
            _SectionHeader(label: 'Related Concepts'),
            const SizedBox(height: 12),
            _RelatedGrid(
              related: _related,
              onTap: (e) => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ConceptDetailScreen(entry: e)),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Section header
// ────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _SectionHeaderWithAction extends StatelessWidget {
  const _SectionHeaderWithAction({
    required this.label,
    this.actionLabel,
    this.onAction,
  });
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Summary card
// ────────────────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.entry,
    required this.loading,
    required this.hasDefinition,
    required this.onDefine,
  });
  final ConceptEntry entry;
  final bool loading;
  final bool hasDefinition;
  final VoidCallback onDefine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Insets.radius + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUMMARY',
            style: Brand.label(
              size: 10,
              color: scheme.primary,
              weight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (hasDefinition)
            Text(
              entry.definition!.trim(),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(height: 1.6, color: scheme.onSurface),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No summary yet — tap Define to generate one.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: loading ? null : onDefine,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const PhosphorIcon(PhosphorIconsRegular.sparkle,
                          size: 16),
                  label: Text(loading ? 'Generating…' : 'Define'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          if (hasDefinition) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDefine,
                icon: loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const PhosphorIcon(PhosphorIconsRegular.sparkle,
                        size: 14),
                label: Text(loading ? 'Regenerating…' : 'Regenerate',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Appears-in rows
// ────────────────────────────────────────────────────────────────────────────

class _AppearsRow extends StatelessWidget {
  const _AppearsRow({required this.title, required this.onTap, this.date});
  final String title;
  final DateTime? date;
  final VoidCallback onTap;

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIconsRegular.article,
                      size: 17,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                  ),
                ),
                if (date != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _fmtDate(date!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(width: 8),
                PhosphorIcon(PhosphorIconsRegular.caretRight,
                    size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Related concepts 2-column grid
// ────────────────────────────────────────────────────────────────────────────

class _RelatedGrid extends StatelessWidget {
  const _RelatedGrid({required this.related, required this.onTap});
  final List<ConceptEntry> related;
  final ValueChanged<ConceptEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < related.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: _RelatedCard(entry: related[i], onTap: onTap)),
            const SizedBox(width: 10),
            i + 1 < related.length
                ? Expanded(
                    child: _RelatedCard(
                        entry: related[i + 1], onTap: onTap))
                : const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < related.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.entry, required this.onTap});
  final ConceptEntry entry;
  final ValueChanged<ConceptEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = entry.sourceCardIds.length;
    return GestureDetector(
      onTap: () => onTap(entry),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Concept',
                style: Brand.label(
                  size: 9,
                  color: scheme.onPrimaryContainer,
                  weight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
            ),
            if (count > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$count card${count == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
