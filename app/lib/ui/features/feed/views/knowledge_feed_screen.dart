/// The Knowledge Feed — "scroll your own brain". A full-screen, vertical,
/// reel-style feed where every page is a moment distilled from the user's saved
/// cards: a core insight, a highlight, a quick quiz, a rabbit-hole doorway, or a
/// surprising connection between two cards. Swipe up for the next.
///
/// The point: the addictive short-form format that got the knowledge in — turned
/// back on the knowledge itself, so revisiting your library feels like a feed,
/// not a filing cabinet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/feed.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/rich_text.dart';
import '../../reader/views/rabbit_hole_screen.dart';
import '../../reader/views/reader_screen.dart';
import '../view_models/knowledge_feed_view_model.dart';

class KnowledgeFeedScreen extends StatelessWidget {
  const KnowledgeFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) =>
          KnowledgeFeedViewModel(repository: ctx.read<CardRepository>())..load(),
      child: const _FeedView(),
    );
  }
}

class _FeedView extends StatefulWidget {
  const _FeedView();

  @override
  State<_FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<_FeedView> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<KnowledgeFeedViewModel>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          _content(context, vm),
          _TopBar(
            index: _page,
            total: vm.items.length,
            onClose: () => Navigator.of(context).maybePop(),
            onRefresh: vm.loading ? null : vm.refresh,
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, KnowledgeFeedViewModel vm) {
    if (vm.loading && vm.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && vm.isEmpty) {
      return ErrorState(
        title: "Can't load your feed",
        message: vm.error!,
        onRetry: vm.load,
      );
    }
    if (vm.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: EmptyState(
          showGlyph: true,
          halo: true,
          title: 'Your feed is waiting',
          message:
              'Save a few reels and Cachy turns them into a feed of your own '
              'knowledge — insights, quizzes, and surprising connections to swipe through.',
        ),
      );
    }

    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      itemCount: vm.items.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (ctx, i) => _MomentPage(
        item: vm.items[i],
        showSwipeHint: i == 0 && vm.items.length > 1,
      ),
    );
  }
}

// ── Top overlay bar ─────────────────────────────────────────────────────── //

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.total,
    required this.onClose,
    required this.onRefresh,
  });
  final int index;
  final int total;
  final VoidCallback onClose;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: const PhosphorIcon(PhosphorIconsRegular.x),
              tooltip: 'Close',
            ),
            const Spacer(),
            if (total > 0)
              Text('${index + 1} / $total',
                  style: Brand.label(
                      size: 11, color: scheme.onSurfaceVariant, weight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              onPressed: onRefresh,
              icon: const PhosphorIcon(PhosphorIconsRegular.shuffle),
              tooltip: 'Shuffle',
            ),
          ],
        ),
      ),
    );
  }
}

// ── One moment (a single full-screen page) ──────────────────────────────── //

class _MomentPage extends StatelessWidget {
  const _MomentPage({required this.item, this.showSwipeHint = false});
  final FeedItem item;
  final bool showSwipeHint;

  @override
  Widget build(BuildContext context) {
    final accent = ContentAccent.of(item.card.contentType);
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.color.withValues(alpha: 0.16),
            scheme.surface,
            scheme.surface,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 64, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Eyebrow(item: item, accent: accent),
              Expanded(child: _MomentBody(item: item, accent: accent)),
              _SourceFooter(item: item, accent: accent),
              if (showSwipeHint) ...[
                const SizedBox(height: 10),
                const Center(child: _SwipeHint()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

({String label, PhosphorIconData icon}) _kindMeta(FeedItemKind kind) {
  switch (kind) {
    case FeedItemKind.insight:
      return (label: 'INSIGHT', icon: PhosphorIconsRegular.lightbulb);
    case FeedItemKind.highlight:
      return (label: 'HIGHLIGHT', icon: PhosphorIconsRegular.quotes);
    case FeedItemKind.quiz:
      return (label: 'QUICK QUIZ', icon: PhosphorIconsRegular.target);
    case FeedItemKind.thread:
      return (label: 'RABBIT HOLE', icon: PhosphorIconsRegular.compass);
    case FeedItemKind.connection:
      return (label: 'CONNECTION', icon: PhosphorIconsRegular.link);
    case FeedItemKind.unknown:
      return (label: 'MOMENT', icon: PhosphorIconsRegular.sparkle);
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.item, required this.accent});
  final FeedItem item;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(item.kind);
    return Row(
      children: [
        PhosphorIcon(meta.icon, size: 16, color: accent.color),
        const SizedBox(width: 8),
        Text(meta.label,
            style: Brand.label(size: 12, color: accent.color, weight: FontWeight.w700)),
      ],
    ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.05, end: 0);
  }
}

class _MomentBody extends StatelessWidget {
  const _MomentBody({required this.item, required this.accent});
  final FeedItem item;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (item.kind) {
      FeedItemKind.quiz when item.quizValid => _QuizMoment(item: item, accent: accent),
      FeedItemKind.thread => _ThreadMoment(item: item, accent: accent),
      FeedItemKind.connection when item.cardB != null =>
        _ConnectionMoment(item: item, accent: accent),
      _ => _TextMoment(item: item),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(child: child),
    ).animate().fadeIn(duration: 350.ms, delay: 60.ms).slideY(begin: 0.04, end: 0);
  }
}

/// Insight / highlight — a big editorial line, rendered like a pull-quote.
class _TextMoment extends StatelessWidget {
  const _TextMoment({required this.item});
  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.kind == FeedItemKind.highlight)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PhosphorIcon(PhosphorIconsFill.quotes,
                size: 30, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          ),
        RichInlineText(
          item.text,
          style: theme.textTheme.headlineMedium?.copyWith(height: 1.28, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Rabbit-hole doorway — a prompt plus a button that drops into the explorer.
class _ThreadMoment extends StatelessWidget {
  const _ThreadMoment({required this.item, required this.accent});
  final FeedItem item;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.text,
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.3, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accent.color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RabbitHoleScreen(
                cardId: item.card.cardId,
                seed: item.text,
                accent: accent,
              ),
            ),
          ),
          icon: const PhosphorIcon(PhosphorIconsRegular.compass, size: 18),
          label: const Text('Fall down the rabbit hole'),
        ),
      ],
    );
  }
}

