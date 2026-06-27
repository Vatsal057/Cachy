/// A calm editorial flourish — a small accent lozenge with two symmetric
/// tapering tendrils. Cachy's quiet answer to a magazine fleuron: accent-tinted
/// but low-chroma, "an underline, not a spotlight". Hand-painted so it themes
/// per surface, no assets. Used as a section ornament / end-mark across screens.
library;

import 'package:flutter/material.dart';

class Flourish extends StatelessWidget {
  const Flourish({super.key, this.color, this.width = 72, this.height = 18});

  /// Base color; rendered at 0.7 alpha so it stays calm. Defaults to the
  /// scheme's accent.
  final Color? color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = (color ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.7);
    return CustomPaint(size: Size(width, height), painter: _FlourishPainter(c));
  }
}

class _FlourishPainter extends CustomPainter {
  const _FlourishPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    // Center lozenge
    const r = 3.2;
    final diamond = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r, cy)
      ..close();
    canvas.drawPath(diamond, fill);

    // Two symmetric tendrils, each curling up to a terminal dot
    for (final dir in const [1.0, -1.0]) {
      final x0 = cx + dir * (r + 2);
      final x1 = cx + dir * (cx - 3);
      final path = Path()
        ..moveTo(x0, cy)
        ..cubicTo(x0 + dir * 10, cy, x1 - dir * 14, cy - 6, x1 - dir * 4, cy - 6)
        ..cubicTo(x1 + dir * 2, cy - 6, x1, cy - 1, x1 - dir * 4, cy - 1);
      canvas.drawPath(path, stroke);
      canvas.drawCircle(Offset(x1 - dir * 4, cy - 1), 1.3, fill);
    }
  }

  @override
  bool shouldRepaint(_FlourishPainter old) => old.color != color;
}
