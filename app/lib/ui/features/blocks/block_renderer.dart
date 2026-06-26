/// The block renderer (docs/06 core): maps the fixed block vocabulary from
/// docs/04 to one widget per entry. Unknown/future blocks degrade gracefully —
/// render `text`/`items` if present, else skip. Never crashes on a bad block.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/models/artifact.dart';
import '../../../domain/models/block.dart';
import '../../core/theme.dart';

/// Callbacks the reader injects so checkable blocks can persist (PATCH).
typedef ToggleCallback = void Function(String blockId, int index, bool checked);
typedef OpenUrlCallback = void Function(String url);

class BlockList extends StatelessWidget {
  const BlockList({
    super.key,
    required this.blocks,
    this.onToggleChecklist,
    this.onToggleStep,
    this.onOpenUrl,
    this.artifacts = const [],
    this.onOpenArtifact,
    this.animate = true,
  });

  final List<Block> blocks;
  final ToggleCallback? onToggleChecklist;
  final ToggleCallback? onToggleStep;
  final OpenUrlCallback? onOpenUrl;

  /// The card's referenced artifacts, used to resolve inline `[[Name]]` markers
  /// into tappable links right where the text introduces them.
  final List<CatalogEntry> artifacts;
  final void Function(CatalogEntry)? onOpenArtifact;

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final segment in _segment(blocks)) {
      final w = _renderSegment(context, segment);
      if (w == null) continue; // skipped (e.g. empty unknown block)
      widgets.add(Padding(
        padding: EdgeInsets.only(bottom: Insets.block),
        child: animate
            ? _StaggeredIn(index: widgets.length, child: w)
            : w,
      ));
    }
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
    // Provide the inline-reference resolver to descendant rich-text widgets.
    if (artifacts.isEmpty || onOpenArtifact == null) return column;
    return _ReferenceScope(
      refs: {
        for (final a in artifacts)
          if (a.title.trim().isNotEmpty) a.title.toLowerCase().trim(): a,
      },
      onTap: onOpenArtifact!,
      child: column,
    );
  }

  /// A block that already carries its own surface/visual treatment, so it
  /// renders standalone rather than being boxed inside a section card.
  bool _isSelfCarded(Block b) =>
      b is CalloutBlock ||
      b is LinkBlock ||
      b is TableBlock ||
      b is MapBlock ||
      b is KeyValueBlock;

  /// Group the flat block list into render segments so the reader shows
  /// carded sections instead of a flat text dump: a `heading` opens a section,
  /// the flow blocks beneath it (paragraphs, lists, steps, checklists) join it,
  /// and self-carded blocks (callout/table/key_value/map/link) stand alone.
  List<List<Block>> _segment(List<Block> input) {
    final out = <List<Block>>[];
    List<Block>? section; // currently open flow section, if any
    for (final b in input) {
      if (_isSelfCarded(b)) {
        // A self-carded block right after a lone heading attaches to it, so a
        // category heading sits as the title atop its table; otherwise it stands
        // alone.
        if (section != null &&
            section.length == 1 &&
            section.first is HeadingBlock) {
          section.add(b);
        } else {
          out.add([b]);
        }
        section = null;
      } else if (b is HeadingBlock) {
        section = [b];
        out.add(section);
      } else if (section != null) {
        section.add(b);
      } else {
        section = [b];
        out.add(section);
      }
    }
    return out;
  }

  /// Render one segment: a lone self-carded block as-is, otherwise the flow
  /// blocks stacked inside a single section card.
  Widget? _renderSegment(BuildContext context, List<Block> segment) {
    if (segment.length == 1 && _isSelfCarded(segment.first)) {
      return _renderBlock(context, segment.first);
    }
    final children = <Widget>[];
    for (final b in segment) {
      final w = _renderBlock(context, b);
      if (w == null) continue;
      if (children.isNotEmpty) {
        children.add(SizedBox(height: b is HeadingBlock ? 14 : 10));
      }
      children.add(w);
    }
    if (children.isEmpty) return null;
    return _SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget? _renderBlock(BuildContext context, Block block) {
    switch (block) {
      case HeadingBlock b:
        return _Heading(b);
      case ParagraphBlock b:
        return _Paragraph(b);
      case BulletListBlock b:
        return _BulletList(b);
      case StepListBlock b:
        return _StepList(block: b, onToggle: onToggleStep);
      case KeyValueBlock b:
        return _KeyValue(b);
      case ChecklistBlock b:
        return _Checklist(block: b, onToggle: onToggleChecklist);
      case CalloutBlock b:
        return _Callout(b, onOpenUrl: onOpenUrl);
      case LinkBlock b:
        return _Link(b, onOpenUrl: onOpenUrl);
      case TableBlock b:
        return _Table(b);
      case MapBlock b:
        return _MapPlaceholder(b);
      case UnknownBlock b:
        return _renderUnknown(context, b);
    }
  }

  /// Forward-compat rule (docs/04): show text/items if present, else skip.
  Widget? _renderUnknown(BuildContext context, UnknownBlock b) {
    if (b.text != null && b.text!.trim().isNotEmpty) {
      return _Paragraph(ParagraphBlock(id: b.id, text: b.text!));
    }
    if (b.items.isNotEmpty) {
      return _BulletList(BulletListBlock(id: b.id, items: b.items));
    }
    return null;
  }
}

