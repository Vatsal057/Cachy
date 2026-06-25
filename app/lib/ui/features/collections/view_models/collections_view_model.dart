/// Collections list state (MVVM, docs/09): the user's named groups of cards.
/// Loads from the repository, supports create + delete. Detail (member cards)
/// is fetched on demand by the detail screen.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/collection.dart';

enum CollectionsStatus { idle, loading, ready, error, empty }

class CollectionsViewModel extends ChangeNotifier {
  CollectionsViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  CollectionsStatus _status = CollectionsStatus.idle;
  CollectionsStatus get status => _status;

  List<Collection> _collections = const [];
  List<Collection> get collections => List.unmodifiable(_collections);

  String? _error;
  String? get error => _error;

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _status = CollectionsStatus.loading;
      notifyListeners();
    }
    try {
      final list = await _repository.listCollections();
      _collections = list;
      _status =
          list.isEmpty ? CollectionsStatus.empty : CollectionsStatus.ready;
      _error = null;
    } catch (e) {
      _error = '$e';
      _status = CollectionsStatus.error;
    }
    notifyListeners();
  }

  Future<void> refresh() => load(showSpinner: false);

  Future<void> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _repository.createCollection(trimmed);
    await load(showSpinner: false);
  }

  Future<void> delete(String id) async {
    _collections = _collections.where((c) => c.id != id).toList();
    if (_collections.isEmpty) _status = CollectionsStatus.empty;
    notifyListeners();
    try {
      await _repository.deleteCollection(id);
    } catch (_) {
      await load(showSpinner: false);
    }
  }
}
