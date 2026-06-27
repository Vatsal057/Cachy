/// Hand-drawn spot illustrations — one bespoke motif per screen so each place
/// feels authored, not templated. Line-art in the screen's own ink/accent,
/// calm and low-chroma. Deliberately a little irregular (overshooting corners,
/// open strokes) so they read as drawn by a person, not generated.
///
/// Each widget sizes itself; pass [color] to tint (defaults to a muted ink).
library;

import 'package:flutter/material.dart';

// ── shared pen ──────────────────────────────────────────────────────────────

Paint _pen(Color c, [double w = 1.7]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Color _ink(BuildContext context, Color? c) =>
    c ?? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.55);

class _Spot extends StatelessWidget {
  const _Spot(this.size, this.painter);
  final Size size;
  final CustomPainter painter;
  @override
  Widget build(BuildContext context) => CustomPaint(size: size, painter: painter);
}

// ── Library: a wall of overlapping card faces ────────────────────────────────

class LibrarySpot extends StatelessWidget {
  const LibrarySpot({super.key, this.color, this.size = const Size(108, 78)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _LibraryPainter(_ink(context, color)));
}

class _LibraryPainter extends CustomPainter {
  const _LibraryPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    void card(double dx, double dy, double angle, {bool lines = false}) {
      canvas.save();
      canvas.translate(s.width / 2 + dx, s.height / 2 + dy);
      canvas.rotate(angle);
      final r = RRect.fromRectAndRadius(
          const Rect.fromLTWH(-26, -34, 52, 68), const Radius.circular(7));
      canvas.drawRRect(r, pen);
      if (lines) {
        canvas.drawLine(const Offset(-16, 14), const Offset(16, 14), pen);
        canvas.drawLine(const Offset(-16, 22), const Offset(6, 22), pen);
      }
      canvas.restore();
    }

    card(-22, 2, -0.16); // back
    card(20, -3, 0.13); // right
    card(-1, 0, -0.02, lines: true); // front
  }

  @override
  bool shouldRepaint(_LibraryPainter o) => o.c != c;
}

// ── Collections: nested folders ──────────────────────────────────────────────

class CollectionsSpot extends StatelessWidget {
  const CollectionsSpot({super.key, this.color, this.size = const Size(108, 76)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _CollectionsPainter(_ink(context, color)));
}

class _CollectionsPainter extends CustomPainter {
  const _CollectionsPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    void folder(double dx, double dy, double angle) {
      canvas.save();
      canvas.translate(s.width / 2 + dx, s.height / 2 + dy);
      canvas.rotate(angle);
      final p = Path()
        ..moveTo(-30, -14)
        ..lineTo(-10, -14)
        ..lineTo(-4, -22) // tab
        ..lineTo(26, -22)
        ..lineTo(30, 20)
        ..lineTo(-30, 20)
        ..close();
      canvas.drawPath(p, pen);
      canvas.restore();
    }

    folder(2, -10, 0.04); // back
    folder(-2, 8, -0.05); // front
  }

  @override
  bool shouldRepaint(_CollectionsPainter o) => o.c != c;
}

// ── Actions: a checklist with one ticked box ─────────────────────────────────

class ActionsSpot extends StatelessWidget {
  const ActionsSpot({super.key, this.color, this.size = const Size(112, 70)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _ActionsPainter(_ink(context, color)));
}

class _ActionsPainter extends CustomPainter {
  const _ActionsPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    final cx = s.width / 2 - 28;
    for (var i = 0; i < 3; i++) {
      final y = s.height / 2 - 24 + i * 24.0;
      final box = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 9, y - 9, 18, 18), const Radius.circular(4));
      canvas.drawRRect(box, pen);
      if (i == 0) {
        // tick, drawn with a little overshoot
        final tick = Path()
          ..moveTo(cx - 4, y)
          ..lineTo(cx - 1, y + 5)
          ..lineTo(cx + 6, y - 6);
        canvas.drawPath(tick, pen);
      }
      // item line beside the box
      final lineEnd = i == 1 ? 30.0 : 44.0;
      canvas.drawLine(Offset(cx + 18, y), Offset(cx + 18 + lineEnd, y), pen);
    }
  }

  @override
  bool shouldRepaint(_ActionsPainter o) => o.c != c;
}

// ── Chat: two speech bubbles ─────────────────────────────────────────────────

class ChatSpot extends StatelessWidget {
  const ChatSpot({super.key, this.color, this.size = const Size(112, 78)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _ChatPainter(_ink(context, color)));
}

class _ChatPainter extends CustomPainter {
  const _ChatPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    final dot = Paint()..color = c;
    // back bubble
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(s.width / 2 - 6, s.height / 2 - 34, 48, 30),
          const Radius.circular(12)),
      pen,
    );
    // front bubble with a tail
    final bx = s.width / 2 - 44;
    final by = s.height / 2 - 8;
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, 56, 34), const Radius.circular(13));
    canvas.drawRRect(body, pen);
    final tail = Path()
      ..moveTo(bx + 14, by + 34)
      ..lineTo(bx + 8, by + 44)
      ..lineTo(bx + 24, by + 34);
    canvas.drawPath(tail, pen);
    // three dots
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(bx + 16 + i * 12.0, by + 17), 2.1, dot);
    }
  }

  @override
  bool shouldRepaint(_ChatPainter o) => o.c != c;
}

