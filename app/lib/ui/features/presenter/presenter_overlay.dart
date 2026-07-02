/// The "Present" mode surface: a Siri-like glowing glyph that floats in a
/// corner while the agent drives the app. It pulses in the agent's current phase
/// colour, shows a live caption of what's being said/done, and — when tapped —
/// expands into a panel where you can hand the agent a question or a task.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'presenter_controller.dart';

class PresenterOverlay extends StatefulWidget {
  const PresenterOverlay({super.key, required this.controller});
  final PresenterController controller;

  @override
  State<PresenterOverlay> createState() => _PresenterOverlayState();
}

class _PresenterOverlayState extends State<PresenterOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  final _field = TextEditingController();
  final _focus = FocusNode();
  bool _expanded = false;

  @override
  void dispose() {
    _pulse.dispose();
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
    // Clear the floating pill nav on mobile; the side rail leaves the corner free.
    final bottom = bottomInset + (width >= Insets.desktop ? 24 : 92);

    return Positioned(
      right: 16,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_expanded)
                _Panel(
                  controller: widget.controller,
                  field: _field,
                  focus: _focus,
                  onSubmit: _submit,
                  onEnd: () => widget.controller.stop(),
                )
              else if (widget.controller.caption.isNotEmpty)
                _CaptionBubble(text: widget.controller.caption),
              const SizedBox(height: 12),
              _Glyph(
                phase: widget.controller.phase,
                pulse: _pulse,
                onTap: _toggle,
                expanded: _expanded,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── The glowing orb ─────────────────────────────────────────────────────── //

class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.phase,
    required this.pulse,
    required this.onTap,
    required this.expanded,
  });

  final PresenterPhase phase;
  final Animation<double> pulse;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final color = _phaseColor(context, phase);
    final busy = phase == PresenterPhase.speaking ||
        phase == PresenterPhase.thinking ||
        phase == PresenterPhase.acting;

    return Semantics(
      button: true,
      label: 'Presenter agent — tap to ask or hand it a task',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              // A soft double-halo that breathes; wider when the agent is busy.
              final t = pulse.value;
              final haloBlur = (busy ? 30.0 : 20.0) + t * 14;
              final haloSpread = (busy ? 8.0 : 4.0) + t * 6;
              return Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.lerp(color, Colors.white, 0.35)!,
                      color,
                      Color.lerp(color, Colors.black, 0.25)!,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                    center: const Alignment(-0.3, -0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: haloBlur,
                      spreadRadius: haloSpread,
                    ),
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: haloBlur * 2,
                      spreadRadius: haloSpread * 1.6,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    expanded ? Icons.keyboard_arrow_down_rounded : _phaseIcon(phase),
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Collapsed caption bubble ────────────────────────────────────────────── //

class _CaptionBubble extends StatelessWidget {
  const _CaptionBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Expanded input panel ────────────────────────────────────────────────── //

class _Panel extends StatelessWidget {
  const _Panel({
    required this.controller,
    required this.field,
    required this.focus,
    required this.onSubmit,
    required this.onEnd,
  });

  final PresenterController controller;
  final TextEditingController field;
  final FocusNode focus;
  final VoidCallback onSubmit;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _phaseLabel(controller.phase),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onEnd,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('End'),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  controller.caption.isEmpty ? '…' : controller.caption,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send_rounded),
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

Color _phaseColor(BuildContext context, PresenterPhase phase) {
  final scheme = Theme.of(context).colorScheme;
  return switch (phase) {
    PresenterPhase.speaking => const Color(0xFF3DDC97),
    PresenterPhase.thinking => const Color(0xFFF5A623),
    PresenterPhase.acting => const Color(0xFF4DA8FF),
    PresenterPhase.idle => scheme.primary,
    PresenterPhase.done => Colors.grey,
  };
}

IconData _phaseIcon(PresenterPhase phase) => switch (phase) {
      PresenterPhase.speaking => Icons.graphic_eq_rounded,
      PresenterPhase.thinking => Icons.auto_awesome_rounded,
      PresenterPhase.acting => Icons.touch_app_rounded,
      PresenterPhase.idle => Icons.mic_none_rounded,
      PresenterPhase.done => Icons.check_rounded,
    };

String _phaseLabel(PresenterPhase p) => switch (p) {
      PresenterPhase.speaking => 'PRESENTING',
      PresenterPhase.thinking => 'THINKING',
      PresenterPhase.acting => 'DOING IT LIVE',
      PresenterPhase.idle => 'READY — ASK ME',
      PresenterPhase.done => 'DONE',
    };
