library;

class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.name,
    required this.isCustom,
    required this.cardCount,
    required this.createdAt,
    this.systemType,
  });

  final String id;
  final String name;
  final bool isCustom;
  final int cardCount;
  final DateTime? createdAt;
  /// Wire value of ContentType, e.g. "recipe". Null for custom collections.
  final String? systemType;

  factory CollectionEntry.fromJson(Map<String, dynamic> json) => CollectionEntry(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        isCustom: (json['is_custom'] as bool?) ?? false,
        cardCount: (json['card_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
        systemType: json['system_type'] as String?,
      );
}