/// Surfaced container that turns a run of flow blocks into a distinct,
/// scannable section card (vs. a flat text dump).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}

// --------------------------------------------------------------------------- //
// Inline rich text (lightweight markdown: **bold**, *italic* / _italic_, `code`)
// --------------------------------------------------------------------------- //

/// Inline grammar: `[[Reference]]`, then **bold**, *italic* / _italic_, `code`.
final _richPattern = RegExp(
  r'\[\[(.+?)\]\]|\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`',
  dotAll: true,
);

/// Carries the card's inline-reference resolver down to rich-text widgets, so a
/// `[[Name]]` marker becomes a tappable link without drilling params everywhere.
class _ReferenceScope extends InheritedWidget {
  const _ReferenceScope({
    required this.refs,
    required this.onTap,
    required super.child,
  });

  final Map<String, CatalogEntry> refs; // normalised title -> entry
  final void Function(CatalogEntry) onTap;

  CatalogEntry? resolve(String label) => refs[label.toLowerCase().trim()];

  static _ReferenceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ReferenceScope>();

  @override
  bool updateShouldNotify(_ReferenceScope old) => old.refs != refs;
}

/// Drop-in for `Text` rendering the inline subset above. Stateful so tap
/// recognizers for `[[Name]]` references are disposed properly.
class _RichText extends StatefulWidget {
  const _RichText(this.text, {this.style});
  final String text;
  final TextStyle? style;

  @override
  State<_RichText> createState() => _RichTextState();
}

