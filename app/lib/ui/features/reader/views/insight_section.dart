/// The deep-analysis layer (docs/14): claims, blind spots, rabbit holes, a small
/// topic map, and a doorway to the deep-research prompt. Rendered ONLY when a card
/// carries an `insight` (idea-rich content); a simple reel shows none of this. Each
/// sub-section guards on its own content, so a partial layer renders cleanly.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../domain/models/card.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/stat_strip.dart';
import 'chat_screen.dart';

class InsightSection extends StatelessWidget {
  const InsightSection({
    super.key,
    required this.insight,
    required this.accent,
    required this.cardId,
    required this.cardTitle,
    required this.readMinutes,
  });

  final Insight insight;
  final ContentAccent accent;
  final String cardId;
  final String cardTitle;

  /// Estimated read time of the card body, computed by the reader.
  final int readMinutes;

  List<Stat> _trio() {
    final rh = insight.rabbitHole;
    final threads =
        rh.questions.length + rh.adjacentTopics.length + rh.advancedConcepts.length;
    return [
      Stat(value: '${readMinutes < 1 ? 1 : readMinutes}m', label: 'Read'),
      Stat(value: '$threads', label: 'Threads', emphasize: true),
      if (insight.topicMap != null)
        Stat(value: '${insight.topicMap!.nodes.length}', label: 'Topics'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (!insight.rabbitHole.isEmpty) {
      children.add(_RabbitHoleCard(
        rabbitHole: insight.rabbitHole,
        accent: accent,
        cardId: cardId,
        cardTitle: cardTitle,
      ));
    }
    if (insight.topicMap != null) {
      children.add(_TopicMapCard(map: insight.topicMap!, accent: accent));
    }
    if (insight.hasDeepResearch) {
      children.add(_DeepResearchButton(prompt: insight.deepResearchPrompt!, accent: accent));
    }
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(icon: PhosphorIconsRegular.brain, label: 'Going deeper', accent: accent),
          const SizedBox(height: 12),
          StatStrip(stats: _trio()),
          const SizedBox(height: 14),
          _DiveDeeperButton(accent: accent, children: children),
        ],
      ),
    );
  }
}

class _DiveDeeperButton extends StatefulWidget {
  const _DiveDeeperButton({required this.accent, required this.children});
  final ContentAccent accent;
  final List<Widget> children;

  @override
  State<_DiveDeeperButton> createState() => _DiveDeeperButtonState();
}

class _DiveDeeperButtonState extends State<_DiveDeeperButton> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _expanded ? scheme.surfaceContainerHighest : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Insets.radius),
            side: BorderSide(
              color: _expanded ? widget.accent.color : scheme.outlineVariant,
              width: _expanded ? 1.5 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  PhosphorIcon(PhosphorIconsRegular.compass, size: 20, color: widget.accent.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dive deeper',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: PhosphorIcon(PhosphorIconsRegular.caretDown, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in widget.children)
                Padding(padding: const EdgeInsets.only(top: 12), child: child),
            ],
          ),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, required this.accent});
  final PhosphorIconData icon;
  final String label;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PhosphorIcon(icon, size: 16, color: accent.color),
        const SizedBox(width: 7),
        Text(label.toUpperCase(),
            style: Brand.label(size: 11, color: accent.color, weight: FontWeight.w700)),
      ],
    );
  }
}

/// A bordered container shared by the insight cards — matches the reader's
/// editorial surfaces.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final PhosphorIconData icon;
  final Widget child;

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
          Row(
            children: [
              PhosphorIcon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// --- Rabbit hole ----------------------------------------------------------- //

class _RabbitHoleCard extends StatelessWidget {
  const _RabbitHoleCard({
    required this.rabbitHole,
    required this.accent,
    required this.cardId,
    required this.cardTitle,
  });
  final RabbitHole rabbitHole;
  final ContentAccent accent;
  final String cardId;
  final String cardTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <(String, List<String>)>[
      ('Questions', rabbitHole.questions),
      ('Adjacent topics', rabbitHole.adjacentTopics),
      ('Advanced concepts', rabbitHole.advancedConcepts),
    ].where((g) => g.$2.isNotEmpty).toList();

    return _Panel(
      title: 'Rabbit hole',
      icon: PhosphorIconsRegular.compass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Tap a thread to go deeper — the card answers, grounded in its content.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          for (final group in groups)
            _RabbitHoleGroup(
              label: group.$1,
              items: group.$2,
              accent: accent,
              cardId: cardId,
              cardTitle: cardTitle,
            ),
        ],
      ),
    );
  }
}

class _RabbitHoleGroup extends StatelessWidget {
  const _RabbitHoleGroup({
    required this.label,
    required this.items,
    required this.accent,
    required this.cardId,
    required this.cardTitle,
  });
  final String label;
  final List<String> items;
  final ContentAccent accent;
  final String cardId;
  final String cardTitle;

