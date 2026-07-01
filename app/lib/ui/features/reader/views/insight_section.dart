/// The deep-analysis layer (docs/14): rabbit-hole threads to explore, a short
/// "test yourself" quiz for active recall, and a doorway to the deep-research
/// prompt. Rendered ONLY when a card carries an `insight` (idea-rich content); a
/// simple reel shows none of this. Each sub-section guards on its own content.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../domain/models/card.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/stat_strip.dart';
import 'rabbit_hole_screen.dart';

/// Hard ceiling on rabbit-hole starter threads shown in the panel — keeps the
/// list scannable no matter how many the (possibly older, larger) card carries.
const int _kMaxThreads = 5;

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
    final unique = <String>{
      ...rh.questions.map((s) => s.toLowerCase().trim()),
      ...rh.adjacentTopics.map((s) => s.toLowerCase().trim()),
      ...rh.advancedConcepts.map((s) => s.toLowerCase().trim()),
    }..removeWhere((s) => s.isEmpty);
    final threads = unique.length > _kMaxThreads ? _kMaxThreads : unique.length;
    return [
      Stat(value: '${readMinutes < 1 ? 1 : readMinutes}m', label: 'Read'),
      if (!rh.isEmpty)
        Stat(value: '$threads', label: 'Threads', emphasize: true),
      if (insight.hasQuiz)
        Stat(value: '${insight.quiz.questions.length}', label: 'Quiz'),
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
      ));
    }
    if (insight.hasQuiz) {
      children.add(_QuizCard(quiz: insight.quiz, accent: accent));
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

class _RabbitHoleCard extends StatefulWidget {
  const _RabbitHoleCard({
    required this.rabbitHole,
    required this.accent,
    required this.cardId,
  });
  final RabbitHole rabbitHole;
  final ContentAccent accent;
  final String cardId;

  @override
  State<_RabbitHoleCard> createState() => _RabbitHoleCardState();
}

class _RabbitHoleCardState extends State<_RabbitHoleCard> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  /// The three source lists flattened into one ordered set of starter threads —
  /// questions first (most tappable), then topics, then advanced concepts. They
  /// all open the same explorer now, so a single tidy list beats three lists.
  /// Hard-capped at [_kMaxThreads] so the panel never overwhelms.
  List<String> get _threads {
    final rh = widget.rabbitHole;
    final seen = <String>{};
    final out = <String>[];
    for (final t in [...rh.questions, ...rh.adjacentTopics, ...rh.advancedConcepts]) {
      final key = t.toLowerCase().trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(t);
      if (out.length >= _kMaxThreads) break;
    }
    return out;
  }

  void _open(String thread) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RabbitHoleScreen(cardId: widget.cardId, seed: thread, accent: widget.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = _threads;
    final visible = _expanded ? all : all.take(_collapsedCount).toList();
    final hidden = all.length - visible.length;

    return _Panel(
      title: 'Rabbit hole',
      icon: PhosphorIconsRegular.compass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Tap a thread to fall in — each answer opens new ones.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
            _ThreadRow(
              label: visible[i],
              accent: widget.accent,
              onTap: () => _open(visible[i]),
            ),
          ],
          if (all.length > _collapsedCount)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: widget.accent.color,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(_expanded ? 'Show less' : 'Show $hidden more'),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single tappable starter thread — a lean row with an accent dot and a
/// navigation cue, so a handful read as a clean list rather than a wall.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.label, required this.accent, required this.onTap});
  final String label;
  final ContentAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 7, right: 11),
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle),
            ),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(height: 1.3, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: PhosphorIcon(PhosphorIconsRegular.arrowRight,
                  size: 14, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Quiz ------------------------------------------------------------------ //

class _QuizCard extends StatefulWidget {
  const _QuizCard({required this.quiz, required this.accent});
  final Quiz quiz;
  final ContentAccent accent;

  @override
  State<_QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<_QuizCard> {
  int _index = 0;
  int? _selected;
  int _score = 0;
  bool _finished = false;

  List<QuizQuestion> get _questions => widget.quiz.questions;
  QuizQuestion get _q => _questions[_index];
  bool get _answered => _selected != null;
  bool get _isLast => _index + 1 >= _questions.length;

  void _pick(int i) {
    if (_answered) return;
    setState(() {
      _selected = i;
      if (i == _q.answerIndex) _score++;
    });
  }

  void _next() {
    setState(() {
      if (_isLast) {
        _finished = true;
      } else {
        _index++;
        _selected = null;
      }
    });
  }

  void _restart() => setState(() {
        _index = 0;
        _selected = null;
        _score = 0;
        _finished = false;
      });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Test yourself',
      icon: PhosphorIconsRegular.target,
      child: _finished ? _results(context) : _question(context),
    );
  }

  Widget _question(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _questions.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (_index + (_answered ? 1 : 0)) / total,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: widget.accent.color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${_index + 1}/$total',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 16),
        Text(_q.question,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
        const SizedBox(height: 14),
        for (var i = 0; i < _q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionTile(
              text: _q.options[i],
              state: !_answered
                  ? _OptState.idle
                  : i == _q.answerIndex
                      ? _OptState.correct
                      : i == _selected
                          ? _OptState.wrong
                          : _OptState.dim,
              onTap: () => _pick(i),
            ),
          ),
        if (_answered) ...[
          const SizedBox(height: 4),
          _explanation(context),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _next,
              icon: PhosphorIcon(
                  _isLast
                      ? PhosphorIconsRegular.flagCheckered
                      : PhosphorIconsRegular.arrowRight,
                  size: 18),
              label: Text(_isLast ? 'See results' : 'Next question'),
            ),
          ),
        ],
      ],
    ).animate(key: ValueKey('q$_index')).fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _explanation(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final right = _selected == _q.answerIndex;
    final color = right ? _kQuizCorrect : scheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(
              right ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.xCircle,
              size: 18,
              color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(right ? 'Correct' : 'Not quite',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                if (_q.explanation.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_q.explanation,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurface, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _questions.length;
    final pct = _score / total;
    final (msg, emoji) = pct == 1
        ? ('Perfect run.', '🎯')
        : pct >= 0.6
            ? ('Solid — you got the gist.', '💪')
            : ('Worth another read.', '📖');
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text('$_score / $total',
            style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800, color: widget.accent.color)),
        const SizedBox(height: 4),
        Text(msg,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _restart,
            icon: const PhosphorIcon(PhosphorIconsRegular.arrowClockwise, size: 16),
            label: const Text('Try again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accent.color,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms).scaleXY(begin: 0.96, end: 1, curve: Curves.easeOutBack);
  }
}

/// Visual state of a quiz option once the reader has (or hasn't) answered.
enum _OptState { idle, correct, wrong, dim }

/// Success green for quiz feedback — reads as "right" independent of the card's
/// content accent (which is reserved for navigation/branding).
const Color _kQuizCorrect = Color(0xFF2E7D52);

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.text, required this.state, required this.onTap});
  final String text;
  final _OptState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var border = scheme.outlineVariant;
    var bg = scheme.surfaceContainerLow;
    var fg = scheme.onSurface;
    IconData? icon;
    var iconColor = scheme.onSurfaceVariant;
    switch (state) {
      case _OptState.idle:
        break;
      case _OptState.correct:
        border = _kQuizCorrect;
        bg = _kQuizCorrect.withValues(alpha: 0.10);
        icon = PhosphorIconsFill.checkCircle;
        iconColor = _kQuizCorrect;
      case _OptState.wrong:
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.10);
        icon = PhosphorIconsFill.xCircle;
        iconColor = scheme.error;
      case _OptState.dim:
        fg = scheme.onSurfaceVariant;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(Insets.radius),
      child: InkWell(
        onTap: state == _OptState.idle ? onTap : null,
        borderRadius: BorderRadius.circular(Insets.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Insets.radius),
            border: Border.all(color: border, width: state == _OptState.idle ? 1 : 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: fg, fontWeight: FontWeight.w500, height: 1.3)),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                PhosphorIcon(icon, size: 18, color: iconColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
              Text('~$_tokenEstimate tokens · paste into ChatGPT, Claude or Gemini',
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
