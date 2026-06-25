/// The launch moment: the brand glyph "catches" a falling reel, then the
/// wordmark draws in. Plays over the brand gradient, ~1.3s, then [onDone] fires.
/// Tappable to skip. The native splash (flutter_native_splash) covers the gap
/// before Flutter is up; this continues the same gesture seamlessly.
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
        backgroundColor: Brand.creamGround,
        body: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachyGlyph(
                  size: 92,
                  color: Brand.ink,
                  reelColor: Brand.rust,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small loading splash variant reused while the app boots, without animation.
class SplashStatic extends StatelessWidget {
  const SplashStatic({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Brand.creamGround,
      body: Center(child: CachyGlyph(size: 92, color: Brand.ink, reelColor: Brand.rust)),
    );
  }
}