  void _ask(BuildContext context, String thread) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(cardId: cardId, title: cardTitle, seed: thread),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        initiallyExpanded: true,
        title: Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('${items.length}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        children: [
          for (final item in items)
            InkWell(
              onTap: () => _ask(context, item),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: PhosphorIcon(PhosphorIconsRegular.chatCircle,
                          size: 15, color: accent.color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item,
                          style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
                    ),
                    PhosphorIcon(PhosphorIconsRegular.arrowUpRight,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Topic map ------------------------------------------------------------- //

class _TopicMapCard extends StatelessWidget {
  const _TopicMapCard({required this.map, required this.accent});
  final TopicMap map;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      title: 'Topic map',
      icon: PhosphorIconsRegular.graph,
      child: SizedBox(
        height: 260,
        width: double.infinity,
        child: CustomPaint(
          painter: _TopicMapPainter(
            center: map.center,
            nodes: map.nodes,
            accent: accent.color,
            line: scheme.outlineVariant,
            centerText: scheme.onPrimary,
            centerSubText: scheme.onPrimary.withValues(alpha: 0.7),
            nodeFill: scheme.surfaceContainerHighest,
            nodeText: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _TopicMapPainter extends CustomPainter {
  _TopicMapPainter({
    required this.center,
    required this.nodes,
    required this.accent,
    required this.line,
    required this.centerText,
    required this.centerSubText,
    required this.nodeFill,
    required this.nodeText,
  });

  final String center;
  final List<String> nodes;
  final Color accent;
  final Color line;
  final Color centerText;
  final Color centerSubText;
  final Color nodeFill;
  final Color nodeText;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    const centerR = 46.0;
    const nodeR = 30.0;

    final positions = <Offset>[];
    for (var i = 0; i < nodes.length; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / nodes.length);
      positions.add(Offset(c.dx + radius * math.cos(angle), c.dy + radius * math.sin(angle)));
    }

    final dashPaint = Paint()
      ..color = line
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final p in positions) {
      final dir = p - c;
      final len = dir.distance;
      if (len < 1) continue;
      final unit = dir / len;
      final start = c + unit * (centerR + 2);
      final stop = c + unit * (len - nodeR - 2);
      _dashedLine(canvas, start, stop, dashPaint, 4, 4);
    }

    final rimPaint = Paint()
      ..color = line
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < positions.length; i++) {
      canvas.drawCircle(positions[i], nodeR + 4, Paint()..color = accent.withValues(alpha: 0.05));
      canvas.drawCircle(positions[i], nodeR, Paint()..color = nodeFill);
      canvas.drawCircle(positions[i], nodeR, rimPaint);
      _label(canvas, nodes[i], positions[i], nodeR * 2 - 8, nodeText, 9);
    }

    canvas.drawCircle(c, centerR + 10, Paint()..color = accent.withValues(alpha: 0.12));
    canvas.drawCircle(c, centerR, Paint()..color = accent);

    final mainTp = _layout(center, centerR * 2 - 10, centerText, 12, bold: true);
    final subTp = _layout('${nodes.length} subtopics', centerR * 2 - 10, centerSubText, 9);
    final totalH = mainTp.height + 2 + subTp.height;
    mainTp.paint(canvas, Offset(c.dx - mainTp.width / 2, c.dy - totalH / 2));
    subTp.paint(canvas, Offset(c.dx - subTp.width / 2, c.dy - totalH / 2 + mainTp.height + 2));
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final delta = b - a;
    final len = delta.distance;
    if (len < 1) return;
    final dir = delta / len;
    var drawn = 0.0;
    while (drawn < len) {
      final start = a + dir * drawn;
      final end = a + dir * math.min(drawn + dash, len);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  TextPainter _layout(String text, double maxWidth, Color color, double fontSize,
      {bool bold = false}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  void _label(Canvas canvas, String text, Offset at, double maxWidth, Color color,
      double fontSize, {bool bold = false}) {
    final tp = _layout(text, maxWidth, color, fontSize, bold: bold);
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TopicMapPainter old) =>
      old.center != center || old.nodes != nodes || old.accent != accent;
}

// --- Deep research --------------------------------------------------------- //

class _DeepResearchButton extends StatelessWidget {
  const _DeepResearchButton({required this.prompt, required this.accent});
  final String prompt;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: accent.color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DeepResearchScreen(prompt: prompt, accent: accent)),
        ),
        icon: const PhosphorIcon(PhosphorIconsRegular.sparkle, size: 18),
        label: const Text('Deep research prompt'),
      ),
    );
  }
}

/// The deep-research prompt screen (docs/14): a ready-to-paste research brief for
/// an external frontier LLM. Copy is the dominant action.
class DeepResearchScreen extends StatelessWidget {
  const DeepResearchScreen({super.key, required this.prompt, required this.accent});
  final String prompt;
  final ContentAccent accent;

  int get _tokenEstimate => (prompt.length / 4).ceil();

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prompt copied'), duration: Motion.medium),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Deep research')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Insets.readingColumn),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 120),
            children: [
              Row(
                children: [
                  PhosphorIcon(PhosphorIconsRegular.sparkle, size: 16, color: accent.color),
                  const SizedBox(width: 7),
                  Text('DEEP RESEARCH PROMPT',
                      style: Brand.label(size: 11, color: accent.color, weight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text('~$_tokenEstimate tokens · paste into ChatGPT or Gemini',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(Insets.radius),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: SelectableText(
                  prompt,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.page, 8, Insets.page, 20),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _copy(context),
                icon: const PhosphorIcon(PhosphorIconsRegular.copy, size: 18),
                label: const Text('Copy prompt'),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: () => _copy(context),
              icon: const PhosphorIcon(PhosphorIconsRegular.export),
            ),
          ],
        ),
      ),
    );
  }
}
