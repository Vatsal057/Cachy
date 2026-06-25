/// Knowledge graph (Obsidian-style): an interactive, force-directed map of the
/// library. Each card is a node; an edge means two cards are similar (semantic
/// embedding + shared tags, computed server-side). Similar notes pull together
/// into clusters; notes with nothing similar float alone. Pan to move, pinch to
/// zoom, tap a node to open that card.
///
/// Rendered with a hand-rolled Fruchterman-Reingold layout + CustomPainter — no
/// graph package, full control (free-first).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/graph.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../reader/views/reader_screen.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  GraphData? _data;
  Object? _error;
  bool _loading = true;

  // Layout state (world coordinates, centred on the origin).
  final Map<String, Offset> _pos = {};
  final Map<String, List<String>> _adj = {};
  double _temp = 0; // simulated-annealing temperature; 0 = settled

  // View transform.
  Offset _pan = Offset.zero;
  double _zoom = 1.0;
  Offset _panStart = Offset.zero;
  double _baseZoom = 1.0;
  String? _selected;
  String? _draggedNode;

  static const double _k = 78; // ideal edge length

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<CardRepository>().graph();
      _seedLayout(data);
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _seedLayout(GraphData data) {
    _pos.clear();
    _adj.clear();
    final rng = math.Random(7);
    final n = data.nodes.length;
    for (var i = 0; i < n; i++) {
      // Seed on a ring + jitter so the sim has a non-degenerate start.
      final a = (i / math.max(1, n)) * 2 * math.pi;
      final r = 40 + rng.nextDouble() * 120;
      _pos[data.nodes[i].id] =
          Offset(math.cos(a) * r, math.sin(a) * r) +
              Offset(rng.nextDouble() * 8 - 4, rng.nextDouble() * 8 - 4);
      _adj[data.nodes[i].id] = [];
    }
    for (final e in data.edges) {
      _adj[e.source]?.add(e.target);
      _adj[e.target]?.add(e.source);
    }
    _temp = 90;
    if (!_ticker.isActive && n > 0) _ticker.start();
  }

  void _onTick(Duration _) {
    if (_data == null || _pos.isEmpty) return;
    _step(_data!);
    if (_temp < 0.6) _ticker.stop();
    if (mounted) setState(() {});
    final data = _data;
    if (data == null || _temp < 0.5) {
      if (_ticker.isTicking) _ticker.stop();
      return;
    }
    _step(data);
    setState(() {});
  }

  /// One Fruchterman-Reingold iteration: nodes repel, edges attract (scaled by
  /// similarity weight), gentle gravity keeps the whole thing centred, and a
  /// cooling temperature caps per-step movement so it settles.
  void _step(GraphData data) {
    final ids = data.nodes.map((n) => n.id).toList();
    final disp = <String, Offset>{for (final id in ids) id: Offset.zero};

    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final pa = _pos[ids[i]];
        final pb = _pos[ids[j]];
        if (pa == null || pb == null) continue;
        var delta = pa - pb;
        var d = delta.distance;
        if (d < 0.01) {
          delta = const Offset(0.5, 0.3);
          d = delta.distance;
        }
        final force = (_k * _k) / d;
        final push = delta / d * force;
        disp[ids[i]] = disp[ids[i]]! + push;
        disp[ids[j]] = disp[ids[j]]! - push;
      }
    }

    for (final e in data.edges) {
      final pa = _pos[e.source];
      final pb = _pos[e.target];
      if (pa == null || pb == null) continue;
      var delta = pa - pb;
      var d = delta.distance;
      if (d < 0.01) d = 0.01;
      final force = (d * d) / _k * (0.4 + e.weight);
      final pull = delta / d * force;
      disp[e.source] = disp[e.source]! - pull;
      disp[e.target] = disp[e.target]! + pull;
    }

    for (final n in data.nodes) {
      if (n.id == _draggedNode) continue;
      var dd = disp[n.id]! - _pos[n.id]! * 0.03;
      final len = dd.distance;
      if (len > 0) dd = dd / len * math.min(len, _temp);
      _pos[n.id] = _pos[n.id]! + dd;
    }
    _temp = math.max(0.5, _temp * 0.96);
  }

  // ------------------------------------------------------------------------ //
  // Gestures
  // ------------------------------------------------------------------------ //

  void _onScaleStart(ScaleStartDetails d, Size size) {
    _baseZoom = _zoom;
    _panStart = _pan;
    final hit = _hitTest(d.localFocalPoint, size);
    if (hit != null && d.pointerCount == 1) {
      _draggedNode = hit;
      _selected = hit;
      if (!_ticker.isTicking) _ticker.start();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_draggedNode != null && d.pointerCount == 1) {
      final center = Offset(size.width / 2, size.height / 2);
      final world = (d.localFocalPoint - center - _pan) / _zoom;
      _pos[_draggedNode!] = world;
      _temp = math.max(_temp, 4.0);
      setState(() {});
      return;
    }
    if (d.pointerCount > 1 || _draggedNode == null) {
      setState(() {
        _zoom = (_baseZoom * d.scale).clamp(0.25, 3.5);
        _pan = _panStart + d.focalPointDelta;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _draggedNode = null;
  }

  void _onTapUp(TapUpDetails d, Size size) {
    final hit = _hitTest(d.localPosition, size);
    if (hit == null) {
      setState(() => _selected = null);
      return;
    }
    setState(() => _selected = hit);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(cardId: hit)),
    );
  }

  String? _hitTest(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final world = (local - center - _pan) / _zoom;
    String? best;
    double bestD = double.infinity;
    for (final entry in _pos.entries) {
      final d = (entry.value - world).distance;
      if (d < 30 && d < bestD) {
        bestD = d;
        best = entry.key;
      }
    }
    return best;
  }

  // ------------------------------------------------------------------------ //

  @override
  Widget build(BuildContext context) {
    final content = _body();
    if (!widget.showAppBar) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Graph'),
        actions: [
          IconButton(
            tooltip: 'Re-layout',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.violet));
    }
    if (_error != null) {
      return ErrorState(
        title: "Couldn't load the graph",
        message: 'Check your connection and try again.',
        onRetry: _load,
      );
    }
    final data = _data;
    if (data == null || data.isEmpty) {
      return const EmptyState(
        icon: Icons.hub_outlined,
        title: 'Nothing to connect yet',
        message: "Save a few cards and we'll link the ones that belong together.",
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onScaleStart: (d) => _onScaleStart(d, size),
          onScaleUpdate: (d) => _onScaleUpdate(d, size),
          onScaleEnd: _onScaleEnd,
          onTapUp: (d) => _onTapUp(d, size),
          child: CustomPaint(
            size: size,
            painter: _GraphPainter(
              data: data,
              positions: _pos,
              pan: _pan,
              zoom: _zoom,
              selected: _selected,
              adjacency: _adj,
              theme: Theme.of(context),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.data,
    required this.positions,
    required this.pan,
    required this.zoom,
    required this.selected,
    required this.adjacency,
    required this.theme,
  });

  final GraphData data;
  final Map<String, Offset> positions;
  final Offset pan;
  final double zoom;
  final String? selected;
  final Map<String, List<String>> adjacency;
  final ThemeData theme;

  Offset _screen(Offset world, Size size) =>
      Offset(size.width / 2, size.height / 2) + pan + world * zoom;

  bool _isNeighbour(String id) =>
      selected != null &&
      (id == selected || (adjacency[selected]?.contains(id) ?? false));

  @override
  void paint(Canvas canvas, Size size) {
    final scheme = theme.colorScheme;

    // Edges.
    for (final e in data.edges) {
      final a = positions[e.source];
      final b = positions[e.target];
      if (a == null || b == null) continue;
      final highlight = selected != null &&
          (e.source == selected || e.target == selected);
      final base = highlight ? scheme.primary : scheme.outlineVariant;
      final paint = Paint()
        ..color = base.withValues(
            alpha: highlight ? 0.9 : (0.18 + 0.5 * e.weight).clamp(0.0, 0.7))
        ..strokeWidth = (highlight ? 2.2 : 0.6 + e.weight * 1.6) * zoom.clamp(0.5, 1.5)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(_screen(a, size), _screen(b, size), paint);
    }

    // Nodes.
    final dim = selected != null;
    for (final node in data.nodes) {
      final p = positions[node.id];
      if (p == null) continue;
      final s = _screen(p, size);
      final accent =
          ContentAccent.of(ContentType.fromWire(node.contentType)).color;
      final r = (8.0 + node.degree * 1.8).clamp(8.0, 22.0) * zoom.clamp(0.5, 1.6);
      final faded = dim && !_isNeighbour(node.id);

      // Halo for the selected node.
      if (node.id == selected) {
        canvas.drawCircle(
          s,
          r + 6,
          Paint()..color = accent.withValues(alpha: 0.25),
        );
      }
      canvas.drawCircle(
        s,
        r,
        Paint()..color = accent.withValues(alpha: faded ? 0.25 : 1.0),
      );
      canvas.drawCircle(
        s,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = scheme.surface.withValues(alpha: faded ? 0.3 : 0.9),
      );

      // Label (only when not too zoomed-out, to avoid clutter).
      if (zoom > 0.65 && !faded) {
        final tp = TextPainter(
          text: TextSpan(
            text: node.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.85),
              height: 1.1,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: 110);
        tp.paint(canvas, Offset(s.dx - tp.width / 2, s.dy + r + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
