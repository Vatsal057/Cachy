/// Obsidian-style knowledge graph: a live force-directed physics simulation that
/// runs on every open, letting nodes wiggle and settle into emergent clusters.
///
/// Four configurable forces:
///   1. **Repulsion** — every node pushes every other node away (Coulomb's law).
///   2. **Link/spring** — connected nodes pull together (Hooke's law).
///   3. **Center** — gentle gravity toward the origin keeps the graph compact.
///   4. **Link distance** — ideal spring rest length.
///
/// Drag pins a node while physics recalculates around it (rubber-band effect).
/// Two node types (card = circle, catalog = rounded square), three edge styles,
/// cluster filter chips, and a two-tap preview sheet.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/concept.dart';
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/graph.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../concepts/views/concept_detail_screen.dart';
import '../../reader/views/reader_screen.dart';

// ========================================================================== //
// Physics tuning defaults
// ========================================================================== //

class _PhysicsConfig {
  double repelForce;
  double linkForce;
  double centerForce;
  double linkDistance;

  _PhysicsConfig({
    this.repelForce = 1.6,
    this.linkForce = 1.3,
    this.centerForce = 0.025,
    this.linkDistance = 110,
  });
}

// ========================================================================== //
// Main screen
// ========================================================================== //

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

  // Physics state (world coordinates).
  final Map<String, Offset> _pos = {};
  final Map<String, Offset> _vel = {};
  final Map<String, List<String>> _adj = {};
  final Map<String, double> _edgeWeights = {};

  // Star layout anchors — the ideal position each node should occupy.
  final Map<String, Offset> _starPos = {};
  final Map<String, Offset> _starRel = {};
  final Map<String, String> _hubFor = {};
  static const double _starRadius = 125.0;
  // Loose strength so the spring-back feels natural, not snappy.
  static const double _starRestoreStrength = 0.04;
  double _temperature = 0;

  // View transform.
  Offset _pan = Offset.zero;
  double _zoom = 0.72;
  double _baseZoom = 0.72;
  String? _selected;
  String? _draggedNode;

  // Cluster filter.
  int? _activeCluster;

  // Physics config.
  final _physics = _PhysicsConfig();

  // Local graph mode.
  bool _localMode = false;
  int _localDepth = 1;
  String? _localRoot; // node ID that is the ego-center

  // Concept node visibility (off by default — they can bloat the graph).
  bool _showConcepts = false;

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

  // --------------------------------------------------------------------------
  // Layout seeding — places nodes directly into star positions
  // --------------------------------------------------------------------------

  void _seedLayout(GraphData data) {
    _pos.clear();
    _vel.clear();
    _adj.clear();
    _edgeWeights.clear();
    _starPos.clear();
    _starRel.clear();
    _hubFor.clear();

    // Initialise adjacency lists and zero velocities.
    for (final node in data.nodes) {
      _adj[node.id] = [];
      _vel[node.id] = Offset.zero;
    }
    for (final e in data.edges) {
      _adj[e.source]?.add(e.target);
      _adj[e.target]?.add(e.source);
      final key = e.source.compareTo(e.target) < 0
          ? '${e.source}|${e.target}'
          : '${e.target}|${e.source}';
      _edgeWeights[key] = e.weight;
    }

    // Compute star positions and seed nodes directly into them so the graph
    // opens already in star form — no physics convergence needed.
    _starPos.addAll(_computeStarLayout(data, data.nodes));
    for (final node in data.nodes) {
      _pos[node.id] = _starPos[node.id] ?? Offset.zero;
    }

    _temperature = 45;
    if (!_ticker.isActive && data.nodes.isNotEmpty) _ticker.start();
  }

  // --------------------------------------------------------------------------
  // Star layout computation
  // --------------------------------------------------------------------------

  /// Returns the ideal star position for each node in [visible].
  ///
  /// Each connected cluster gets one **hub** (highest-degree node) placed on a
  /// coarse ring, with all other cluster members as **spokes** radiating
  /// outward at equal angular intervals.
  ///
  /// Cluster-hub separation = `_starRadius * 2.4` so adjacent clusters' spoke
  /// disks never spatially overlap, preventing cross-cluster edge crossings.
  Map<String, Offset> _computeStarLayout(
      GraphData data, List<GraphNode> visible) {
    final result = <String, Offset>{};

    // Group nodes by cluster ID.
    final clusterMap = <int, List<GraphNode>>{};
    for (final node in visible) {
      clusterMap.putIfAbsent(node.clusterId, () => []).add(node);
    }

    // Isolated nodes (-1) live on an outer ring, handled separately.
    final isolated = clusterMap.remove(-1) ?? <GraphNode>[];
    final clusterIds = clusterMap.keys.toList()..sort();
    final numClusters = clusterIds.length;

    // Minimum separation between adjacent cluster hubs so that no spoke from
    // cluster A can reach any spoke of cluster B.
    const clusterSep = _starRadius * 2.4;
    // Chord formula: for n equally spaced points on a ring, the chord between
    // adjacent points = 2 * R * sin(π / n). Solve for R given chord = clusterSep.
    final hubRingRadius = numClusters <= 1
        ? 0.0
        : clusterSep / (2 * math.sin(math.pi / numClusters));

    for (var ci = 0; ci < numClusters; ci++) {
      final cid = clusterIds[ci];
      final nodes = List<GraphNode>.from(clusterMap[cid]!);

      // Highest-degree node becomes the star's hub.
      nodes.sort((a, b) => b.degree.compareTo(a.degree));
      final hub = nodes.first;

      final hubAngle =
          (ci / math.max(1, numClusters)) * 2 * math.pi - math.pi / 2;
      final hubPos = numClusters <= 1
          ? Offset.zero
          : Offset(
              math.cos(hubAngle) * hubRingRadius,
              math.sin(hubAngle) * hubRingRadius,
            );
      result[hub.id] = hubPos;
      _hubFor[hub.id] = hub.id;
      _starRel[hub.id] = Offset.zero;

      // Place spoke nodes at equal angular intervals around the hub.
      final spokes = nodes.skip(1).toList();
      for (var si = 0; si < spokes.length; si++) {
        final spokeAngle =
            (si / math.max(1, spokes.length)) * 2 * math.pi - math.pi / 2;
        final rel = Offset(
          math.cos(spokeAngle) * _starRadius,
          math.sin(spokeAngle) * _starRadius,
        );
        result[spokes[si].id] = hubPos + rel;
        _hubFor[spokes[si].id] = hub.id;
        _starRel[spokes[si].id] = rel;
      }
    }

    // Isolated nodes on a ring well beyond all star clusters.
    final outerRadius = hubRingRadius + _starRadius * 1.6;
    for (var ii = 0; ii < isolated.length; ii++) {
      final angle =
          (ii / math.max(1, isolated.length)) * 2 * math.pi - math.pi / 2;
      result[isolated[ii].id] = Offset(
        math.cos(angle) * outerRadius,
        math.sin(angle) * outerRadius,
      );
      _hubFor[isolated[ii].id] = isolated[ii].id;
      _starRel[isolated[ii].id] = Offset.zero;
    }

    return result;
  }

  /// Recomputes star target positions for the currently visible node set and
  /// updates [_starPos].  Call whenever local-mode or depth changes.
  void _recomputeStar() {
    final data = _data;
    if (data == null) return;
    final visible = _visibleNodes(data);
    _starRel.clear();
    _hubFor.clear();
    _starPos
      ..clear()
      ..addAll(_computeStarLayout(data, visible));
  }

  // --------------------------------------------------------------------------
  // Physics tick — the Obsidian-style 4-force model
  // --------------------------------------------------------------------------

  void _onTick(Duration _) {
    final data = _data;
    if (data == null || _pos.isEmpty) return;

    final visible = _visibleNodes(data);
    final visibleIds = visible.map((n) => n.id).toSet();

    _step(data, visible, visibleIds);

    if (_temperature < 0.5) {
      _ticker.stop();
    }
    if (mounted) setState(() {});
  }

  void _step(GraphData data, List<GraphNode> visible, Set<String> visibleIds) {
    final ids = visible.map((n) => n.id).toList();
    final n = ids.length;
    if (n == 0) return;

    final k = _physics.linkDistance;
    final disp = <String, Offset>{for (final id in ids) id: Offset.zero};

    // Group visible nodes into connected components (families)
    final family = <String, int>{};
    var nextFamily = 0;
    for (final id in ids) {
      if (family.containsKey(id)) continue;
      nextFamily++;
      final queue = [id];
      family[id] = nextFamily;
      var head = 0;
      while (head < queue.length) {
        final curr = queue[head++];
        for (final nbr in (_adj[curr] ?? <String>[])) {
          if (visibleIds.contains(nbr) && !family.containsKey(nbr)) {
            family[nbr] = nextFamily;
            queue.add(nbr);
          }
        }
      }
    }

    // --- Force 1: Repulsion (Coulomb's law) ---
    // Every node pushes every other node away. Separate families repel 8x harder.
    final repelK = k * k * _physics.repelForce;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final pa = _pos[ids[i]];
        final pb = _pos[ids[j]];
        if (pa == null || pb == null) continue;
        var delta = pa - pb;
        var d = delta.distance;
        if (d < 0.01) {
          delta = const Offset(0.5, 0.3);
          d = delta.distance;
        }
        final sameFamily = family[ids[i]] == family[ids[j]];
        final mult = sameFamily ? 3.5 : 15.0;
        final force = (repelK * mult) / (d * d);
        final push = delta / d * force;
        disp[ids[i]] = disp[ids[i]]! + push;
        disp[ids[j]] = disp[ids[j]]! - push;
      }
    }

    // --- Force 2: Link/spring (Hooke's law) ---
    // Connected nodes attract each other toward the ideal link distance.
    for (final e in data.edges) {
      if (!visibleIds.contains(e.source) || !visibleIds.contains(e.target)) {
        continue;
      }
      final pa = _pos[e.source];
      final pb = _pos[e.target];
      if (pa == null || pb == null) continue;
      var delta = pa - pb;
      var d = delta.distance;
      if (d < 0.01) d = 0.01;
      // Spring: pulls when distance > k, pushes when < k.
      final force = (d - k) / d * _physics.linkForce * (0.4 + e.weight);
      final pull = delta / d * force;
      final degA = (_adj[e.source]?.length ?? 1).toDouble();
      final degB = (_adj[e.target]?.length ?? 1).toDouble();
      final totalDeg = degA + degB;
      final biasA = degB / totalDeg; // hub anchor stability
      final biasB = degA / totalDeg; // leaf node pull

      disp[e.source] = disp[e.source]! - pull * (biasA * 2);
      disp[e.target] = disp[e.target]! + pull * (biasB * 2);
    }

    // --- Force 3: Center gravity ---
    // Gentle pull toward origin keeps connected items centered inside.
    for (final id in ids) {
      if ((_adj[id]?.isEmpty ?? true)) continue; // empty nodes bypass inward gravity
      final p = _pos[id];
      if (p == null) continue;
      disp[id] = disp[id]! - p * _physics.centerForce;
    }

    // --- Force 4: Relative Star Schema Restoring Spring ---
    // Pulls every spoke node gently toward its ideal star offset relative to its CURRENT LIVE HUB POSITION.
    for (final id in ids) {
      if (id == _draggedNode) continue;
      final hubId = _hubFor[id];
      final rel = _starRel[id];
      if (hubId == null || rel == null || hubId == id) continue; // hub itself is free
      final hubPos = _pos[hubId];
      final curr = _pos[id];
      if (hubPos == null || curr == null) continue;
      final target = hubPos + rel;
      disp[id] = disp[id]! + (target - curr) * 0.22;
    }

    // --- Force 5: Segregated Circle Containment Wall ---
    // Connected clusters stay centered (< 130px). Empty nodes orbit far outer rim (220 - 260px).
    for (final id in ids) {
      if (id == _draggedNode) continue;
      final p = _pos[id];
      if (p == null) continue;
      final dist = p.distance;
      if (dist < 0.01) continue;
      if ((_adj[id]?.isEmpty ?? true)) {
        // Orbit rim halo for empty nodes.
        if (dist > 280.0) {
          disp[id] = disp[id]! - (p / dist) * (dist - 280.0) * 0.25;
        } else if (dist < 240.0) {
          disp[id] = disp[id]! + (p / dist) * (240.0 - dist) * 0.15;
        }
      } else {
        // Interior containment for connected nodes.
        if (dist > 190.0) {
          disp[id] = disp[id]! - (p / dist) * (dist - 190.0) * 0.25;
        }
      }
    }

    // --- Apply forces with temperature clamping + velocity damping ---
    const damping = 0.80; // less drag = bouncier spring oscillation
    for (final node in visible) {
      if (node.id == _draggedNode) continue;
      var dd = disp[node.id]!;
      // Add velocity (momentum).
      final oldVel = _vel[node.id] ?? Offset.zero;
      dd = dd + oldVel * damping;
      final len = dd.distance;
      if (len > 0) {
        dd = dd / len * math.min(len, _temperature);
      }
      _pos[node.id] = _pos[node.id]! + dd;
      _vel[node.id] = dd * 0.65; // carry 65% kinetic energy for snappy snapback
    }

    _temperature = _temperature * 0.96; // allow decaying below 0.5 so ticker stops naturally
  }

  // --------------------------------------------------------------------------
  // Local graph — BFS neighborhood
  // --------------------------------------------------------------------------

  List<GraphNode> _visibleNodes(GraphData data) {
    List<GraphNode> nodes;
    if (!_localMode || _localRoot == null) {
      nodes = data.nodes;
    } else {
      final root = _localRoot!;
      final visited = <String>{root};
      var frontier = <String>{root};
      for (var depth = 0; depth < _localDepth; depth++) {
        final next = <String>{};
        for (final nid in frontier) {
          for (final neighbor in (_adj[nid] ?? <String>[])) {
            if (visited.add(neighbor)) next.add(neighbor);
          }
        }
        frontier = next;
      }
      nodes = data.nodes.where((n) => visited.contains(n.id)).toList();
    }
    if (!_showConcepts) nodes = nodes.where((n) => !n.isConcept).toList();
    return nodes;
  }

  // --------------------------------------------------------------------------
  // Gestures
  // --------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails d, Size size) {
    _baseZoom = _zoom;
    final hit = _hitTest(d.localFocalPoint, size);
    if (hit != null && d.pointerCount == 1) {
      _draggedNode = hit;
      _selected = hit;
      // Reheat physics so neighbors react to the drag (rubber-band effect).
      _temperature = math.max(_temperature, 8.0);
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_draggedNode != null && d.pointerCount == 1) {
      final center = Offset(size.width / 2, size.height / 2);
      final world = (d.localFocalPoint - center - _pan) / _zoom;
      _pos[_draggedNode!] = world;
      // High heat while dragging so the constellation tracks smoothly.
      _temperature = math.max(_temperature, 35.0);
      if (!_ticker.isActive) _ticker.start();
      setState(() {});
      return;
    }
    if (d.pointerCount > 1 || _draggedNode == null) {
      setState(() {
        _zoom = (_baseZoom * d.scale).clamp(0.25, 3.5);
        _pan = _pan + d.focalPointDelta; // accumulate per-frame delta
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_draggedNode != null) {
      // Reheat enough for the restoring force to animate the snap-back
      // visibly, but not so hot that distant nodes thrash.
      _temperature = math.max(_temperature, 45.0);
      if (!_ticker.isActive) _ticker.start();
    }
    _draggedNode = null;
  }

  void _dragFamily(String rootId, Offset delta) {
    final visited = <String>{rootId};
    var frontier = <String>{rootId};
    var depth = 1;
    while (frontier.isNotEmpty && depth <= 25) {
      final next = <String>{};
      final factor = math.pow(0.96, depth).toDouble();
      for (final id in frontier) {
        for (final neighbor in (_adj[id] ?? <String>[])) {
          if (visited.add(neighbor)) {
            next.add(neighbor);
            if (_pos[neighbor] != null) {
              _pos[neighbor] = _pos[neighbor]! + delta * factor;
            }
          }
        }
      }
      frontier = next;
      depth++;
    }
  }

  void _onTapUp(TapUpDetails d, Size size) {
    final hit = _hitTest(d.localPosition, size);
    if (hit == null) {
      setState(() => _selected = null);
      return;
    }
    setState(() => _selected = hit);
    _showNodePreview(hit);
  }

  String? _hitTest(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final world = (local - center - _pan) / _zoom;
    String? best;
    double bestD = double.infinity;
    final maxHitWorld = 36.0 / _zoom; // constant 36 screen px touch target
    for (final entry in _pos.entries) {
      final d = (entry.value - world).distance;
      if (d < maxHitWorld && d < bestD) {
        bestD = d;
        best = entry.key;
      }
    }
    return best;
  }

  // --------------------------------------------------------------------------
  // Node preview (two-tap pattern)
  // --------------------------------------------------------------------------

  void _showNodePreview(String nodeId) {
    final data = _data;
    if (data == null) return;
    final node = data.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return;

    final neighbors = _adj[nodeId] ?? [];
    final neighborNodes =
        data.nodes.where((n) => neighbors.contains(n.id)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NodePreviewSheet(
        node: node,
        neighbors: neighborNodes,
        onOpen: () {
          Navigator.pop(ctx);
          if (node.isCard) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ReaderScreen(cardId: node.id)),
            );
          } else if (node.isConcept) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConceptDetailScreen(
                  entry: ConceptEntry(id: node.id, name: node.label),
                ),
              ),
            );
          }
        },
        onFocusLocal: () {
          Navigator.pop(ctx);
          setState(() {
            _localMode = true;
            _localRoot = node.id;
            _temperature = 60;
            if (!_ticker.isActive) _ticker.start();
          });
          _recomputeStar();
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Settings drawer
  // --------------------------------------------------------------------------

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _SettingsSheet(
        physics: _physics,
        localMode: _localMode,
        localDepth: _localDepth,
        onChanged: () {
          setState(() {
            // Reheat so graph reacts to new forces.
            _temperature = 60;
            if (!_ticker.isActive) _ticker.start();
          });
          // Update the bottom sheet's own state.
          (ctx as Element).markNeedsBuild();
        },
        onLocalModeChanged: (v) {
          setState(() {
            _localMode = v;
            if (!v) _localRoot = null;
            _temperature = 60;
            if (!_ticker.isActive) _ticker.start();
          });
          _recomputeStar();
          // Update the bottom sheet's own state.
          (ctx as Element).markNeedsBuild();
        },
        onLocalDepthChanged: (v) {
          setState(() {
            _localDepth = v;
            _temperature = 60;
            if (!_ticker.isActive) _ticker.start();
          });
          _recomputeStar();
          (ctx as Element).markNeedsBuild();
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final content = _body();
    if (!widget.showAppBar) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Graph'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showSettings,
          ),
          IconButton(
            tooltip: 'Re-layout',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading
                ? null
                : () {
                    if (_data != null) {
                      _seedLayout(_data!);
                      setState(() {});
                    }
                  },
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
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
        message:
            "Save a few cards and we'll link the ones that belong together.",
      );
    }

    final visible = _visibleNodes(data);
    final visibleIds = visible.map((n) => n.id).toSet();

    return Column(
      children: [
        // Local mode banner.
        if (_localMode && _localRoot != null)
          _LocalModeBanner(
            rootLabel: data.nodes
                    .where((n) => n.id == _localRoot)
                    .firstOrNull
                    ?.label ??
                'Unknown',
            depth: _localDepth,
            onExit: () {
              setState(() {
                _localMode = false;
                _localRoot = null;
                _temperature = 60;
                if (!_ticker.isActive) _ticker.start();
              });
              _recomputeStar();
            },
          ),
        // Cluster filter chips.
        if (!_localMode && data.clusters.isNotEmpty)
          _ClusterFilterBar(
            clusters: data.clusters,
            active: _activeCluster,
            onSelect: (id) => setState(() {
              _activeCluster = id == _activeCluster ? null : id;
            }),
          ),
        // Concept toggle — hidden by default to avoid hairball graphs.
        if (!_localMode && data.nodes.any((n) => n.isConcept))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                FilterChip(
                  avatar: Icon(
                    Icons.lightbulb_rounded,
                    size: 16,
                    color: _showConcepts
                        ? Theme.of(context).colorScheme.onPrimary
                        : const Color(0xFF5E4DA8),
                  ),
                  label: Text(
                    'Concepts',
                    style: Brand.label(
                      size: 12,
                      color: _showConcepts
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  selected: _showConcepts,
                  selectedColor: const Color(0xFF5E4DA8),
                  onSelected: (v) {
                    setState(() {
                      _showConcepts = v;
                      _temperature = 60;
                      if (!_ticker.isActive) _ticker.start();
                    });
                    _recomputeStar();
                  },
                  showCheckmark: false,
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size =
                  Size(constraints.maxWidth, constraints.maxHeight);
              return ClipRect(
                child: GestureDetector(
                  onScaleStart: (d) => _onScaleStart(d, size),
                  onScaleUpdate: (d) => _onScaleUpdate(d, size),
                  onScaleEnd: _onScaleEnd,
                  onTapUp: (d) => _onTapUp(d, size),
                  child: CustomPaint(
                    size: size,
                    painter: _GraphPainter(
                      data: data,
                      visibleIds: visibleIds,
                      positions: _pos,
                      hubMap: _hubFor,
                      pan: _pan,
                      zoom: _zoom,
                      selected: _selected,
                      adjacency: _adj,
                      activeCluster: _activeCluster,
                      theme: Theme.of(context),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ========================================================================== //
// Local mode banner
// ========================================================================== //

class _LocalModeBanner extends StatelessWidget {
  const _LocalModeBanner({
    required this.rootLabel,
    required this.depth,
    required this.onExit,
  });

  final String rootLabel;
  final int depth;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.filter_center_focus_rounded,
              size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Local graph · $rootLabel · depth $depth',
              style: Brand.label(size: 12, color: scheme.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onExit,
            child: Text('Show all',
                style: Brand.label(size: 12, color: scheme.primary)),
          ),
        ],
      ),
    );
  }
}

// ========================================================================== //
// Cluster filter bar
// ========================================================================== //

class _ClusterFilterBar extends StatelessWidget {
  const _ClusterFilterBar({
    required this.clusters,
    required this.active,
    required this.onSelect,
  });

  final List<GraphCluster> clusters;
  final int? active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('All', style: Brand.label(size: 12)),
              selected: active == null,
              onSelected: (_) => onSelect(-1),
              selectedColor: scheme.primaryContainer,
            ),
          ),
          for (final c in clusters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${c.label} (${c.count})',
                    style: Brand.label(size: 12)),
                selected: active == c.id,
                onSelected: (_) => onSelect(c.id),
                selectedColor: scheme.primaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}

// ========================================================================== //
// Node preview sheet (two-tap pattern)
// ========================================================================== //

class _NodePreviewSheet extends StatelessWidget {
  const _NodePreviewSheet({
    required this.node,
    required this.neighbors,
    required this.onOpen,
    required this.onFocusLocal,
  });

  final GraphNode node;
  final List<GraphNode> neighbors;
  final VoidCallback onOpen;
  final VoidCallback onFocusLocal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCard = node.isCard;

    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.2,
      maxChildSize: 0.5,
      builder: (ctx, sc) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Type badge.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCard
                        ? scheme.primaryContainer
                        : node.isConcept
                            ? scheme.secondaryContainer
                            : node.isFolder
                                ? scheme.secondaryContainer
                                : scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCard
                        ? node.contentType.toUpperCase()
                        : node.isConcept
                            ? 'CONCEPT'
                            : node.isFolder
                                ? 'FOLDER · ${node.contentType.toUpperCase()}'
                                : 'CATALOG · ${node.contentType.toUpperCase()}',
                    style: Brand.label(
                      size: 11,
                      weight: FontWeight.w700,
                      color: isCard
                          ? scheme.onPrimaryContainer
                          : node.isConcept
                              ? scheme.onSecondaryContainer
                              : node.isFolder
                                  ? scheme.onSecondaryContainer
                                  : scheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${node.degree} connections',
                  style: Brand.label(
                      size: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              node.label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (neighbors.isNotEmpty) ...[
              Text(
                'CONNECTED TO',
                style: Brand.label(
                    size: 11,
                    weight: FontWeight.w700,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: neighbors.take(8).map((n) {
                  return Chip(
                    avatar: Icon(
                      n.isCard
                          ? Icons.article_rounded
                          : n.isConcept
                              ? Icons.lightbulb_rounded
                              : Icons.category_rounded,
                      size: 16,
                    ),
                    label: Text(
                      n.label.length > 30
                          ? '${n.label.substring(0, 30)}…'
                          : n.label,
                      style: Brand.label(size: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              if (neighbors.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+${neighbors.length - 8} more',
                    style: Brand.label(
                        size: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (isCard || node.isConcept)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
                if (isCard || node.isConcept) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onFocusLocal,
                    icon: const Icon(
                        Icons.filter_center_focus_rounded,
                        size: 18),
                    label: const Text('Focus'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================================================== //
// Settings sheet (force sliders)
// ========================================================================== //

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.physics,
    required this.localMode,
    required this.localDepth,
    required this.onChanged,
    required this.onLocalModeChanged,
    required this.onLocalDepthChanged,
  });

  final _PhysicsConfig physics;
  final bool localMode;
  final int localDepth;
  final VoidCallback onChanged;
  final ValueChanged<bool> onLocalModeChanged;
  final ValueChanged<int> onLocalDepthChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('FORCES',
              style: Brand.label(
                  size: 12,
                  weight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'Repel force',
            value: physics.repelForce,
            min: 0.0,
            max: 3.0,
            onChanged: (v) {
              physics.repelForce = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Link force',
            value: physics.linkForce,
            min: 0.0,
            max: 3.0,
            onChanged: (v) {
              physics.linkForce = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Center force',
            value: physics.centerForce,
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              physics.centerForce = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Link distance',
            value: physics.linkDistance,
            min: 30,
            max: 200,
            onChanged: (v) {
              physics.linkDistance = v;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          Text('LOCAL GRAPH',
              style: Brand.label(
                  size: 12,
                  weight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          SwitchListTile(
            title: Text('Local mode',
                style: Brand.label(size: 13, color: scheme.onSurface)),
            subtitle: Text('Show only neighbors of a selected node',
                style: Brand.label(
                    size: 11, color: scheme.onSurfaceVariant)),
            value: localMode,
            onChanged: onLocalModeChanged,
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          if (localMode)
            _SliderRow(
              label: 'Depth',
              value: localDepth.toDouble(),
              min: 1,
              max: 3,
              divisions: 2,
              onChanged: (v) => onLocalDepthChanged(v.round()),
            ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: Brand.label(size: 12, color: scheme.onSurface)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value == value.roundToDouble()
                ? value.toInt().toString()
                : value.toStringAsFixed(1),
            style: Brand.label(size: 11, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ========================================================================== //
// Graph painter
// ========================================================================== //

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.data,
    required this.visibleIds,
    required this.positions,
    required this.hubMap,
    required this.pan,
    required this.zoom,
    required this.selected,
    required this.adjacency,
    required this.activeCluster,
    required this.theme,
  });

  final GraphData data;
  final Set<String> visibleIds;
  final Map<String, Offset> positions;
  final Map<String, String> hubMap;
  final Offset pan;
  final double zoom;
  final String? selected;
  final Map<String, List<String>> adjacency;
  final int? activeCluster;
  final ThemeData theme;

  Offset _screen(Offset world, Size size) =>
      Offset(size.width / 2, size.height / 2) + pan + world * zoom;

  bool _isNeighbour(String id) =>
      selected != null &&
      (id == selected || (adjacency[selected]?.contains(id) ?? false));

  bool _inActiveCluster(GraphNode node) {
    if (activeCluster == null) return true;
    return node.clusterId == activeCluster;
  }

  Color _nodeColor(GraphNode node) {
    if (node.isConcept) {
      return const Color(0xFF5E4DA8); // purple — distinct from cards/catalog/folders
    }
    if (node.isFolder) {
      if (node.contentType != 'custom') {
        try {
          return ContentAccent.of(ContentType.fromWire(node.contentType)).color;
        } catch (_) {}
      }
      return const Color(0xFF6B5C4E);
    }
    if (node.isCard) {
      return ContentAccent.of(ContentType.fromWire(node.contentType)).color;
    }
    const catalogColors = <String, Color>{
      'book': Color(0xFF8B6F47),
      'movie': Color(0xFF3E5C73),
      'tv_show': Color(0xFF4F6B7A),
      'podcast': Color(0xFF7A5A86),
      'music': Color(0xFFB08227),
      'product': Color(0xFF6B8E5A),
      'place': Color(0xFF2F7E80),
      'app': Color(0xFF5A6B8E),
      'other': Color(0xFF8A7A6C),
    };
    return catalogColors[node.contentType] ?? const Color(0xFF8A7A6C);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scheme = theme.colorScheme;
    final clampedZoom = zoom.clamp(0.5, 1.6);

    // --- Edges ---
    for (final e in data.edges) {
      if (!visibleIds.contains(e.source) || !visibleIds.contains(e.target)) {
        continue;
      }
      final a = positions[e.source];
      final b = positions[e.target];
      if (a == null || b == null) continue;

      final highlight = selected != null &&
          (e.source == selected || e.target == selected);

      final sourceNode =
          data.nodes.where((n) => n.id == e.source).firstOrNull;
      final targetNode =
          data.nodes.where((n) => n.id == e.target).firstOrNull;
      final clusterDim = activeCluster != null &&
          (sourceNode == null || !_inActiveCluster(sourceNode)) &&
          (targetNode == null || !_inActiveCluster(targetNode));

      final base = highlight ? scheme.primary : scheme.outlineVariant;
      final alpha = clusterDim
          ? 0.06
          : highlight
              ? 0.9
              : (0.18 + 0.5 * e.weight).clamp(0.0, 0.7);

      double sw;
      if (e.kind == 'reference') {
        sw = (highlight ? 2.5 : 1.2 + e.weight) * clampedZoom;
      } else if (e.kind == 'tag') {
        sw = (highlight ? 1.5 : 0.5) * clampedZoom;
      } else if (e.kind == 'membership') {
        sw = (highlight ? 2.0 : 1.4) * clampedZoom;
      } else {
        sw = (highlight ? 2.2 : 0.6 + e.weight * 1.6) * clampedZoom;
      }

      final paint = Paint()
        ..color = base.withValues(alpha: alpha)
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round;

      final sa = _screen(a, size);
      final sb = _screen(b, size);

      if (e.kind == 'reference') {
        _drawDashedLine(canvas, sa, sb, paint, 6.0, 4.0);
      } else if (e.kind == 'tag') {
        _drawDashedLine(canvas, sa, sb, paint, 2.0, 4.0);
      } else {
        canvas.drawLine(sa, sb, paint);
      }
    }

    // --- Nodes ---
    final dim = selected != null || activeCluster != null;
    for (final node in data.nodes) {
      if (!visibleIds.contains(node.id)) continue;
      final p = positions[node.id];
      if (p == null) continue;
      final s = _screen(p, size);
      final accent = _nodeColor(node);
      final double r;
      if (node.isFolder) {
        r = (22.0 + node.degree * 0.6).clamp(22.0, 36.0) * clampedZoom;
      } else if (node.isCard) {
        r = (10.0 + node.degree * 0.8).clamp(10.0, 18.0) * clampedZoom;
      } else {
        r = (5.0 + node.degree * 0.4).clamp(5.0, 9.0) * clampedZoom;
      }

      final bool faded;
      if (activeCluster != null && !_inActiveCluster(node)) {
        faded = true;
      } else if (selected != null && !_isNeighbour(node.id)) {
        faded = true;
      } else {
        faded = false;
      }

      // Selection halo.
      if (node.id == selected) {
        canvas.drawCircle(
            s, r + 6, Paint()..color = accent.withValues(alpha: 0.25));
      }

      if (node.isConcept) {
        final diamond = _diamondPath(s, r * 1.3);
        canvas.drawPath(diamond,
            Paint()..color = accent.withValues(alpha: faded ? 0.2 : 1.0));
        canvas.drawPath(
            diamond,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = scheme.surface.withValues(alpha: faded ? 0.3 : 0.9));
      } else if (node.isFolder) {
        final hex = _hexPath(s, r * 1.2);
        canvas.drawPath(hex, Paint()..color = accent.withValues(alpha: faded ? 0.2 : 1.0));
        canvas.drawPath(hex, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = scheme.surface.withValues(alpha: faded ? 0.3 : 0.9));
      } else if (node.isCatalog) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: s, width: r * 2, height: r * 2),
          Radius.circular(r * 0.3),
        );
        canvas.drawRRect(rect,
            Paint()..color = accent.withValues(alpha: faded ? 0.2 : 1.0));
        canvas.drawRRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color =
                  scheme.surface.withValues(alpha: faded ? 0.3 : 0.9));
      } else {
        canvas.drawCircle(s, r,
            Paint()..color = accent.withValues(alpha: faded ? 0.2 : 1.0));
        canvas.drawCircle(
            s,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color =
                  scheme.surface.withValues(alpha: faded ? 0.3 : 0.9));
      }

      // LOD labels.
      if (zoom > 0.65 && !faded) {
        final maxLines = zoom >= 1.0 ? 2 : 1;
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
          maxLines: maxLines,
          ellipsis: '…',
        )..layout(maxWidth: 105);
        Offset labelPos;
        final hId = hubMap[node.id];
        final hPos = hId != null ? positions[hId] : null;
        final cPos = positions[node.id];
        if (hPos != null && cPos != null && hId != node.id) {
          final d = cPos - hPos;
          final ang = math.atan2(d.dy, d.dx);
          final out = r + 4.0;
          final cx = s.dx + math.cos(ang) * (out + tp.width / 2);
          final cy = s.dy + math.sin(ang) * (out + tp.height / 2);
          labelPos = Offset(cx - tp.width / 2, cy - tp.height / 2);
        } else {
          labelPos = Offset(s.dx - tp.width / 2, s.dy + r + 3);
        }
        tp.paint(canvas, labelPos);
      }

      // Folder icon badge.
      if (node.isFolder && zoom > 0.6 && !faded) {
        final iconSize = (r * 0.85).clamp(10.0, 20.0);
        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.folder_rounded.codePoint),
            style: TextStyle(
              fontFamily: Icons.folder_rounded.fontFamily,
              package: Icons.folder_rounded.fontPackage,
              fontSize: iconSize,
              color: scheme.surface.withValues(alpha: 0.9),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        iconPainter.paint(
          canvas,
          Offset(s.dx - iconPainter.width / 2, s.dy - iconPainter.height / 2),
        );
      }

      // Concept icon badge.
      if (node.isConcept && zoom > 0.8 && !faded) {
        final iconSize = (r * 0.9).clamp(8.0, 16.0);
        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.lightbulb_rounded.codePoint),
            style: TextStyle(
              fontFamily: Icons.lightbulb_rounded.fontFamily,
              package: Icons.lightbulb_rounded.fontPackage,
              fontSize: iconSize,
              color: scheme.surface.withValues(alpha: 0.9),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        iconPainter.paint(
          canvas,
          Offset(s.dx - iconPainter.width / 2, s.dy - iconPainter.height / 2),
        );
      }

      // Catalog icon badge.
      if (node.isCatalog && zoom > 0.8 && !faded) {
        final iconSize = (r * 0.8).clamp(10.0, 18.0);
        final icon = _catalogIcon(node.contentType);
        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: iconSize,
              color: scheme.surface.withValues(alpha: 0.9),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        iconPainter.paint(
          canvas,
          Offset(
              s.dx - iconPainter.width / 2, s.dy - iconPainter.height / 2),
        );
      }
    }
  }

  Path _diamondPath(Offset center, double r) {
    return Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r, center.dy)
      ..close();
  }

  Path _hexPath(Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    return path..close();
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final delta = b - a;
    final len = delta.distance;
    if (len < 1) return;
    final dir = delta / len;
    var drawn = 0.0;
    while (drawn < len) {
      final start = a + dir * drawn;
      final end = a + dir * math.min(drawn + dash, len);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  IconData _catalogIcon(String contentType) {
    const icons = <String, IconData>{
      'book': Icons.menu_book_rounded,
      'movie': Icons.movie_rounded,
      'tv_show': Icons.tv_rounded,
      'podcast': Icons.podcasts_rounded,
      'music': Icons.music_note_rounded,
      'product': Icons.shopping_bag_rounded,
      'place': Icons.place_rounded,
      'app': Icons.apps_rounded,
      'other': Icons.category_rounded,
    };
    return icons[contentType] ?? Icons.category_rounded;
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
