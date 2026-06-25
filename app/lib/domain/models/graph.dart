/// Knowledge-graph model (mirrors backend GET /graph). Cards are nodes; an edge
/// means two cards are similar (semantic embedding + shared tags). Isolated nodes
/// (no edge) are notes with nothing similar enough yet — they float alone.
library;

class GraphNode {
  const GraphNode({
    required this.id,
    required this.label,
    this.contentType = 'other',
    this.thumbnail,
    this.tags = const [],
    this.degree = 0,
  });

  final String id;
  final String label;
  final String contentType;
  final String? thumbnail;
  final List<String> tags;
  final int degree; // edge count — drives node size

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: (json['id'] as String?) ?? '',
        label: (json['label'] as String?) ?? 'Untitled',
        contentType: (json['content_type'] as String?) ?? 'other',
        thumbnail: json['thumbnail'] as String?,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        degree: (json['degree'] as num?)?.toInt() ?? 0,
      );
}

class GraphEdge {
  const GraphEdge({
    required this.source,
    required this.target,
    this.weight = 0.0,
  });

  final String source;
  final String target;
  final double weight;

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
        source: (json['source'] as String?) ?? '',
        target: (json['target'] as String?) ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      );
}

class GraphData {
  const GraphData({this.nodes = const [], this.edges = const []});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

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
      );
}