/// Connection — two cards + the surprising link between them.
class _ConnectionMoment extends StatelessWidget {
  const _ConnectionMoment({required this.item, required this.accent});
  final FeedItem item;
  final ContentAccent accent;

  void _open(BuildContext context, String cardId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(cardId: cardId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = item.cardB!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniCard(ref: item.card, onTap: () => _open(context, item.card.cardId)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              PhosphorIcon(PhosphorIconsRegular.link, size: 16, color: accent.color),
              const SizedBox(width: 8),
              Text('shares a thread with',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        _MiniCard(ref: b, onTap: () => _open(context, b.cardId)),
        const SizedBox(height: 22),
        RichInlineText(
          item.text,
          style: theme.textTheme.titleLarge?.copyWith(height: 1.35, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.ref, required this.onTap});
  final FeedCardRef ref;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = ContentAccent.of(ref.contentType);
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Insets.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Insets.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Insets.radius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              PhosphorIcon(accent.icon, size: 18, color: accent.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(ref.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              PhosphorIcon(PhosphorIconsRegular.arrowUpRight,
                  size: 14, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Source footer — where the moment came from, tappable into the reader.
class _SourceFooter extends StatelessWidget {
  const _SourceFooter({required this.item, required this.accent});
  final FeedItem item;
  final ContentAccent accent;

  @override
  Widget build(BuildContext context) {
    // Connection moments carry their own tappable cards; no single source.
    if (item.kind == FeedItemKind.connection) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderScreen(cardId: item.card.cardId)),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            PhosphorIcon(accent.icon, size: 16, color: accent.color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FROM YOUR LIBRARY',
                      style: Brand.label(
                          size: 9, color: scheme.onSurfaceVariant, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(item.card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('READ',
                style: Brand.label(size: 10, color: accent.color, weight: FontWeight.w700)),
            PhosphorIcon(PhosphorIconsRegular.caretRight, size: 14, color: accent.color),
          ],
        ),
      ),
    );
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(PhosphorIconsRegular.caretUp, size: 18, color: scheme.onSurfaceVariant),
        Text('SWIPE UP',
            style: Brand.label(size: 9, color: scheme.onSurfaceVariant, weight: FontWeight.w600)),
      ],
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(begin: 4, end: -4, duration: 900.ms, curve: Curves.easeInOut);
  }
}

// ── Interactive quiz moment ─────────────────────────────────────────────── //

const Color _kQuizCorrect = Color(0xFF2E7D52);

class _QuizMoment extends StatefulWidget {
  const _QuizMoment({required this.item, required this.accent});
  final FeedItem item;
  final ContentAccent accent;

  @override
  State<_QuizMoment> createState() => _QuizMomentState();
}

class _QuizMomentState extends State<_QuizMoment> {
  int? _selected;
  bool get _answered => _selected != null;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.question,
            style: theme.textTheme.headlineSmall?.copyWith(height: 1.3, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        for (var i = 0; i < item.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QuizOption(
              text: item.options[i],
              correct: i == item.answerIndex,
              selected: i == _selected,
              answered: _answered,
              accent: widget.accent,
              onTap: () => setState(() => _selected = i),
            ),
          ),
        if (_answered && item.explanation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhosphorIcon(
                _selected == item.answerIndex
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsFill.info,
                size: 18,
                color: _selected == item.answerIndex ? _kQuizCorrect : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.explanation,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
              ),
            ],
          ).animate().fadeIn(duration: 250.ms),
        ],
      ],
    );
  }
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.text,
    required this.correct,
    required this.selected,
    required this.answered,
    required this.accent,
    required this.onTap,
  });
  final String text;
  final bool correct;
  final bool selected;
  final bool answered;
  final ContentAccent accent;
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
    if (answered) {
      if (correct) {
        border = _kQuizCorrect;
        bg = _kQuizCorrect.withValues(alpha: 0.10);
        icon = PhosphorIconsFill.checkCircle;
        iconColor = _kQuizCorrect;
      } else if (selected) {
        border = scheme.error;
        bg = scheme.error.withValues(alpha: 0.10);
        icon = PhosphorIconsFill.xCircle;
        iconColor = scheme.error;
      } else {
        fg = scheme.onSurfaceVariant;
      }
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(Insets.radius),
      child: InkWell(
        onTap: answered ? null : onTap,
        borderRadius: BorderRadius.circular(Insets.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Insets.radius),
            border: Border.all(color: border, width: answered ? 1.5 : 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(text,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: fg, fontWeight: FontWeight.w500, height: 1.3)),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                PhosphorIcon(icon, size: 20, color: iconColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
