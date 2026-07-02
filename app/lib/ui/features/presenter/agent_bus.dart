/// The bridge that lets the presenting agent actually *operate* the app.
///
/// Cachy has no central controller registry — each feature keeps its live UI
/// state private inside its own `State`. Rather than rewire every screen into a
/// global controller, the agent talks to screens through this bus:
///
///  * the host shell registers [onNavigate] / [onOpenCard] / [onCreateCard] so
///    the agent can move between views and open cards, and
///  * interactive screens (graph, feed, search) register a small set of
///    imperative *hooks* while they're mounted, which the agent invokes to
///    drive them live (focus a graph node, advance the feed, run a search).
///
/// A screen attaches its hooks in `initState`/`didChangeDependencies` and
/// detaches them in `dispose`, so the agent only ever drives what's on screen.
library;

import 'package:flutter/widgets.dart';

import '../../../domain/models/graph.dart';

/// A single thing the agent can do: a verb ([type]) plus its arguments.
///
/// The vocabulary is shared with the backend `/presenter/ask` endpoint, which
/// returns these to answer audience questions by *performing* them.
@immutable
class AgentAction {
  const AgentAction(this.type, [this.args = const {}]);

  /// One of: navigate, create_card, search, open_card, graph_focus,
  /// graph_open, graph_wander, graph_reset, feed_next, feed_prev, wait.
  final String type;
  final Map<String, dynamic> args;

  String? get view => args['view'] as String?;
  String? get query => args['query'] as String?;
  String? get url => args['url'] as String?;

  factory AgentAction.fromJson(Map<String, dynamic> json) => AgentAction(
        (json['do'] as String?)?.trim() ?? 'none',
        Map<String, dynamic>.from(json)..remove('do'),
      );
}

/// One beat of narration: optionally [say] something, optionally do [action].
/// Beats run in order; within a beat speech starts first and the action fires a
/// moment later *while* the agent is still talking — the way a human presenter
/// narrates over their own clicks.
@immutable
class AgentBeat {
  const AgentBeat({this.say, this.action, this.view, this.focus});

  final String? say;
  final AgentAction? action;

  /// Convenience for tour beats that just switch view before speaking.
  final String? view;

  /// Optional spotlight target id (see [AgentBus.spotlightRect]); when absent
  /// the target is derived from the action type.
  final String? focus;

  factory AgentBeat.fromJson(Map<String, dynamic> json) {
    final rawAction = json['action'];
    return AgentBeat(
      say: (json['say'] as String?)?.trim(),
      action: rawAction is Map<String, dynamic>
          ? AgentAction.fromJson(rawAction)
          : null,
    );
  }
}

/// Imperative controls a mounted [graph screen] exposes to the agent.
class GraphAgentHooks {
  GraphAgentHooks({
    required this.nodes,
    required this.isReady,
    required this.focus,
    required this.open,
    required this.wander,
    required this.reset,
    required this.filterCluster,
    required this.toggleConcepts,
  });

  /// Snapshot of the currently loaded graph nodes (empty until loaded).
  final List<GraphNode> Function() nodes;

  /// True once graph data is loaded and the screen can be driven.
  final bool Function() isReady;

  /// Center + select a node and dive into its neighborhood (ego view).
  final Future<void> Function(String nodeId) focus;

  /// Open a node's underlying card/concept.
  final Future<void> Function(String nodeId) open;

  /// Reheat the physics + drift the view so the layout visibly comes alive.
  final Future<void> Function() wander;

  /// Exit ego/local mode and recenter.
  final void Function() reset;

  /// Apply a cluster filter so only one community stays visible.
  final Future<void> Function() filterCluster;

  /// Toggle the concept hub nodes on/off.
  final Future<void> Function() toggleConcepts;
}

/// Imperative controls a mounted feed exposes to the agent.
class FeedAgentHooks {
  FeedAgentHooks({
    required this.next,
    required this.prev,
    required this.count,
    required this.shuffle,
  });

  final void Function() next;
  final void Function() prev;
  final int Function() count;

  /// Reshuffle the feed into a fresh set of moments.
  final void Function() shuffle;
}

/// Imperative controls a mounted search screen exposes to the agent.
class SearchAgentHooks {
  SearchAgentHooks({required this.run, required this.filter});

  /// Type a query into the search box and run it.
  final void Function(String query) run;

  /// Apply the first available content-type filter to the current results.
  final void Function() filter;
}

/// Imperative controls a mounted reader exposes to the agent, so it can show
/// that cards are interactive (checkable steps and checklists) live.
class ReaderAgentHooks {
  ReaderAgentHooks({
    required this.isReady,
    required this.toggleCheck,
    required this.toggleStep,
  });

  /// True once the card is loaded.
  final bool Function() isReady;

  /// Toggle the first checklist item; returns true if there was one.
  final Future<bool> Function() toggleCheck;

  /// Mark the first step complete; returns true if there was one.
  final Future<bool> Function() toggleStep;
}

/// Shared channel between the [PresenterController] agent and the app.
///
/// Provided app-wide (see `main.dart`). The shell sets the navigation callbacks;
/// feature screens attach/detach their hooks as they mount/unmount.
class AgentBus extends ChangeNotifier {
  // ── Shell-provided navigation ─────────────────────────────────────────── //

  /// Switch the visible view. Recognized: library, feed, graph, search,
  /// collections, actions, profile, catalog, concepts, connections.
  void Function(String view)? onNavigate;

