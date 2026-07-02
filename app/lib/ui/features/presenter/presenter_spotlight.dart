/// The guided-focus layer for Present mode: while the agent presents a beat it
/// dims the surrounding interface, lights the widget it's talking about, and
/// glides a presentation cursor there — the coach-marks feel of an app's
/// first-run tour.
///
/// Targets are real widgets: screens register a GlobalKey per target id on the
/// [AgentBus] (see `agent_bus.dart`), and this layer resolves live geometry
/// from the key every ~150 ms while lit, so the hole hugs the actual widget
/// even if it mounts late or the layout shifts. Ids with no registered widget
/// fall back to a coarse screen region. The layer stays mounted for the whole
/// presentation so the hole and cursor *animate between* targets instead of
/// restarting, and it's wrapped in [IgnorePointer] so it never blocks input.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'agent_bus.dart';
import 'presenter_controller.dart';

class PresenterSpotlight extends StatefulWidget {
  const PresenterSpotlight({
    super.key,
    required this.controller,
    required this.bus,
  });

  final PresenterController controller;
  final AgentBus bus;

  @override
  State<PresenterSpotlight> createState() => _PresenterSpotlightState();
}

class _PresenterSpotlightState extends State<PresenterSpotlight> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFocusChanged);
    _onFocusChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFocusChanged);
    _poll?.cancel();
    super.dispose();
  }

  /// While a target is lit, re-resolve its geometry a few times a second so a
  /// screen that mounts (or scrolls) after navigation still gets hugged.
  void _onFocusChanged() {
    final lit = widget.controller.focusId != null;
    if (lit && _poll == null) {
      _poll = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (mounted) setState(() {});
      });
    } else if (!lit) {
      _poll?.cancel();
      _poll = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final id = widget.controller.focusId;
            final rect = id == null ? null : _resolve(id, size);
            // Dim the app only around genuinely small controls (a button, a nav
            // item, the action bar). For anything larger, dimming reads as the
            // whole screen going dark — distracting — so we skip the scrim and
            // just let the cursor + a soft ring point the way.
            final small = rect != null &&
                rect.width * rect.height < size.width * size.height * 0.22;
            return _Guidance(
              target: rect,
              dim: small,
              tapping: widget.controller.tapping,
              screen: size,
              color: Theme.of(context).colorScheme.primary,
            );
          },
        ),
      ),
    );
  }

  /// Real widget bounds when the target is registered and mounted, else a
  /// generous fallback region so guidance degrades instead of vanishing.
  Rect _resolve(String id, Size size) {
    final live = widget.bus.spotlightRect(id);
    if (live != null && !live.isEmpty) {
      // Keep the hole on screen even if the widget hangs off an edge.
      final screen = Offset.zero & size;
      final clamped = live.intersect(screen.inflate(-4));
      if (!clamped.isEmpty) return clamped;
    }
    return _fallbackRect(id, size);
  }

  Rect _fallbackRect(String id, Size size) {
    final w = size.width;
    final h = size.height;
    final desktop = w >= Insets.desktop;
    // Bottom nav / side rail.
    if (id == 'nav' || id.startsWith('nav.')) {
      return desktop
          ? Rect.fromLTWH(0, h * 0.18, 88, h * 0.64) // left rail
          : Rect.fromLTWH(w * 0.08, h - 100, w * 0.84, 74); // bottom pill
    }
    // Add button — bottom-right on mobile, in the rail on desktop.
    if (id == 'home.plus') {
      return desktop
          ? Rect.fromLTWH(16, 24, 56, 56)
          : Rect.fromLTWH(w - 88, h - 168, 64, 64);
    }
    // Top bar: search field, top-bar icons, library segment tabs.
    if (id.startsWith('search.') ||
        id.startsWith('top.') ||
        id.startsWith('library.tab') ||
        id == 'top') {
      final left = w * (desktop ? 0.18 : 0.06);
      return Rect.fromLTWH(left, 8, w - left - 16, 96);
    }
    // The main content stage ('content', 'feed.page', 'graph.canvas',
    // 'card.first', 'reader.*', 'catalog.item', 'folders.*', 'todo.*', …).
    final left = desktop ? 96.0 : w * 0.06;
    return Rect.fromLTWH(
      left,
      h * 0.14,
      w - left - (desktop ? 24 : w * 0.06),
      h * 0.66,
    );
  }
}

