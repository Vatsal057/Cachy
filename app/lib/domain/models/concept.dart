/// Concept node: a source-independent evergreen idea mined across all cards.
/// Mirrors the backend concept subsystem (models/concept.py).
library;

class ConceptEntry {
  const ConceptEntry({
    required this.id,
    required this.name,
    this.sourceCardIds = const [],
    this.definition,
  });

  final String id;
  final String name;
  final List<String> sourceCardIds;

  /// On-demand LLM definition; null until "Define" is tapped.
  final String? definition;

  factory ConceptEntry.fromJson(Map<String, dynamic> json) => ConceptEntry(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        sourceCardIds: (json['source_card_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        definition: json['definition'] as String?,
      );
}

class ConceptDetail {
  const ConceptDetail({required this.entry, this.related = const []});

  final ConceptEntry entry;
  final List<ConceptEntry> related;

  factory ConceptDetail.fromJson(Map<String, dynamic> json) => ConceptDetail(
        entry: ConceptEntry.fromJson(
            (json['entry'] as Map<String, dynamic>?) ?? {}),
        related: (json['related'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ConceptEntry.fromJson)
                .toList() ??
            const [],
      );
}
