/// First-run onboarding: three swipeable panels that teach the one loop —
/// share → structured card → do it. Each panel is a single idea with a small
/// motion accent (no external illustration assets). Skip or finish persists the
/// first-run flag (via [AppController.completeOnboarding]) and hands off to the
/// shell.
library;

import 'package:flutter/material.dart';

import '../../../core/brand.dart';
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
                      color: i == _index ? Brand.violet : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.page, 0, Insets.page, 24),
              child: GestureDetector(
                onTap: _next,
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: Brand.gradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: Brand.glow(opacity: 0.35, blur: 18, y: 6),
                  ),
                  child: Text(
                    _isLast ? 'Get started' : 'Next',
                    style: Brand.wordmarkStyle(17, color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w700),
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
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Brand.violet.withValues(alpha: 0.16),
                  Brand.indigo.withValues(alpha: 0.10),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 58, color: Brand.violet),
          ),
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