// ── Graph: connected nodes ───────────────────────────────────────────────────

class GraphSpot extends StatelessWidget {
  const GraphSpot({super.key, this.color, this.size = const Size(112, 80)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _GraphPainter(_ink(context, color)));
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c, 1.5);
    final fill = Paint()..color = c.withValues(alpha: 0.18);
    final cx = s.width / 2;
    final cy = s.height / 2;
    // node positions: a hub plus four satellites, hand-placed (not symmetric)
    final hub = Offset(cx - 2, cy + 2);
    final nodes = <Offset>[
      Offset(cx - 36, cy - 22),
      Offset(cx + 30, cy - 26),
      Offset(cx + 40, cy + 16),
      Offset(cx - 28, cy + 24),
    ];
    // edges from hub, plus one rim link
    for (final n in nodes) {
      canvas.drawLine(hub, n, pen);
    }
    canvas.drawLine(nodes[1], nodes[2], pen);
    // draw nodes (filled disc + ring) so they read as beads
    void bead(Offset o, double r) {
      canvas.drawCircle(o, r, fill);
      canvas.drawCircle(o, r, pen);
    }
    bead(hub, 7);
    bead(nodes[0], 5);
    bead(nodes[1], 5.5);
    bead(nodes[2], 4.5);
    bead(nodes[3], 5);
  }

  @override
  bool shouldRepaint(_GraphPainter o) => o.c != c;
}

// ── Structure: a card resolved into labelled blocks ──────────────────────────

class StructureSpot extends StatelessWidget {
  const StructureSpot({super.key, this.color, this.size = const Size(108, 80)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _StructurePainter(_ink(context, color)));
}

class _StructurePainter extends CustomPainter {
  const _StructurePainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    final fill = Paint()..color = c.withValues(alpha: 0.18);
    final cx = s.width / 2;
    final cy = s.height / 2;
    // card outline
    final card = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 64, height: 72),
        const Radius.circular(8));
    canvas.drawRRect(card, pen);
    // an eyebrow chip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 24, cy - 28, 22, 8), const Radius.circular(4)),
      fill,
    );
    // block rows: a bullet + line, three of them
    for (var i = 0; i < 3; i++) {
      final y = cy - 8 + i * 14.0;
      canvas.drawCircle(Offset(cx - 19, y), 2.4, Paint()..color = c);
      final len = i == 2 ? 22.0 : 34.0;
      canvas.drawLine(Offset(cx - 12, y), Offset(cx - 12 + len, y), pen);
    }
  }

  @override
  bool shouldRepaint(_StructurePainter o) => o.c != c;
}

// ── Capture: a link dropping into a card ─────────────────────────────────────

class CaptureSpot extends StatelessWidget {
  const CaptureSpot({super.key, this.color, this.size = const Size(116, 70)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _CapturePainter(_ink(context, color)));
}

class _CapturePainter extends CustomPainter {
  const _CapturePainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    final cx = s.width / 2;
    final cy = s.height / 2;
    // a card
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 4, cy - 18, 52, 44), const Radius.circular(8)),
      pen,
    );
    canvas.drawLine(Offset(cx + 6, cy + 4), Offset(cx + 38, cy + 4), pen);
    canvas.drawLine(Offset(cx + 6, cy + 14), Offset(cx + 26, cy + 14), pen);
    // two chain links arcing in from the left
    for (var i = 0; i < 2; i++) {
      final ox = cx - 40 + i * 18.0;
      final oy = cy - 14 + i * 12.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(ox, oy, 22, 12), const Radius.circular(6)),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_CapturePainter o) => o.c != c;
}

// ── Catalog: a book and a film frame ─────────────────────────────────────────

class CatalogSpot extends StatelessWidget {
  const CatalogSpot({super.key, this.color, this.size = const Size(112, 74)});
  final Color? color;
  final Size size;
  @override
  Widget build(BuildContext context) =>
      _Spot(size, _CatalogPainter(_ink(context, color)));
}

class _CatalogPainter extends CustomPainter {
  const _CatalogPainter(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final pen = _pen(c);
    final cy = s.height / 2;
    // book, left, leaning
    canvas.save();
    canvas.translate(s.width / 2 - 30, cy);
    canvas.rotate(-0.1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(-18, -26, 36, 52), const Radius.circular(4)),
      pen,
    );
    canvas.drawLine(const Offset(-10, -26), const Offset(-10, 26), pen); // spine
    canvas.restore();
    // film frame, right
    canvas.save();
    canvas.translate(s.width / 2 + 26, cy + 2);
    canvas.rotate(0.08);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(-22, -20, 44, 40), const Radius.circular(4)),
      pen,
    );
    for (final x in const [-22.0, 22.0]) {
      for (var i = 0; i < 3; i++) {
        final y = -14 + i * 12.0;
        canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), pen); // sprocket holes
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CatalogPainter o) => o.c != c;
}
