/// Reusable frosted-glass surface. One widget every glass surface uses —
/// no hand-rolled BackdropFilter per screen.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../brand.dart';

/// A frosted-glass container: BackdropFilter blur + translucent fill +
/// optional 1-px hairline border.
///
/// Usage:
///   Glass(child: ...) — no radius (full-width bars, overlays)
///   Glass.card(child: ...) — rounded card (radius 18)
///   Glass.rounded(radius: 12, child: ...) — custom radius
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding,
    this.blurOverride,
    this.fillOverride,
    this.showBorder = true,
  });

  const Glass.card({
    super.key,
    required this.child,
    this.padding,
    this.blurOverride,
    this.fillOverride,
    this.showBorder = true,
  }) : borderRadius = const BorderRadius.all(Radius.circular(18));

  Glass.rounded({
    super.key,
    required this.child,
    required double radius,
    this.padding,
    this.blurOverride,
    this.fillOverride,
    this.showBorder = true,
  }) : borderRadius = BorderRadius.all(Radius.circular(radius));

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Override blur sigma (defaults to [Brand.glassBlurSigma] / dark variant).
  final double? blurOverride;

  /// Override fill color (defaults to [Brand.glassFill]).
  final Color? fillOverride;

  /// Show the 1-px hairline border (default true).
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final isDark = b == Brightness.dark;
    final sigma = blurOverride ??
        (isDark ? Brand.glassBlurSigmaDark : Brand.glassBlurSigma);
    final fill = fillOverride ?? Brand.glassFill(b);
    final border = Brand.glassBorder(b);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: showBorder
                ? Border.all(color: border, width: 0.8)
                : null,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
