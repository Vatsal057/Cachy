/// First-run onboarding: three swipeable panels that teach the one loop —
/// share → structured card → do it. Each panel is a single idea with a small
/// motion accent (no external illustration assets). Skip or finish persists the
/// first-run flag (via [AppController.completeOnboarding]) and hands off to the
/// shell.
library;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _panels = [
    _Panel(
      icon: Icons.ios_share_rounded,
      title: 'Share a reel to Cachy',
      body: 'See something worth keeping on Instagram, TikTok or YouTube? '
          'Hit share and pick Cachy.',
    ),
    _Panel(
      icon: Icons.auto_awesome_rounded,
      title: 'We make it readable',
      body: 'Cachy watches the video and turns it into a clean card — steps, '
          'ingredients, places, the gist. No rewatching.',
    ),
    _Panel(
      icon: Icons.checklist_rounded,
      title: 'Then actually use it',
      body: 'Tick off steps, build a shopping list, save the place, set a '
          'reminder. The reel becomes something you do.',
    ),
  ];

  bool get _isLast => _index == _panels.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      _page.nextPage(duration: Motion.medium, curve: Motion.curve);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: _panels,
              ),
            ),
            // Page dots.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _panels.length; i++)
                  AnimatedContainer(
                    duration: Motion.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, 24),
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: Text(_isLast ? 'Get started' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.page * 1.4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RingedIcon(icon: icon),
          const SizedBox(height: 40),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// A haloed feature icon: a filled tinted core ringed by two concentric outlines
/// that fade outward — the onboarding's "feature highlight" motif.
class _RingedIcon extends StatelessWidget {
  const _RingedIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget ring(double size, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: primary.withValues(alpha: alpha)),
          ),
        );
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ring(168, 0.10),
          ring(140, 0.20),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: primary.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 50, color: primary),
          ),
        ],
      ),
    );
  }
}
