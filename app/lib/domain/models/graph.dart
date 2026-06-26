/// Multi-entity knowledge graph model (mirrors backend GET /graph).
///
/// Two node types: cards (content nodes) and catalog items (artifact nodes).
/// Three edge types: semantic (embedding similarity), reference (catalog item ↔
/// source card), and tag (shared tags only). Layout is computed client-side via
/// a live Obsidian-style force-directed physics simulation. Server provides
/// graph topology and cluster IDs only.
library;

class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    this.nodeType = 'card',
    this.contentType = 'other',
    this.thumbnail,
    this.tags = const [],
    this.degree = 0,
    this.clusterId = -1,
  });

  final String id;
  final String label;

  /// `"card"` or `"catalog"`.
  final String nodeType;

  /// Content type for cards (e.g. "recipe"), artifact type for catalog (e.g. "book").
  final String contentType;
  final String? thumbnail;
  final List<String> tags;
  final int degree;

  /// Community cluster ID from label propagation. -1 = isolated.
  final int clusterId;

  bool get isCard => nodeType == 'card';
  bool get isCatalog => nodeType == 'catalog';
  bool get isFolder => nodeType == 'folder';

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: (json['id'] as String?) ?? '',
        label: (json['label'] as String?) ?? 'Untitled',
        nodeType: (json['node_type'] as String?) ?? 'card',
        contentType: (json['content_type'] as String?) ?? 'other',
        thumbnail: json['thumbnail'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        degree: (json['degree'] as num?)?.toInt() ?? 0,
        clusterId: (json['cluster_id'] as num?)?.toInt() ?? -1,
      );
}


class GraphEdge {
  const GraphEdge({
    required this.source,
    required this.target,
    this.weight = 0.0,
    this.kind = 'semantic',
  });

  final String source;
  final String target;
  final double weight;

  /// `"semantic"`, `"reference"`, or `"tag"`.
  final String kind;

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
        source: (json['source'] as String?) ?? '',
        target: (json['target'] as String?) ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
        kind: (json['kind'] as String?) ?? 'semantic',
      );
}

/// Server-generated cluster metadata.
class GraphCluster {
  const GraphCluster({
    required this.id,
    required this.label,
    this.count = 0,
  });

  final int id;
  final String label;
  final int count;

  factory GraphCluster.fromJson(Map<String, dynamic> json) => GraphCluster(
        id: (json['id'] as num?)?.toInt() ?? -1,
        label: (json['label'] as String?) ?? 'Unknown',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

class GraphData {
  const GraphData({
    this.nodes = const [],
    this.edges = const [],
    this.clusters = const [],
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphCluster> clusters;

  bool get isEmpty => nodes.isEmpty;

  factory GraphData.fromJson(Map<String, dynamic> json) => GraphData(
        nodes: (json['nodes'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(GraphNode.fromJson)
                .toList() ??
            const [],
        edges: (json['edges'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(GraphEdge.fromJson)
                .toList() ??
            const [],
        clusters: (json['clusters'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(GraphCluster.fromJson)
                .toList() ??
            const [],
      );
}
