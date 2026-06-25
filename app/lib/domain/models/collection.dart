/// A user-created collection: a named group of cards (docs/09). Mirrors the
/// backend contract (backend models/collection.py). Membership is by card id;
/// the cards themselves are unchanged, so this needs no block-schema change.
library;

import 'card.dart';

class Collection {
  const Collection({
    required this.id,
    required this.name,
    this.cardIds = const [],
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> cardIds;
  final DateTime? createdAt;

  int get count => cardIds.length;

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        cardIds: (json['card_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
      );
}

/// A collection plus its resolved member cards (the detail endpoint payload).
class CollectionDetail {
  const CollectionDetail({required this.collection, this.cards = const []});

  final Collection collection;
  final List<Card> cards;

  factory CollectionDetail.fromJson(Map<String, dynamic> json) =>
      CollectionDetail(
        collection: Collection.fromJson(
          (json['collection'] as Map<String, dynamic>?) ?? const {},
        ),
        cards: ((json['cards'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Card.fromJson)
            .toList(),
      );
}
