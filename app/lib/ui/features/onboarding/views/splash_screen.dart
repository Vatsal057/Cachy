/// The launch moment: the brand glyph "catches" a falling reel, then the
/// wordmark draws in. Plays over the calm paper ground, ~1.3 s, then [onDone]
/// fires. Tappable to skip.
library;

import 'package:flutter/material.dart';

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
    if (!mounted || _done) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groundColor = isDark ? Brand.charcoalGround : Brand.paperGround;
    final textColor = isDark ? Brand.cream : Brand.ink;
    final accentColor = Brand.accentFor(Theme.of(context).brightness);

    return GestureDetector(
      onTap: _finish,
      child: Scaffold(
        backgroundColor: groundColor,
        body: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachyGlyph(
                  size: 92,
                  color: textColor,
                  reelColor: accentColor,
                  reelDrop: _drop.value,
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: _wordmark.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, (1 - _wordmark.value) * 10),
                    child: Text(
                      'cachy',
                      style: Brand.wordmarkStyle(44, color: textColor),
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

/// Static variant used while the app boots (no animation).
class SplashStatic extends StatelessWidget {
  const SplashStatic({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Brand.charcoalGround : Brand.paperGround,
      body: Center(
        child: CachyGlyph(
          size: 92,
          color: isDark ? Brand.cream : Brand.ink,
          reelColor: Brand.accentFor(Theme.of(context).brightness),
        ),
      ),
    );
  }
}
