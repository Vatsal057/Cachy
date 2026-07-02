/// d3-force style knowledge graph: a live force-directed physics simulation that
/// runs on every open, letting nodes wiggle and settle into emergent clusters.
///
/// Physics model ported from Org Roam UI's d3-force engine:
///   1. **Charge** — every node repels every other (forceManyBody).
///   2. **Link** — connected nodes spring toward ideal distance (forceLink).
///   3. **Center** — gentle pull toward origin (forceCenter).
///   4. **Gravity** — forceX/Y toward origin.
///   5. **Collision** — prevents node overlap (forceCollide).
///
/// Uses alpha-decay cooling: forces scale by alpha (0→1), which decays
/// exponentially each tick. This gives smooth "settling into equilibrium" feel.
///
/// Drag pins a node while physics recalculates around it (rubber-band effect).
/// Two node types (card = circle, catalog = rounded square), three edge styles,
/// cluster filter chips, and a two-tap preview sheet.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/concept.dart';
import '../../../../domain/models/enums.dart';
import '../../../../domain/models/graph.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/spot_art.dart';
import '../../concepts/views/concept_detail_screen.dart';
import '../../feed/views/connections_screen.dart';
import '../../presenter/agent_bus.dart';
import '../../reader/views/reader_screen.dart';

// ========================================================================== //
// Physics tuning defaults
// ========================================================================== //

class _PhysicsConfig {
  /// forceManyBody strength (negative = repulsive). Org Roam UI default: -700.
  double charge;

  /// forceLink strength. Org Roam UI default: 0.3.
  double linkStrength;

  /// forceLink ideal rest length.
  double linkDistance;

  /// forceLink constraint iterations per tick.
  int linkIterations;

  /// forceX/Y gravity strength. Org Roam UI default: 0.3.
  double gravity;

  /// Whether gravity forces are active.
  bool gravityOn;

  /// forceCenter strength. Org Roam UI default: 0.2.
  double centerStrength;

  /// Whether centering force is active.
  bool centerOn;

  /// Whether collision detection is active.
  bool collision;

  /// forceCollide radius.
  double collisionRadius;

  /// Alpha decay rate per tick (lower = slower settling). Org Roam UI: 0.0228.
  double alphaDecay;

  /// Velocity damping per tick (0–1, higher = more damping). Org Roam UI: 0.25.
  double velocityDecay;

  /// Minimum alpha before simulation stops.
  double alphaMin;

  _PhysicsConfig({
    this.charge = -900,
    this.linkStrength = 0.6,
    this.linkDistance = 115,
    this.linkIterations = 1,
    this.gravity = 0.04,
    this.gravityOn = true,
    this.centerStrength = 0.08,
    this.centerOn = true,
    this.collision = true,
    this.collisionRadius = 50,
    this.alphaDecay = 0.035,
    this.velocityDecay = 0.28,
    this.alphaMin = 0.001,
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

  // d3-force alpha — controls how much force is applied each tick.
  // Starts at 1.0 on reheat, decays toward alphaMin.
  double _alpha = 1.0;
  double _alphaTarget = 0.0;

  // View transform.
  Offset _pan = Offset.zero;
  double _zoom = 0.72;
  double _baseZoom = 0.72;
  String? _selected;
  String? _draggedNode;

  // Cluster filter.
  int? _activeCluster;

  // Physics config.
  final _physics = _PhysicsConfig(
    charge: -900,
    linkStrength: 0.6,
    linkDistance: 115,
    linkIterations: 1,
    gravity: 0.04,
    gravityOn: true,
    centerStrength: 0.08,
    centerOn: true,
    collision: true,
    collisionRadius: 50,
    alphaDecay: 0.035,
    velocityDecay: 0.28,
    alphaMin: 0.001,
  );

  // Local graph mode.
  bool _localMode = false;
  int _localDepth = 1;
  String? _localRoot; // node ID that is the ego-center

  // Concepts ON by default — they're the backbone hubs connecting cards by meaning.
  bool _showConcepts = true;

  // Agent driving: the presenter agent operates the graph through these hooks
  // while this screen is mounted (see AgentBus). The canvas key gives its
  // spotlight the real canvas bounds.
  AgentBus? _bus;
  GraphAgentHooks? _hooks;
  final _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hooks != null) return;
    _bus = context.read<AgentBus>();
    final hooks = GraphAgentHooks(
      nodes: () => _data?.nodes ?? const [],
      isReady: () => _data != null && !_loading,
      focus: _agentFocus,
      open: _agentOpen,
      wander: _agentWander,
      reset: _agentReset,
      filterCluster: _agentFilterCluster,
      toggleConcepts: _agentToggleConcepts,
    );
    _hooks = hooks;
    _bus!.attachGraph(hooks);
    _bus!.registerSpotlight('graph.canvas', _canvasKey);
  }

