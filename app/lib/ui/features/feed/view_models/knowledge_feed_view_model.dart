/// Drives the Knowledge Feed: loads the shuffled stream of moments for the
/// current owner and exposes loading / error / empty states. The feed is
/// assembled server-side from the user's own cards (reel-style "scroll your
/// brain"), so this view model is a thin loader.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../../domain/models/feed.dart';

class KnowledgeFeedViewModel extends ChangeNotifier {
  KnowledgeFeedViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  List<FeedItem> _items = const [];
  List<FeedItem> get items => List.unmodifiable(_items);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  bool get isEmpty => _items.isEmpty;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.feed(limit: 40);
    } on ApiException catch (_) {
      _error = "Couldn't load your feed.";
    } catch (_) {
      _error = "Couldn't reach the backend.";
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() => load();
}
