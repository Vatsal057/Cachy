/// Library grid state (MVVM). Loads cards from the repository, supports
/// pull-to-refresh, filtering by state, and delete. Falls back to cache offline.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart';
import '../../../../domain/models/enums.dart';

enum LibraryStatus { idle, loading, ready, error, empty }

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  LibraryStatus _status = LibraryStatus.idle;
  LibraryStatus get status => _status;

  List<Card> _cards = const [];
  List<Card> get cards => List.unmodifiable(_cards);

  CardState? _filter;
  CardState? get filter => _filter;

  String? _error;
  String? get error => _error;

  bool _offline = false;
  bool get offline => _offline;

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _status = LibraryStatus.loading;
      notifyListeners();
    }
    try {
      await _repository.flushPendingShares();
      final cards = await _repository.list(state: _filter);
      _cards = cards;
      _offline = false;
      _status = cards.isEmpty ? LibraryStatus.empty : LibraryStatus.ready;
      _error = null;
    } catch (e) {
      _error = '$e';
      _offline = true;
      _status = _cards.isEmpty ? LibraryStatus.error : LibraryStatus.ready;
    }
    notifyListeners();
  }

  Future<void> refresh() => load(showSpinner: false);

  void setFilter(CardState? state) {
    if (_filter == state) return;
    _filter = state;
    load();
  }

  Future<void> delete(String cardId) async {
    _cards = _cards.where((c) => c.cardId != cardId).toList();
    if (_cards.isEmpty && _status == LibraryStatus.ready) {
      _status = LibraryStatus.empty;
    }
    notifyListeners();
    try {
      await _repository.delete(cardId);
    } catch (_) {
      await load(showSpinner: false); // resync on failure
    }
  }
}