  @override
  void dispose() {
    final h = _hooks;
    if (h != null) _bus?.detachGraph(h);
    _bus?.unregisterSpotlight('graph.canvas', _canvasKey);
    _ticker.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Agent-driven controls (mirror the manual gesture handlers)
  // --------------------------------------------------------------------------

  /// Center + select a node and dive into its neighborhood, so the audience
  /// sees exactly what it connects to.
  Future<void> _agentFocus(String id) async {
    if (!mounted) return;
    final p = _pos[id];
    setState(() {
      _selected = id;
      if (p != null) _pan = -p * _zoom;
      _localMode = true;
      _localRoot = id;
      _alpha = 1.0;
      _alphaTarget = 0.0;
    });
    if (!_ticker.isActive) _ticker.start();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
  }

  /// Open a node's underlying card (in the reader, under the agent glyph) or
  /// concept detail.
  Future<void> _agentOpen(String id) async {
    final node = _data?.nodes.where((n) => n.id == id).firstOrNull;
    if (node == null) return;
    if (node.isCard) {
      await _bus?.onOpenCard?.call(node.id);
    } else if (node.isConcept && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConceptDetailScreen(
            entry: ConceptEntry(id: node.id, name: node.label),
          ),
        ),
      );
    }
  }

  /// Reheat the physics and drift the view so the layout visibly comes alive.
  Future<void> _agentWander() async {
    if (!mounted) return;
    setState(() {
      _localMode = false;
      _localRoot = null;
      _alpha = 1.0;
      _alphaTarget = 0.0;
    });
    if (!_ticker.isActive) _ticker.start();
    const steps = 22;
    for (var i = 0; i < steps; i++) {
      if (!mounted) return;
      final angle = (i / steps) * 2 * math.pi;
      setState(() => _pan = Offset(math.cos(angle), math.sin(angle)) * 26);
      await Future<void>.delayed(const Duration(milliseconds: 95));
    }
    if (mounted) setState(() => _pan = Offset.zero);
  }

  /// Exit ego/local mode and recenter.
  void _agentReset() {
    if (!mounted) return;
    setState(() {
      _localMode = false;
      _localRoot = null;
      _selected = null;
      _pan = Offset.zero;
      _alpha = 1.0;
      _alphaTarget = 0.0;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  /// Filter the graph down to a single community cluster.
  Future<void> _agentFilterCluster() async {
    final data = _data;
    if (!mounted || data == null || data.clusters.isEmpty) return;
    setState(() {
      _localMode = false;
      _localRoot = null;
      _activeCluster = data.clusters.first.id;
      _alpha = 1.0;
      _alphaTarget = 0.0;
    });
    if (!_ticker.isActive) _ticker.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
  }

  /// Toggle the concept hub nodes on/off so the audience sees their effect.
  Future<void> _agentToggleConcepts() async {
    if (!mounted) return;
    setState(() {
      _showConcepts = !_showConcepts;
      _alpha = 1.0;
      _alphaTarget = 0.0;
    });
    if (!_ticker.isActive) _ticker.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
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

    // Cluster-ring seeding: place clusters on a ring, jitter nodes within.
    // Physics will find the organic layout from here.
    final clusterMap = <int, List<GraphNode>>{};
    for (final node in data.nodes) {
      clusterMap.putIfAbsent(node.clusterId, () => []).add(node);
    }
    final isolated = clusterMap.remove(-1) ?? <GraphNode>[];
    final clusterIds = clusterMap.keys.toList()..sort();
    final numClusters = clusterIds.length;
    final rng = math.Random(42);

    // Cluster hubs on a ring.
    const clusterSep = 200.0;
    final hubRingRadius = numClusters <= 1
        ? 0.0
        : clusterSep / (2 * math.sin(math.pi / math.max(2, numClusters)));

    for (var ci = 0; ci < numClusters; ci++) {
      final cid = clusterIds[ci];
      final nodes = clusterMap[cid]!;
      final hubAngle =
          (ci / math.max(1, numClusters)) * 2 * math.pi - math.pi / 2;
      final hubPos = numClusters <= 1
          ? Offset.zero
          : Offset(
              math.cos(hubAngle) * hubRingRadius,
              math.sin(hubAngle) * hubRingRadius,
            );

      // Jitter each node around the cluster center.
      for (final node in nodes) {
        _pos[node.id] = hubPos +
            Offset(
              (rng.nextDouble() - 0.5) * 80,
              (rng.nextDouble() - 0.5) * 80,
            );
      }
    }

    // Isolated nodes in a ring beyond clusters.
    final outerRadius = hubRingRadius + 180;
    for (var ii = 0; ii < isolated.length; ii++) {
      final angle =
          (ii / math.max(1, isolated.length)) * 2 * math.pi - math.pi / 2;
      _pos[isolated[ii].id] = Offset(
        math.cos(angle) * outerRadius,
        math.sin(angle) * outerRadius,
      );
    }

    // Run 80 warmup ticks silently so the graph opens in a settled state
    // rather than showing chaotic initial animation.
    _alpha = 1.0;
    _alphaTarget = 0.0;
    final visible = _visibleNodes(data);
    final visibleIds = visible.map((n) => n.id).toSet();
    for (var i = 0; i < 80; i++) {
      _step(data, visible, visibleIds);
      if (_alpha < _physics.alphaMin) break;
    }

    // Start the ticker for remaining settling.
    _alpha = math.max(_alpha, 0.1);
    if (!_ticker.isActive && data.nodes.isNotEmpty) _ticker.start();
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

    if (_alpha < _physics.alphaMin) {
      _ticker.stop();
    }
    if (mounted) setState(() {});
  }

  /// d3-force simulation step.
  ///
  /// Applies five forces scaled by [_alpha], matching Org Roam UI's d3-force:
  ///   1. Charge (forceManyBody) — repulsion between all node pairs.
  ///   2. Link (forceLink) — spring toward ideal distance.
  ///   3. Center (forceCenter) — pull toward origin.
  ///   4. Gravity (forceX/Y) — directional pull toward origin.
  ///   5. Collision (forceCollide) — prevents node overlap.
  void _step(GraphData data, List<GraphNode> visible, Set<String> visibleIds) {
    final ids = visible.map((n) => n.id).toList();
    final n = ids.length;
    if (n == 0) return;

    // --- Alpha decay (d3's cooling schedule) ---
    _alpha += (_alphaTarget - _alpha) * _physics.alphaDecay;

    // --- Force 1: Charge / Many-Body (d3.forceManyBody) ---
    // Every node repels every other node.
    // d3 formula: vel += delta * strength * alpha / d²  (raw delta, NOT unit vector)
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final pa = _pos[ids[i]];
        final pb = _pos[ids[j]];
        if (pa == null || pb == null) continue;
        var delta = pa - pb;
        var d = delta.distance;
        if (d < 1.0) {
          // Jitter to break degeneracy (d3 does this too).
          delta = Offset(
            (ids[i].hashCode.isEven ? 1 : -1) * 0.5,
            (ids[j].hashCode.isEven ? 1 : -1) * 0.3,
          );
          d = delta.distance;
        }
        // d3's forceManyBody: delta * strength * alpha / d²
        // Using raw delta (not normalized) — this is critical.
        // Makes force fall off as 1/d (not 1/d²), giving long-range repulsion.
        final w = _physics.charge * _alpha / (d * d);
        final push = delta * w;
        // Negative charge → push is opposite to delta → repulsive.
        _vel[ids[i]] = (_vel[ids[i]] ?? Offset.zero) - push;
        _vel[ids[j]] = (_vel[ids[j]] ?? Offset.zero) + push;
      }
    }

    // --- Force 2: Link / Spring (d3.forceLink) ---
    // Multiple iterations for constraint convergence (d3's linkIterations).
    for (var iter = 0; iter < _physics.linkIterations; iter++) {
      for (final e in data.edges) {
        if (!visibleIds.contains(e.source) ||
            !visibleIds.contains(e.target)) {
          continue;
        }
        final pa = _pos[e.source];
        final pb = _pos[e.target];
        if (pa == null || pb == null) continue;
        var delta = pb - pa;
        var d = delta.distance;
        if (d < 0.01) d = 0.01;

        // d3-style bias: distribute force inversely by degree.
        final degA = math.max(1.0, (_adj[e.source]?.length ?? 1).toDouble());
        final degB = math.max(1.0, (_adj[e.target]?.length ?? 1).toDouble());
        final bias = degA / (degA + degB);

        // Spring force: pull toward ideal link distance.
        // D3 degree scaling: divide strength by minDeg so densely connected hubs don't crush together.
        final minDeg = math.min(degA, degB);
        final k = _physics.linkDistance;
        final strength = (_physics.linkStrength / minDeg) * _alpha;
        final force = (d - k) / d * strength;
        final fx = delta.dx * force;
        final fy = delta.dy * force;

        // Apply with degree-bias (lighter nodes move more).
        _vel[e.target] = (_vel[e.target] ?? Offset.zero) -
            Offset(fx * bias, fy * bias);
        _vel[e.source] = (_vel[e.source] ?? Offset.zero) +
            Offset(fx * (1 - bias), fy * (1 - bias));
      }
    }

    // --- Force 3: Center (d3.forceCenter) ---
    // Shifts the center of mass toward origin.
    if (_physics.centerOn) {
      var cx = 0.0, cy = 0.0;
      var count = 0;
      for (final id in ids) {
        final p = _pos[id];
        if (p == null) continue;
        cx += p.dx;
        cy += p.dy;
        count++;
      }
      if (count > 0) {
        cx = cx / count * _physics.centerStrength;
        cy = cy / count * _physics.centerStrength;
        for (final id in ids) {
          final p = _pos[id];
          if (p == null) continue;
          _pos[id] = Offset(p.dx - cx, p.dy - cy);
        }
      }
    }

    // --- Force 4: Gravity (d3.forceX / d3.forceY) ---
    // Individual pull toward origin (unlike center which shifts the mean).
    if (_physics.gravityOn) {
      for (final id in ids) {
        final p = _pos[id];
        if (p == null) continue;
        _vel[id] = (_vel[id] ?? Offset.zero) +
            Offset(-p.dx * _physics.gravity * _alpha,
                   -p.dy * _physics.gravity * _alpha);
      }
    }

    // --- Force 5: Collision (d3.forceCollide) ---
    if (_physics.collision) {
      final r = _physics.collisionRadius;
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final pa = _pos[ids[i]];
          final pb = _pos[ids[j]];
          if (pa == null || pb == null) continue;
          var delta = pa - pb;
          var d = delta.distance;
          final minDist = r * 2; // each node has radius r
          if (d < minDist && d > 0.01) {
            final overlap = (minDist - d) / d * 0.5;
            final push = delta * overlap;
            _pos[ids[i]] = pa + push;
            _pos[ids[j]] = pb - push;
          }
        }
      }
    }

    // --- Apply velocity + damping (d3's velocityDecay) ---
    for (final node in visible) {
      if (node.id == _draggedNode) {
        _vel[node.id] = Offset.zero;
        continue;
      }
      final vel = _vel[node.id] ?? Offset.zero;
      // d3 velocity decay: vel *= (1 - velocityDecay)
      final dampedVel = vel * (1.0 - _physics.velocityDecay);
      _vel[node.id] = dampedVel;
      _pos[node.id] = (_pos[node.id] ?? Offset.zero) + dampedVel;
    }
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
      _lastDragWorld = null;
      // Reheat strongly so neighbors react to the drag.
      _alphaTarget = 0.3;
      _alpha = math.max(_alpha, 0.5);
      if (!_ticker.isActive) _ticker.start();
    }
  }

  Offset? _lastDragWorld;

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    if (_draggedNode != null && d.pointerCount == 1) {
      final center = Offset(size.width / 2, size.height / 2);
      final world = (d.localFocalPoint - center - _pan) / _zoom;
      final prev = _lastDragWorld ?? _pos[_draggedNode!] ?? world;
      final worldDelta = world - prev;
      _pos[_draggedNode!] = world;
      _vel[_draggedNode!] = Offset.zero;
      _lastDragWorld = world;
      // Elastic drag: pull neighbors along with depth-decaying strength.
      _dragFamily(_draggedNode!, worldDelta);
      // Keep alpha warm while dragging.
      _alpha = math.max(_alpha, 0.3);
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
      _vel[_draggedNode!] = Offset.zero;
      // Let it settle naturally from a moderate alpha.
      _alphaTarget = 0.0;
      _alpha = math.max(_alpha, 0.3);
      _lastDragWorld = null;
      if (!_ticker.isActive) _ticker.start();
    }
    _draggedNode = null;
  }

  void _dragFamily(String rootId, Offset delta) {
    final visited = <String>{rootId};
    var frontier = <String>{rootId};
    var depth = 1;
    while (frontier.isNotEmpty && depth <= 6) {
      final next = <String>{};
      final factor = math.pow(0.7, depth).toDouble();
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
        edges: data.edges,
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
            _alpha = 1.0;
            _alphaTarget = 0.0;
            if (!_ticker.isActive) _ticker.start();
          });
        },
        onSelectNeighbor: (nId) {
          Navigator.pop(ctx);
          setState(() => _selected = nId);
          final p = _pos[nId];
          if (p != null) {
            setState(() => _pan = -p * _zoom);
          }
          _showNodePreview(nId);
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
            _alpha = 1.0;
            _alphaTarget = 0.0;
            if (!_ticker.isActive) _ticker.start();
          });
          // Update the bottom sheet's own state.
          (ctx as Element).markNeedsBuild();
        },
        onLocalModeChanged: (v) {
          setState(() {
            _localMode = v;
            if (!v) _localRoot = null;
            _alpha = 1.0;
            _alphaTarget = 0.0;
            if (!_ticker.isActive) _ticker.start();
          });
          // Update the bottom sheet's own state.
          (ctx as Element).markNeedsBuild();
        },
        onLocalDepthChanged: (v) {
          setState(() {
            _localDepth = v;
            _alpha = 1.0;
            _alphaTarget = 0.0;
            if (!_ticker.isActive) _ticker.start();
          });
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
            tooltip: 'Connections',
            icon: const PhosphorIcon(PhosphorIconsRegular.sparkle),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectionsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const PhosphorIcon(PhosphorIconsRegular.sliders),
            onPressed: _showSettings,
          ),
          IconButton(
            tooltip: 'Re-layout',
            icon: const PhosphorIcon(PhosphorIconsRegular.arrowClockwise),
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
        icon: PhosphorIconsRegular.graph,
        title: 'Nothing to connect yet',
        message:
            "Save a few cards and we'll link the ones that belong together.",
        art: GraphSpot(),
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
                _alpha = 1.0;
                _alphaTarget = 0.0;
                if (!_ticker.isActive) _ticker.start();
              });
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
        // Concept toggle — always visible in library view so user can toggle concepts.
        if (!_localMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                FilterChip(
                  avatar: PhosphorIcon(
                    PhosphorIconsRegular.lightbulb,
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
                      _alpha = 1.0;
                      _alphaTarget = 0.0;
                      if (!_ticker.isActive) _ticker.start();
                    });
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
                key: _canvasKey,
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
          PhosphorIcon(PhosphorIconsRegular.crosshair,
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
    required this.edges,
    required this.onOpen,
    required this.onFocusLocal,
    required this.onSelectNeighbor,
  });

  final GraphNode node;
  final List<GraphNode> neighbors;
  final List<GraphEdge> edges;
  final VoidCallback onOpen;
  final VoidCallback onFocusLocal;
  final ValueChanged<String> onSelectNeighbor;

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
                'CONNECTED TO (${neighbors.length})',
                style: Brand.label(
                    size: 11,
                    weight: FontWeight.w700,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Column(
                children: neighbors.map((n) {
                  final edge = edges.where((e) =>
                      (e.source == node.id && e.target == n.id) ||
                      (e.source == n.id && e.target == node.id)).firstOrNull;
                  final topics = edge?.sharedTopics ?? [];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => onSelectNeighbor(n.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            PhosphorIcon(
                              n.isCard
                                  ? PhosphorIconsRegular.article
                                  : n.isConcept
                                      ? PhosphorIconsRegular.lightbulb
                                      : PhosphorIconsRegular.shapes,
                              size: 20,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.label,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (topics.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        PhosphorIcon(
                                          PhosphorIconsRegular.tag,
                                          size: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            topics.join(', '),
                                            style: Brand.label(
                                              size: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PhosphorIcon(
                              PhosphorIconsRegular.caretRight,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (isCard || node.isConcept)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const PhosphorIcon(PhosphorIconsRegular.arrowUpRight, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
                if (isCard || node.isConcept) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onFocusLocal,
                    icon: const PhosphorIcon(
                        PhosphorIconsRegular.crosshair,
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
            label: 'Charge',
            value: -physics.charge / 100,
            min: 0.0,
            max: 20.0,
            onChanged: (v) {
              physics.charge = -v * 100;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Link strength',
            value: physics.linkStrength * 5,
            min: 0.0,
            max: 5.0,
            onChanged: (v) {
              physics.linkStrength = v / 5;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Link distance',
            value: physics.linkDistance,
            min: 30,
            max: 300,
            onChanged: (v) {
              physics.linkDistance = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Gravity',
            value: physics.gravity * 10,
            min: 0.0,
            max: 10.0,
            onChanged: (v) {
              physics.gravity = v / 10;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Center force',
            value: physics.centerStrength,
            min: 0.0,
            max: 2.0,
            onChanged: (v) {
              physics.centerStrength = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Damping',
            value: physics.velocityDecay * 10,
            min: 0.0,
            max: 10.0,
            onChanged: (v) {
              physics.velocityDecay = v / 10;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Settle rate',
            value: physics.alphaDecay * 50,
            min: 0.0,
            max: 5.0,
            onChanged: (v) {
              physics.alphaDecay = v / 50;
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
        sw = (highlight ? 1.5 : 0.6 + e.weight * 0.5) * clampedZoom;
      } else if (e.kind == 'tag') {
        sw = (highlight ? 0.9 : 0.35) * clampedZoom;
      } else if (e.kind == 'membership') {
        sw = (highlight ? 1.2 : 0.7) * clampedZoom;
      } else {
        sw = (highlight ? 1.4 : 0.35 + e.weight * 0.9) * clampedZoom;
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
    for (final node in data.nodes) {
      if (!visibleIds.contains(node.id)) continue;
      final p = positions[node.id];
      if (p == null) continue;
      final s = _screen(p, size);
      final accent = _nodeColor(node);
      final double r;
      if (node.isConcept) {
        // Hub size scales with how many cards share the concept.
        r = (14.0 + node.degree * 1.2).clamp(14.0, 30.0) * clampedZoom;
      } else if (node.isFolder) {
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
        // Place labels below nodes (no hub-based placement needed).
        labelPos = Offset(s.dx - tp.width / 2, s.dy + r + 3);
        tp.paint(canvas, labelPos);
      }

      // Folder icon badge.
      if (node.isFolder && zoom > 0.6 && !faded) {
        final iconSize = (r * 0.85).clamp(10.0, 20.0);
        const folderIcon = PhosphorIconsFill.folder;
        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(folderIcon.codePoint),
            style: TextStyle(
              fontFamily: folderIcon.fontFamily,
              package: folderIcon.fontPackage,
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
        const lightbulbIcon = PhosphorIconsRegular.lightbulb;
        final iconPainter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(lightbulbIcon.codePoint),
            style: TextStyle(
              fontFamily: lightbulbIcon.fontFamily,
              package: lightbulbIcon.fontPackage,
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
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
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

  PhosphorIconData _catalogIcon(String contentType) {
    const icons = <String, PhosphorIconData>{
      'book': PhosphorIconsRegular.bookOpen,
      'movie': PhosphorIconsRegular.filmSlate,
      'tv_show': PhosphorIconsRegular.television,
      'podcast': PhosphorIconsRegular.microphone,
      'music': PhosphorIconsRegular.musicNote,
      'product': PhosphorIconsRegular.shoppingBag,
      'place': PhosphorIconsRegular.mapPin,
      'app': PhosphorIconsRegular.appWindow,
      'other': PhosphorIconsRegular.shapes,
    };
    return icons[contentType] ?? PhosphorIconsRegular.shapes;
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