class _RichTextState extends State<_RichText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers(); // rebuilt fresh each build
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final scope = _ReferenceScope.maybeOf(context);
    return Text.rich(TextSpan(children: _spans(widget.text, base, scope)));
  }

  List<InlineSpan> _spans(String text, TextStyle? base, _ReferenceScope? scope) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _richPattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      final ref = m.group(1);
      if (ref != null) {
        spans.add(_referenceSpan(ref, base, scope));
      } else if (m.group(2) != null || m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(2) ?? m.group(3),
          style: base?.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (m.group(4) != null || m.group(5) != null) {
        spans.add(TextSpan(
          text: m.group(4) ?? m.group(5),
          style: base?.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (m.group(6) != null) {
        spans.add(TextSpan(
          text: m.group(6),
          style: base?.copyWith(
            fontFamily: 'monospace',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return spans;
  }

  /// A `[[Name]]` marker: a tappable link if it resolves to a card artifact,
  /// otherwise the bare name (brackets stripped) so unknown refs never leak.
  InlineSpan _referenceSpan(String label, TextStyle? base, _ReferenceScope? scope) {
    final entry = scope?.resolve(label);
    if (entry == null) return TextSpan(text: label, style: base);
    final recognizer = TapGestureRecognizer()..onTap = () => scope!.onTap(entry);
    _recognizers.add(recognizer);
    return TextSpan(
      text: label,
      style: base?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      recognizer: recognizer,
    );
  }
}

// --------------------------------------------------------------------------- //
// Per-block widgets
// --------------------------------------------------------------------------- //

class _Heading extends StatelessWidget {
  const _Heading(this.block);
  final HeadingBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = switch (block.level) {
      1 => theme.textTheme.headlineSmall,
      2 => theme.textTheme.titleLarge,
      _ => theme.textTheme.titleMedium,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(block.text, style: style?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.block);
  final ParagraphBlock block;

  @override
  Widget build(BuildContext context) =>
      _RichText(block.text, style: Theme.of(context).textTheme.bodyLarge);
}

class _BulletList extends StatelessWidget {
  const _BulletList(this.block);
  final BulletListBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in block.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9, right: 12),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: _RichText(item, style: theme.textTheme.bodyLarge),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.block, this.onToggle});
  final StepListBlock block;
  final ToggleCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = Column(
      children: [
        for (var i = 0; i < block.steps.length; i++)
          _StepRow(
            number: i + 1,
            step: block.steps[i],
            onToggle: block.steps[i].checkable && onToggle != null
                ? (checked) => onToggle!(block.id, i, checked)
                : null,
          ),
        if (block.steps.isEmpty)
          const SizedBox.shrink(),
      ].map((w) => w).toList(),
    )._dividedBy(theme);

    // Visual step strip (docs/09): a compact horizontal at-a-glance progress
    // row above the detailed list, for sequences of 3+ steps.
    if (block.steps.length < 3) return rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepStrip(steps: block.steps),
        const SizedBox(height: 12),
        rows,
      ],
    );
  }
}

/// Horizontal numbered strip summarising a step list; filled = done.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.steps});
  final List<Step> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, _) => _Connector(color: scheme.outlineVariant),
        itemBuilder: (ctx, i) {
          final done = steps[i].checked;
          return AnimatedContainer(
            duration: Motion.fast,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done ? scheme.primary : scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: done
                ? PhosphorIcon(PhosphorIconsRegular.check, size: 16, color: scheme.onPrimary)
                : Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: scheme.onPrimaryContainer,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 14,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          color: color,
        ),
      );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.step, this.onToggle});
  final int number;
  final Step step;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = step.checked;
    return InkWell(
      onTap: onToggle == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onToggle!(!done);
            },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StepMarker(number: number, done: done, checkable: onToggle != null),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _RichText(
                  step.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.number,
    required this.done,
    required this.checkable,
  });
  final int number;
  final bool done;
  final bool checkable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.fast,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: done ? scheme.primary : scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: done
          ? PhosphorIcon(PhosphorIconsRegular.check, size: 18, color: scheme.onPrimary)
          : Text(
              '$number',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: scheme.onPrimaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.block);
  final KeyValueBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < block.pairs.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      block.pairs[i].key,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Text(
                      block.pairs[i].value,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.block, this.onToggle});
  final ChecklistBlock block;
  final ToggleCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < block.items.length; i++)
          InkWell(
            onTap: onToggle == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onToggle!(block.id, i, !block.items[i].checked);
                  },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _CheckBox(checked: block.items[i].checked),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      block.items[i].text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: block.items[i].checked
                            ? TextDecoration.lineThrough
                            : null,
                        color: block.items[i].checked
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final box = AnimatedContainer(
      duration: Motion.fast,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? scheme.primary : null,
        shape: BoxShape.circle,
        border: checked
            ? null
            : Border.all(color: scheme.outline, width: 2),
      ),
      child: checked
          ? PhosphorIcon(PhosphorIconsRegular.check, size: 17, color: scheme.onPrimary)
          : null,
    );
    if (!checked) return box;
    return box.animate(key: const ValueKey('on')).scaleXY(
        begin: 0.7, end: 1, duration: Motion.fast, curve: Motion.spring);
  }
}