/// Always mounted so the implicit tweens retarget — the hole and cursor glide
/// from the previous target to the next instead of resetting. When [target] is
/// null the whole layer just fades out, holding its last geometry.
class _Guidance extends StatefulWidget {
  const _Guidance({
    required this.target,
    required this.dim,
    required this.tapping,
    required this.screen,
    required this.color,
  });

  final Rect? target;

  /// Punch a dimming hole around the target (only worthwhile for small ones).
  final bool dim;

  /// The agent is tapping the target right now — render a tap ripple.
  final bool tapping;

  final Size screen;
  final Color color;

  @override
  State<_Guidance> createState() => _GuidanceState();
}

class _GuidanceState extends State<_Guidance> {
  late Rect _target = Rect.fromCenter(
    center: widget.screen.center(Offset.zero),
    width: 120,
    height: 120,
  );

  @override
  void initState() {
    super.initState();
    if (widget.target != null) _target = widget.target!;
  }

  @override
  void didUpdateWidget(_Guidance old) {
    super.didUpdateWidget(old);
    // Adopt a new target only when it actually moved — the ~150ms geometry
    // poll re-resolves the same widget with sub-pixel jitter every tick, and
    // feeding that into the tween would restart the glide forever (the old
    // "broken spotlight"). A few pixels of slack absorbs the jitter.
    final t = widget.target;
    if (t != null && !_closeEnough(t, _target)) _target = t;
  }

  bool _closeEnough(Rect a, Rect b) =>
      (a.center - b.center).distance < 6 &&
      (a.width - b.width).abs() < 6 &&
      (a.height - b.height).abs() < 6;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.target != null ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: TweenAnimationBuilder<Rect?>(
        // Only `end` matters — TweenAnimationBuilder animates from the current
        // in-flight value to a new end whenever it changes, so the hole and
        // cursor glide smoothly target-to-target.
        tween: RectTween(begin: _target, end: _target),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
        builder: (context, animated, _) {
          final r = animated ?? _target;
          return Stack(
            children: [
              if (widget.dim)
                Positioned.fill(
                  child:
                      CustomPaint(painter: _SpotlightPainter(r, widget.color)),
                ),
              // Presentation cursor gliding to the target, like a tour guide's
              // pointer, with a tap ripple when the agent clicks.
              Positioned(
                left: r.center.dx - 18,
                top: r.center.dy - 18,
                child: _Cursor(color: widget.color, tapping: widget.tapping),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.rect, this.color);
  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final cut = RRect.fromRectAndRadius(
      rect.inflate(8),
      const Radius.circular(16),
    );
    // Scrim with a hole punched out around the lit widget.
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRRect(cut),
    );
    // Gentle scrim — enough to lift the target out, not a black wash.
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.18));
    // Soft ring around the lit widget.
    canvas.drawRRect(
      cut,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.rect != rect || old.color != color;
}

/// The tour-guide pointer. A steady dot that glides to the target, plus an
/// expanding ring that fires while [tapping] so a "click" is visible.
class _Cursor extends StatelessWidget {
  const _Cursor({required this.color, required this.tapping});
  final Color color;
  final bool tapping;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Tap ripple: a ring that expands and fades out on each tap.
          TweenAnimationBuilder<double>(
            key: ValueKey(tapping),
            tween: Tween(begin: tapping ? 0.0 : 1.0, end: 1.0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            builder: (context, t, _) {
              if (!tapping) return const SizedBox.shrink();
              return Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: Container(
                  width: 12 + 30 * t,
                  height: 12 + 30 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9), width: 2),
                  ),
                ),
              );
            },
          ),
          // The pointer dot.
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.30),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85), width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
