/// The launch moment: the brand glyph "catches" a falling reel, then the
/// wordmark draws in. Plays over the calm paper ground, ~1.3 s, then [onDone]
/// fires. Tappable to skip.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _drop;
  late final Animation<double> _wordmark;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _drop = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _wordmark = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );
    _c.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _finish,
      child: Scaffold(
        backgroundColor: Brand.paperGround,
        body: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachyGlyph(
                  size: 92,
                  color: Brand.ink,
                  reelColor: Brand.sage,
                  reelDrop: _drop.value,
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: _wordmark.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - _wordmark.value) * 10),
                    child: Text(
                      'cachy',
                      style: Brand.wordmarkStyle(44, color: Brand.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _FloatingChip(
                  icon: PhosphorIconsRegular.videoCamera,
                  label: 'Short-form videos',
                  t: _wordmark.value,
                ),
                const SizedBox(height: 12),
                _FloatingChip(
                  icon: PhosphorIconsRegular.sparkle,
                  label: 'AI-powered recall',
                  t: (_wordmark.value * 1.25 - 0.25).clamp(0.0, 1.0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip({required this.icon, required this.label, required this.t});
  final PhosphorIconData icon;
  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Brand.paperRaised,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Brand.ink.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(icon, size: 15, color: Brand.sage),
              const SizedBox(width: 8),
              Text(
                label,
                style: Brand.label(
                  size: 12,
                  color: Brand.ink,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static variant used while the app boots (no animation).
class SplashStatic extends StatelessWidget {
  const SplashStatic({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.paperGround,
      body: const Center(
        child: CachyGlyph(size: 92, color: Brand.ink, reelColor: Brand.sage),
      ),
    );
  }
}