class _Callout extends StatelessWidget {
  const _Callout(this.block, {this.onOpenUrl});
  final CalloutBlock block;
  final OpenUrlCallback? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final (bg, fg, icon) = _style(block.variant, scheme);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RichText(block.text, style: theme.textTheme.bodyMedium),
                if (block.confidence != 'unverified' ||
                    block.sourceUrl != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _ConfidenceChip(confidence: block.confidence),
                      if (block.sourceUrl != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onOpenUrl == null
                              ? null
                              : () => onOpenUrl!(block.sourceUrl!),
                          child: Text(
                            'Source',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, PhosphorIconData) _style(String variant, ColorScheme s) {
    switch (variant) {
      case 'warning':
        return (
          const Color(0xFFFCEEEA),
          const Color(0xFFC1502E),
          PhosphorIconsRegular.warning
        );
      case 'caveat':
        return (
          const Color(0xFFFBF3E0),
          const Color(0xFF9A7711),
          PhosphorIconsRegular.warning
        );
      case 'source':
        return (
          s.surfaceContainerHigh,
          s.onSurfaceVariant,
          PhosphorIconsRegular.link
        );
      default: // info
        return (
          s.primaryContainer.withValues(alpha: 0.4),
          s.primary,
          PhosphorIconsRegular.info
        );
    }
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});
  final String confidence;

  @override
  Widget build(BuildContext context) {
    final color = switch (confidence) {
      'high' => const Color(0xFF2EA86A),
      'medium' => const Color(0xFFE0A92E),
      'low' => const Color(0xFFC1502E),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        confidence,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.block, {this.onOpenUrl});
  final LinkBlock block;
  final OpenUrlCallback? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpenUrl == null ? null : () => onOpenUrl!(block.url),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(PhosphorIconsRegular.link, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    block.label?.isNotEmpty == true ? block.label! : block.url,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table(this.block);
  final TableBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Table(
        border: TableBorder.symmetric(
          inside: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        // First column is the auto-number; keep it tight, let the rest flex.
        columnWidths: const {0: IntrinsicColumnWidth()},
        children: [
          TableRow(
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
            children: [
              _numCell('#', theme.textTheme.labelLarge, scheme),
              for (final h in block.headers)
                _cell(h, theme.textTheme.labelLarge, bold: true),
            ],
          ),
          for (var r = 0; r < block.rows.length; r++)
            TableRow(
              children: [
                _numCell('${r + 1}', theme.textTheme.bodyMedium, scheme),
                for (var i = 0; i < block.headers.length; i++)
                  _cell(
                    i < block.rows[r].length ? block.rows[r][i] : '',
                    theme.textTheme.bodyMedium,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _numCell(String text, TextStyle? style, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          text,
          style: style?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );

  Widget _cell(String text, TextStyle? style, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: _RichText(
          text,
          style: bold ? style?.copyWith(fontWeight: FontWeight.w700) : style,
        ),
      );
}

/// P2 block: render places as a simple list until the map renderer lands.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder(this.block);
  final MapBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in block.places)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PhosphorIcon(PhosphorIconsRegular.mapPin,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (p.note.isNotEmpty)
                          Text(p.note, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// Animation + layout helpers
// --------------------------------------------------------------------------- //

/// Fast top-down stagger as blocks build in (docs/07 motion token).
class _StaggeredIn extends StatefulWidget {
  const _StaggeredIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_StaggeredIn> createState() => _StaggeredInState();
}

class _StaggeredInState extends State<_StaggeredIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Motion.curve);
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    Future.delayed(Motion.stagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

extension on Column {
  /// Insert hairline dividers between step rows for scan-ability.
  Widget _dividedBy(ThemeData theme) {
    final kids = children;
    if (kids.length <= 1) return this;
    final divided = <Widget>[];
    for (var i = 0; i < kids.length; i++) {
      if (i > 0) {
        divided.add(Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ));
      }
      divided.add(kids[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: divided);
  }
}
