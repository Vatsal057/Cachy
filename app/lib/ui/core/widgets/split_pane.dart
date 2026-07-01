import 'package:flutter/material.dart';

/// Resolves the list-panel width for a split pane given the [availableWidth]
/// and the requested [fraction] of that width.
///
/// The result is clamped to `[280.0, availableWidth * 0.5]`, enforcing both a
/// pixel floor (so the list never collapses too far) and a ceiling of half the
/// available width (so the list never dominates the reader). Exposed as a pure
/// top-level function so the width math is unit/property testable in isolation.
double resolveSplitListWidth(double availableWidth, double fraction) =>
    (availableWidth * fraction).clamp(280.0, availableWidth * 0.5);

/// A master-detail layout with a draggable divider between a [list] panel and
/// a [detail] panel.
///
/// The list panel occupies [fraction] of the available width (clamped by
/// [resolveSplitListWidth]); the [detail] panel fills the remainder. Dragging
/// the divider converts the new list width back into a fraction and reports it
/// via [onFractionChanged]; the parent is responsible for clamping/persisting
/// the committed value.
class SplitPane extends StatelessWidget {
  const SplitPane({
    super.key,
    required this.list,
    required this.detail,
    required this.fraction,
    required this.onFractionChanged,
    this.dividerColor,
  });

  /// The list (master) panel, shown on the leading side.
  final Widget list;

  /// The detail (reader) panel, shown on the trailing side.
  final Widget detail;

  /// The list-panel width as a fraction of the available width.
  final double fraction;

  /// Called with the new fraction as the divider is dragged.
  final ValueChanged<double> onFractionChanged;

  /// Color of the 1px divider line. Falls back to the theme's
  /// `outlineVariant` when null.
  final Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    final lineColor =
        dividerColor ?? Theme.of(context).colorScheme.outlineVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final listWidth = resolveSplitListWidth(availableWidth, fraction);

        return Row(
          children: [
            SizedBox(width: listWidth, child: list),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  // Compute the new list width from the drag delta, clamp it
                  // locally to keep the drag sane, then convert back to a
                  // fraction for the parent to clamp/persist.
                  final newWidth = (listWidth + details.delta.dx)
                      .clamp(280.0, availableWidth * 0.5);
                  final newFraction = availableWidth > 0
                      ? newWidth / availableWidth
                      : fraction;
                  onFractionChanged(newFraction);
                },
                child: SizedBox(
                  width: 8,
                  child: Center(
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: lineColor,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}
