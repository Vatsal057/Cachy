import 'package:flutter/material.dart';

import '../theme.dart';

/// Centers and caps single-column content on wide viewports.
///
/// On desktop-width viewports (`>= Insets.desktop`), the [child] is
/// horizontally centered and constrained to at most [maxWidth], giving
/// long-form/single-column screens a comfortable reading column with equal
/// left/right margins. On narrower (mobile) viewports it is a no-op: the
/// [child] renders full-width and left-aligned, so the mobile layout is
/// unchanged.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = Insets.readingColumn,
    this.padding = EdgeInsets.zero,
  });

  /// The content to lay out.
  final Widget child;

  /// Maximum content width applied on wide viewports.
  final double maxWidth;

  /// Padding applied around the [child] in both layout modes.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Insets.desktop) {
          // Mobile: full-width, left-aligned — unchanged behavior.
          return Padding(padding: padding, child: child);
        }
        // Wide viewport: cap width and center.
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}