  /// Open a card in the reader (kept under the agent glyph, not pushed).
  Future<void> Function(String cardId)? onOpenCard;

  /// Submit a URL to the live pipeline and open the resulting card.
  Future<String?> Function(String url)? onCreateCard;

  /// Open a concept's detail (auto-defines if it has no definition yet).
  Future<void> Function(String conceptId, String name)? onOpenConcept;

  /// Open the rabbit-hole explorer for a card, seeded with a topic.
  Future<void> Function(String cardId, String seed)? onOpenRabbitHole;

  /// Open the grounded per-card chat, seeded with a question it auto-asks.
  Future<void> Function(String cardId, String title, String seed)?
      onOpenCardChat;

  /// Open the whole-library chat, seeded with a question it auto-asks.
  Future<void> Function(String seed)? onOpenLibraryChat;

  /// Switch the library's top segment (0 = Cards, 1 = Concepts, 2 = Catalog).
  /// Concepts and Catalog are tabs inside the library, not separate screens —
  /// the agent flips the real tab so the switch reads as a tap on the tab, not
  /// a full-screen swap.
  void Function(int index)? onLibraryTab;

  /// Open the first catalog item's detail and generate its info (the catalog
  /// "Fetch info" demo). No-op if the catalog is empty.
  Future<void> Function()? onOpenCatalogItem;

  /// Expand the reader's "Dive deeper" section in place (scrolls it into view
  /// and opens the panel). Registered by the section while a reader is on
  /// screen; null if the current card has no deep-dive.
  Future<void> Function()? onExpandDeepDive;

  // ── Screen-provided hooks (present only while that screen is mounted) ──── //

  GraphAgentHooks? graph;
  FeedAgentHooks? feed;
  SearchAgentHooks? search;
  ReaderAgentHooks? reader;

  void attachGraph(GraphAgentHooks hooks) => graph = hooks;
  void detachGraph(GraphAgentHooks hooks) {
    if (identical(graph, hooks)) graph = null;
  }

  void attachFeed(FeedAgentHooks hooks) => feed = hooks;
  void detachFeed(FeedAgentHooks hooks) {
    if (identical(feed, hooks)) feed = null;
  }

  void attachSearch(SearchAgentHooks hooks) => search = hooks;
  void detachSearch(SearchAgentHooks hooks) {
    if (identical(search, hooks)) search = null;
  }

  void attachReader(ReaderAgentHooks hooks) => reader = hooks;
  void detachReader(ReaderAgentHooks hooks) {
    if (identical(reader, hooks)) reader = null;
  }

  // ── Spotlight target registry ─────────────────────────────────────────── //
  //
  // Screens tag the widget the agent acts on (search field, graph canvas, nav
  // bar…) with a GlobalKey and register it here while mounted. The spotlight
  // layer resolves live geometry from the key, so the guided-focus hole hugs
  // the real widget instead of a guessed screen region.

  final Map<String, GlobalKey> _spotlightKeys = {};

  void registerSpotlight(String id, GlobalKey key) => _spotlightKeys[id] = key;

  void unregisterSpotlight(String id, GlobalKey key) {
    if (identical(_spotlightKeys[id], key)) _spotlightKeys.remove(id);
  }

  /// Current global-coordinate bounds of a registered target, or null while it
  /// isn't mounted / laid out.
  ///
  /// A GlobalKey can still resolve a `currentContext` for an element that has
  /// been deactivated (mid screen-swap during Present mode) — calling
  /// `findRenderObject()` on it throws "Cannot get renderObject of inactive
  /// element". Guard on `context.mounted` and catch defensively so a
  /// transitioning target just reads as "not visible yet" instead of crashing
  /// the frame.
  Rect? spotlightRect(String id) {
    final context = _spotlightKeys[id]?.currentContext;
    if (context == null || !context.mounted) return null;
    try {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    } catch (_) {
      return null;
    }
  }

  // ── Scrollable registry ───────────────────────────────────────────────── //
  //
  // Screens with a meaningful scroll surface (library grid, reader body)
  // register their ScrollController here while mounted, so the agent can
  // scroll the app the way a person would while presenting.

  final Map<String, ScrollController> _scrollables = {};

  void registerScrollable(String id, ScrollController controller) =>
      _scrollables[id] = controller;

  void unregisterScrollable(String id, ScrollController controller) {
    if (identical(_scrollables[id], controller)) _scrollables.remove(id);
  }

  /// Smoothly scroll a registered surface by [dy] pixels (negative = up),
  /// clamped to its extent, over [duration]. No-op while the surface isn't
  /// mounted. Returns the distance actually travelled (0 if it couldn't move).
  Future<double> scrollBy(
    String id,
    double dy, {
    Duration duration = const Duration(milliseconds: 900),
  }) async {
    final c = _scrollables[id];
    if (c == null || !c.hasClients) return 0;
    final from = c.offset;
    final target = (from + dy).clamp(0.0, c.position.maxScrollExtent);
    if ((target - from).abs() < 1) return 0;
    await c.animateTo(target, duration: duration, curve: Curves.easeInOutCubic);
    return target - from;
  }

  /// Distance a registered surface can still scroll down from where it is.
  double scrollRoom(String id) {
    final c = _scrollables[id];
    if (c == null || !c.hasClients) return 0;
    return (c.position.maxScrollExtent - c.offset).clamp(0.0, double.infinity);
  }
}
