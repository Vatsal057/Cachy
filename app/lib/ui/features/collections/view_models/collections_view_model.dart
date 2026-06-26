library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart';
import '../../../../domain/models/collection.dart';
import '../../../../domain/models/enums.dart';

/// View-layer folder: backend entry + one preview card for the thumbnail.
class Collection {
  const Collection({
    required this.entry,
    this.previewCard,
  });

  final CollectionEntry entry;
  final Card? previewCard;

  String get id => entry.id;
  String get name => entry.name;
  int get count => entry.cardCount;
  bool get isCustom => entry.isCustom;

  ContentType? get contentType {
    final st = entry.systemType;
    if (st == null) return null;
    return ContentType.fromWire(st);
  }
}

/// Display name for each content type — used as fallback when no backend data.
String collectionName(ContentType type) {
  switch (type) {
    case ContentType.recipe:
      return 'Recipes';
    case ContentType.workout:
      return 'Workouts';
    case ContentType.tutorial:
      return 'Tutorials';
    case ContentType.tip:
      return 'Tips';
    case ContentType.productList:
      return 'Products';
    case ContentType.travel:
      return 'Travel';
    case ContentType.newsExplainer:
      return 'Explainers';
    case ContentType.other:
      return 'Notes';
  }
}

enum CollectionsStatus { idle, loading, ready, error, empty }

class CollectionsViewModel extends ChangeNotifier {
  CollectionsViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  CollectionsStatus _status = CollectionsStatus.idle;
  CollectionsStatus get status => _status;

  List<Collection> _collections = const [];
  List<Collection> get collections => _collections;

  String? _error;
  String? get error => _error;

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _status = CollectionsStatus.loading;
      notifyListeners();
    }
    try {
      final entries = await _repository.listCollections();
      // Load a page of cards to pick preview thumbnails.
      final cards = await _repository.list();
      _collections = _buildCollections(entries, cards);
      _error = null;
      _status = _collections.isEmpty ? CollectionsStatus.empty : CollectionsStatus.ready;
    } catch (e) {
      _error = '$e';
      // Fall back to client-side grouping from cached cards.
      try {
        final cards = await _repository.list();
        _collections = _clientSideCollections(cards);
        _status = _collections.isEmpty ? CollectionsStatus.empty : CollectionsStatus.ready;
      } catch (_) {
        _status = _collections.isEmpty ? CollectionsStatus.error : CollectionsStatus.ready;
      }
    }
    notifyListeners();
  }

  Future<void> refresh() => load(showSpinner: false);

  Future<void> rename(String collectionId, String newName) async {
    final updated = await _repository.renameCollection(collectionId, newName);
    _collections = _collections.map((c) {
      if (c.id == collectionId) return Collection(entry: updated, previewCard: c.previewCard);
      return c;
    }).toList();
    notifyListeners();
  }

  Future<Collection> createFolder(String name) async {
    final entry = await _repository.createCollection(name);
    final col = Collection(entry: entry);
    _collections = [..._collections, col];
    _status = CollectionsStatus.ready;
    notifyListeners();
    return col;
  }

  List<Collection> _buildCollections(List<CollectionEntry> entries, List<Card> cards) {
    // Build a quick lookup: collection_id → first card with thumbnail.
    final previews = <String, Card>{};
    for (final c in cards) {
      final cid = c.collectionId;
      if (cid == null) continue;
      if (!previews.containsKey(cid) || c.thumbnail != null) {
        previews[cid] = c;
      }
    }
    return entries
        .where((e) => e.cardCount > 0 || e.isCustom)
        .map((e) => Collection(entry: e, previewCard: previews[e.id]))
        .toList();
  }

  /// Client-side fallback: group cards by contentType (works without backend).
  List<Collection> _clientSideCollections(List<Card> cards) {
    final map = <ContentType, List<Card>>{};
    for (final c in cards) {
      map.putIfAbsent(c.base.contentType, () => []).add(c);
    }
    return ContentType.values.where(map.containsKey).map((t) {
      final group = map[t]!;
      final preview = group.firstWhere(
        (c) => c.thumbnail != null,
        orElse: () => group.first,
      );
      final fakeEntry = CollectionEntry(
        id: t.wire,
        name: collectionName(t),
        isCustom: false,
        cardCount: group.length,
        createdAt: null,
        systemType: t.wire,
      );
      return Collection(entry: fakeEntry, previewCard: preview);
    }).toList();
  }
}
