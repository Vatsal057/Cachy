import 'package:flutter/material.dart';

/// Reusable hover wrapper to avoid repeating `MouseRegion` + `setState`
/// boilerplate across nav destinations and ad-hoc icon buttons.
///
/// Exposes a single `hovered` flag to its [builder]; consumers apply their own
/// `AnimatedContainer`/`AnimatedOpacity` for the transition. The hover state is
/// cleared as soon as the pointer exits, so no stale highlight lingers.
class Hoverable extends StatefulWidget {
  const Hoverable({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  /// Builds the child given the current [hovered] state.
  final Widget Function(BuildContext context, bool hovered) builder;

  /// Cursor shown while the pointer is over the region.
  final MouseCursor cursor;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: widget.builder(context, _hovered),
    );
  }
}
