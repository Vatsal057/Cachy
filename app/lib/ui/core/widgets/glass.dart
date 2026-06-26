/// Glass surface + ambient background primitives.
///
/// [Glass] — reusable BackdropFilter surface (already in use on nav bar).
/// [AmbientBackground] — procedural radial-blob layer; place behind all
/// content so glass surfaces have something rich to blur against.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../brand.dart';

// ────────────────────────────────────────────────────────────────────────────
// Ambient blob background
// ────────────────────────────────────────────────────────────────────────────

/// Procedural gradient-blob background — 5 soft radial blobs in the brand
/// palette. Wrap in a [RepaintBoundary] (done internally) so the foreground
/// never triggers repaints on this layer.
///
/// Place as the first child of a full-screen [Stack] in [HomeShell]:
/// ```dart
/// Stack(children: [
///   const Positioned.fill(child: AmbientBackground()),
///   IndexedStack(...),
/// ])
/// ```
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BlobPainter(isDark: isDark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter({required this.isDark});
  final bool isDark;

  // Light world blobs: rich, vibrant editorial mid-tones
  static const _sageLight  = Color(0xFF6A9C78);
  static const _amberLight = Color(0xFFD49A42);
  static const _clayLight  = Color(0xFFC96E5B);

  // Dark world blobs: deep, moody obsidian jewel tones
  static const _sageDark   = Color(0xFF264535);
  static const _amberDark  = Color(0xFF59401E);
  static const _clayDark   = Color(0xFF4F2620);

  @override
  void paint(Canvas canvas, Size size) {
    final sage  = isDark ? _sageDark  : _sageLight;
    final amber = isDark ? _amberDark : _amberLight;
    final clay  = isDark ? _clayDark  : _clayLight;
    final baseOp = isDark ? 0.40 : 0.46;

    // Radial gradient circles: opaque centre → transparent edge.
    // GPU-only path — no MaskFilter.blur, safe on all Android versions.
    void blob(Offset c, double r, Color col, double opFactor) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          col.withValues(alpha: baseOp * opFactor),
          col.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    final w = size.width;
    final h = size.height;

    blob(Offset(w * 0.08, h * 0.12), 420, sage,  1.00); // top-left
    blob(Offset(w * 0.92, h * 0.08), 380, amber, 0.90); // top-right
    blob(Offset(w * 0.50, h * 0.46), 460, sage,  0.45); // centre
    blob(Offset(w * 0.15, h * 0.82), 360, amber, 0.75); // bottom-left
    blob(Offset(w * 0.88, h * 0.85), 380, clay,  0.85); // bottom-right
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.isDark != isDark;
}

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
