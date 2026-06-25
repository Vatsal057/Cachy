/// The block renderer (docs/06 core): maps the fixed block vocabulary from
/// docs/04 to one widget per entry. Unknown/future blocks degrade gracefully —
/// render `text`/`items` if present, else skip. Never crashes on a bad block.
library;

import 'package:flutter/material.dart' hide Step;

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
    this.animate = true,
  });

  final List<Block> blocks;
  final ToggleCallback? onToggleChecklist;
  final ToggleCallback? onToggleStep;
  final OpenUrlCallback? onOpenUrl;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final w = _renderBlock(context, blocks[i]);
      if (w == null) continue; // skipped (e.g. empty unknown block)
      widgets.add(Padding(
        padding: EdgeInsets.only(bottom: Insets.block),
        child: animate
            ? _StaggeredIn(index: widgets.length, child: w)
            : w,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
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
      Text(block.text, style: Theme.of(context).textTheme.bodyLarge);
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
                  child: Text(item, style: theme.textTheme.bodyLarge),
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
        separatorBuilder: (_, __) => _Connector(color: scheme.outlineVariant),
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
                ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
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
      onTap: onToggle == null ? null : () => onToggle!(!done),
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
                child: Text(
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
          ? Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary)
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
                : () => onToggle!(block.id, i, !block.items[i].checked),
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
    return AnimatedContainer(
      duration: Motion.fast,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: checked ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: 17, color: scheme.onPrimary)
          : null,
    );
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
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(block.text, style: theme.textTheme.bodyMedium),
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

  (Color, Color, IconData) _style(String variant, ColorScheme s) {
    switch (variant) {
      case 'warning':
        return (
          const Color(0xFFFCEEEA),
          const Color(0xFFC1502E),
          Icons.warning_amber_rounded
        );
      case 'caveat':
        return (
          const Color(0xFFFBF3E0),
          const Color(0xFF9A7711),
          Icons.error_outline_rounded
        );
      case 'source':
        return (
          s.surfaceContainerHigh,
          s.onSurfaceVariant,
          Icons.link_rounded
        );
      default: // info
        return (
          s.primaryContainer.withValues(alpha: 0.4),
          s.primary,
          Icons.info_outline_rounded
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
                Icon(Icons.link_rounded, size: 18, color: scheme.primary),
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
        children: [
          TableRow(
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
            children: [
              for (final h in block.headers)
                _cell(h, theme.textTheme.labelLarge),
            ],
          ),
          for (final row in block.rows)
            TableRow(
              children: [
                for (var i = 0; i < block.headers.length; i++)
                  _cell(i < row.length ? row[i] : '', theme.textTheme.bodyMedium),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, TextStyle? style) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(text, style: style),
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
                  Icon(Icons.place_rounded,
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
