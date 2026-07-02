/// The "Present" mode surface: a Siri-like glowing glyph that floats in a
/// corner while the agent drives the app. It breathes in the agent's current
/// phase colour, shows a live caption of what's being said/done, and — when
/// tapped — expands into a panel where you can hand the agent a question or a
/// task.
///
/// The whole surface is designed to read as *one* calm element: the orb, its
/// caption, and the panel share the app's cream/charcoal palette (phase is a
/// gentle tint, never a jarring hue-swap), glide in on launch, and cross-fade
/// between states so nothing ever pops in abruptly.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import 'presenter_controller.dart';

class PresenterOverlay extends StatefulWidget {
  const PresenterOverlay({super.key, required this.controller});
  final PresenterController controller;

  @override
  State<PresenterOverlay> createState() => _PresenterOverlayState();
}

class _PresenterOverlayState extends State<PresenterOverlay>
    with TickerProviderStateMixin {
  // Slow breathing halo.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  // Continuous rotation for the orb's inner sheen — keeps it feeling alive.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  // One-shot entrance: the surface glides up and fades in when Present starts.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _expanded = false;

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    _intro.dispose();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  void _submit() {
    final q = _field.text.trim();
    if (q.isEmpty) return;
    _field.clear();
    widget.controller.ask(q);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final desktop = width >= Insets.desktop;
    // Clear the floating pill nav on mobile; the side rail leaves the corner free.
    final bottom = bottomInset + (desktop ? 24 : 96);
    // Give the bubble/panel room without crowding the edge on phones.
    final maxBubble = math.min(desktop ? 360.0 : width - 88, 360.0);

    return Positioned(
      right: desktop ? 24 : 16,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.controller, _intro]),
        builder: (context, _) {
          final intro = Curves.easeOutCubic.transform(_intro.value);
          return Opacity(
            opacity: intro,
            child: Transform.translate(
              offset: Offset(0, (1 - intro) * 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: Motion.medium,
                    curve: Motion.curve,
                    alignment: Alignment.bottomRight,
                    child: _buildBubble(maxBubble),
                  ),
                  const SizedBox(height: 12),
                  _Glyph(
                    phase: widget.controller.phase,
                    pulse: _pulse,
                    spin: _spin,
                    onTap: _toggle,
                    expanded: _expanded,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBubble(double maxWidth) {
    final controller = widget.controller;
    final Widget child;
    if (_expanded) {
      child = _Panel(
        key: const ValueKey('panel'),
        controller: controller,
        field: _field,
        focus: _focus,
        maxWidth: maxWidth,
        onSubmit: _submit,
        onEnd: controller.stop,
      );
    } else if (controller.caption.isNotEmpty) {
      child = _CaptionBubble(
        key: const ValueKey('caption'),
        text: controller.caption,
        spokenEnd: controller.captionSpokenEnd,
        phase: controller.phase,
        maxWidth: maxWidth,
        onTap: _toggle,
      );
    } else {
      child = const SizedBox.shrink(key: ValueKey('empty'));
    }

    return AnimatedSwitcher(
      duration: Motion.medium,
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ── The glowing orb ─────────────────────────────────────────────────────── //

class _Glyph extends StatefulWidget {
  const _Glyph({
    required this.phase,
    required this.pulse,
    required this.spin,
    required this.onTap,
    required this.expanded,
  });

  final PresenterPhase phase;
  final Animation<double> pulse;
  final Animation<double> spin;
  final VoidCallback onTap;
  final bool expanded;

  @override
  State<_Glyph> createState() => _GlyphState();
}

class _GlyphState extends State<_Glyph> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = _phaseColor(context, widget.phase);
    final busy = widget.phase == PresenterPhase.speaking ||
        widget.phase == PresenterPhase.thinking ||
        widget.phase == PresenterPhase.acting;

    return Semantics(
      button: true,
      label: 'Presenter agent — tap to ask or hand it a task',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1.0,
            duration: Motion.fast,
            curve: Motion.curve,
            child: AnimatedBuilder(
              animation: Listenable.merge([widget.pulse, widget.spin]),
              builder: (context, _) {
                // A soft double-halo that breathes; wider when the agent is busy.
                final t = widget.pulse.value;
                final haloBlur = (busy ? 26.0 : 16.0) + t * 12;
                final haloSpread = (busy ? 6.0 : 2.0) + t * 5;
                return SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The core orb + breathing glow.
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color.lerp(color, Colors.white, 0.45)!,
                              color,
                              Color.lerp(color, Colors.black, 0.28)!,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                            center: const Alignment(-0.3, -0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.50),
                              blurRadius: haloBlur,
                              spreadRadius: haloSpread,
                            ),
                            BoxShadow(
                              color: color.withValues(alpha: 0.20),
                              blurRadius: haloBlur * 2,
                              spreadRadius: haloSpread * 1.6,
                            ),
                          ],
                        ),
                      ),
                      // A slow rotating sheen so the orb reads as alive, not a
                      // static dot. Only visible while the agent is working.
                      ClipOval(
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: Transform.rotate(
                            angle: widget.spin.value * 2 * math.pi,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: SweepGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.0),
                                    Colors.white
                                        .withValues(alpha: busy ? 0.35 : 0.14),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.35, 0.5, 0.65],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Phase glyph, cross-fading as the phase changes.
                      AnimatedSwitcher(
                        duration: Motion.fast,
                        child: Icon(
                          widget.expanded
                              ? PhosphorIconsRegular.caretDown
                              : _phaseIcon(widget.phase),
                          key: ValueKey(
                              widget.expanded ? 'down' : widget.phase),
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Collapsed caption bubble ────────────────────────────────────────────── //

class _CaptionBubble extends StatelessWidget {
  const _CaptionBubble({
    super.key,
    required this.text,
    required this.spokenEnd,
    required this.phase,
    required this.maxWidth,
    required this.onTap,
  });

  final String text;
  final int spokenEnd;
  final PresenterPhase phase;
  final double maxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _phaseColor(context, phase);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.80),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: tint.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 10),
                      child: _LiveDot(color: tint, active: _busy(phase)),
                    ),
                    Flexible(
                      child: _KaraokeText(
                        text: text,
                        spokenEnd: spokenEnd,
                        tint: tint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The caption text with a karaoke-style highlight. Only the words the agent
/// has spoken so far are shown — the newest one tinted, the rest in full ink —
/// and the remainder stays hidden until it's read. So the bubble starts small
/// and grows line-by-line as the sentence is spoken, then shrinks back for the
/// next line: never larger than what's currently on screen.
class _KaraokeText extends StatelessWidget {
  const _KaraokeText({
    required this.text,
    required this.spokenEnd,
    required this.tint,
  });

  final String text;
  final int spokenEnd;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    final end = spokenEnd.clamp(0, text.length);
    final shown = text.substring(0, end);
    // Split the revealed text into the already-settled part and the word being
    // spoken right now, so the leading edge of the highlight glows in the tint.
    final trimmed = shown.trimRight();
    final wordStart = trimmed.lastIndexOf(' ') + 1;
    final settled = shown.substring(0, wordStart);
    final current = shown.substring(wordStart);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: settled,
            style: base?.copyWith(color: theme.colorScheme.onSurface),
          ),
          TextSpan(
            text: current,
            style: base?.copyWith(
              color: Color.lerp(theme.colorScheme.onSurface, tint, 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small pulsing dot that signals the agent is live/working — the visual
/// anchor that ties the caption back to the orb.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = widget.active ? _c.value : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.55 + 0.45 * t),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.5 * t),
                blurRadius: 6 * t,
                spreadRadius: 1 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Expanded input panel ────────────────────────────────────────────────── //

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.controller,
    required this.field,
    required this.focus,
    required this.maxWidth,
    required this.onSubmit,
    required this.onEnd,
  });

  final PresenterController controller;
  final TextEditingController field;
  final FocusNode focus;
  final double maxWidth;
  final VoidCallback onSubmit;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = _phaseColor(context, controller.phase);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: math.max(maxWidth, 300)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: tint.withValues(alpha: 0.32)),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _LiveDot(color: tint, active: _busy(controller.phase)),
                    const SizedBox(width: 8),
                    Text(
                      _phaseLabel(controller.phase),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: tint,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onEnd,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(PhosphorIconsRegular.stopCircle, size: 18),
                      label: const Text('End'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _KaraokeText(
                  text: controller.caption.isEmpty ? '…' : controller.caption,
                  spokenEnd: controller.caption.isEmpty
                      ? 1
                      : controller.captionSpokenEnd,
                  tint: tint,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: field,
                  focusNode: focus,
                  onSubmitted: (_) => onSubmit(),
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Ask, or hand me a task…',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          BorderSide(color: tint.withValues(alpha: 0.6)),
                    ),
                    suffixIcon: IconButton(
                      color: tint,
                      icon: const Icon(PhosphorIconsRegular.paperPlaneRight),
                      onPressed: onSubmit,
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

// ── Phase → colour / icon / label ───────────────────────────────────────── //

bool _busy(PresenterPhase p) =>
    p == PresenterPhase.speaking ||
    p == PresenterPhase.thinking ||
    p == PresenterPhase.acting;

/// Phase tints are kept close to the app's calm palette — the accent is the
/// base and each phase is a gentle, desaturated shift off it, so state reads
/// clearly without the jarring green/orange/blue that fought the cream theme.
Color _phaseColor(BuildContext context, PresenterPhase phase) {
  final scheme = Theme.of(context).colorScheme;
  final accent = scheme.primary;
  return switch (phase) {
    PresenterPhase.speaking => accent,
    PresenterPhase.thinking =>
      Color.lerp(accent, const Color(0xFFD9A441), 0.55)!, // warm amber lean
    PresenterPhase.acting =>
      Color.lerp(accent, const Color(0xFF5B8DCF), 0.45)!, // cool blue lean
    PresenterPhase.idle => Color.lerp(accent, scheme.onSurfaceVariant, 0.25)!,
    PresenterPhase.done => scheme.onSurfaceVariant,
  };
}

IconData _phaseIcon(PresenterPhase phase) => switch (phase) {
      PresenterPhase.speaking => PhosphorIconsRegular.waveform,
      PresenterPhase.thinking => PhosphorIconsRegular.sparkle,
      PresenterPhase.acting => PhosphorIconsRegular.cursorClick,
      PresenterPhase.idle => PhosphorIconsRegular.microphone,
      PresenterPhase.done => PhosphorIconsRegular.check,
    };

String _phaseLabel(PresenterPhase p) => switch (p) {
      PresenterPhase.speaking => 'PRESENTING',
      PresenterPhase.thinking => 'THINKING',
      PresenterPhase.acting => 'DOING IT LIVE',
      PresenterPhase.idle => 'READY — ASK ME',
      PresenterPhase.done => 'DONE',
    };
