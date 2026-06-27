/// First-run onboarding: detailed 3-phase showcase adapted from Insightr
/// (demo) featuring Cachy logo headers, Fraunces serif display headlines,
/// floating capability badges, mock structured feature cards, and library vault previews.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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

  void _next() {
    if (_index == 2) {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLast = _index == 2;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.45),
            radius: 1.3,
            colors: [
              scheme.primary.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar: Logo + Skip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _LogoBadge(),
                    TextButton(
                      onPressed: widget.onDone,
                      child: Text('Skip', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _page,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: const [
                    _PageHook(),
                    _PageStructure(),
                    _PageLibrary(),
                  ],
                ),
              ),
              // Bottom Controls
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          AnimatedContainer(
                            duration: Motion.fast,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index ? scheme.primary : scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLast ? 'Enter Cachy' : 'Continue',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          if (isLast) ...[
                            const SizedBox(width: 8),
                            const PhosphorIcon(PhosphorIconsRegular.arrowRight, size: 18),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: PhosphorIcon(PhosphorIconsRegular.lightning, color: scheme.onPrimary, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          'Cachy',
          style: Brand.wordmarkStyle(20, color: scheme.onSurface),
        ),
      ],
    );
  }
}

class _FloatingPill extends StatelessWidget {
  const _FloatingPill({required this.icon, required this.label});
  final PhosphorIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Text(label, style: Brand.label(size: 11, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _PageHook extends StatelessWidget {
  const _PageHook();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const _FloatingPill(icon: PhosphorIconsRegular.link, label: 'ANY SOURCE · ANY FORMAT'),
          const SizedBox(height: 32),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.fraunces(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                height: 1.1,
                color: scheme.onSurface,
              ),
              children: [
                const TextSpan(text: 'Any Link,\n'),
                TextSpan(
                  text: 'Captured.',
                  style: TextStyle(
                    color: scheme.primary,
                    shadows: [
                      Shadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _FloatingPill(icon: PhosphorIconsRegular.sparkle, label: 'ZERO SCROLLING'),
          const SizedBox(height: 32),
          Text(
            'Videos, articles, newsletters, Wikipedia — paste any link and Cachy distills the key takeaways into a browsable card.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageStructure extends StatelessWidget {
  const _PageStructure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: PhosphorIcon(PhosphorIconsRegular.stack, color: scheme.primary, size: 36),
          ),
          const SizedBox(height: 24),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.fraunces(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.1,
                color: scheme.onSurface,
              ),
              children: [
                const TextSpan(text: 'Every Source,\n'),
                TextSpan(text: 'Structured.', style: TextStyle(color: scheme.primary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Videos, articles, threads — any content becomes clean, scannable action cards.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          // Feature Showcase Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                _FeatureRow(
                  icon: PhosphorIconsRegular.listDashes,
                  title: 'Exact Ingredients & Steps',
                  subtitle: 'Extracted directly from on-screen text + voice',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: scheme.outlineVariant),
                ),
                _FeatureRow(
                  icon: PhosphorIconsRegular.mapPin,
                  title: 'Places & Coordinates',
                  subtitle: 'Hidden cafes and travel spots mapped out',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: scheme.outlineVariant),
                ),
                _FeatureRow(
                  icon: PhosphorIconsRegular.checkCircle,
                  title: 'Immediate To-Dos',
                  subtitle: 'Export checklists straight to your routine',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SmallTag('4 prep steps', active: true),
                    _SmallTag('Kyoto Speakeasy'),
                    _SmallTag('DIY Woodwork'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});
  final PhosphorIconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: PhosphorIcon(icon, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag(this.text, {this.active = false});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PageLibrary extends StatelessWidget {
  const _PageLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: PhosphorIcon(PhosphorIconsRegular.graph, color: scheme.primary, size: 36),
          ),
          const SizedBox(height: 24),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.fraunces(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.1,
                color: scheme.onSurface,
              ),
              children: [
                const TextSpan(text: 'Personal Web\n'),
                TextSpan(text: 'Of Action.', style: TextStyle(color: scheme.primary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Everything you keep is searchable and linked forever.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          // Vault Preview Card
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('My Cachy Vault', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Row(
                        children: [
                          PhosphorIcon(PhosphorIconsFill.bookmark, size: 14, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text('18 cards', style: Brand.label(size: 11, color: scheme.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                const _VaultRow(title: 'Crispy Chili Oil Eggs', tag: 'Recipe', time: 'Today'),
                Divider(height: 1, color: scheme.outlineVariant),
                const _VaultRow(title: 'Hidden Tokyo Speakeasy', tag: 'Travel', time: 'Yesterday'),
                Divider(height: 1, color: scheme.outlineVariant),
                const _VaultRow(title: 'Zone 2 Cardio Protocols', tag: 'Fitness', time: '3d ago'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({required this.title, required this.tag, required this.time});
  final String title;
  final String tag;
  final String time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(time, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(tag, style: Brand.label(size: 9, color: scheme.primary)),
          ),
        ],
      ),
    );
  }
}
