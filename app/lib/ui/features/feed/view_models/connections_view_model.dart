/// Drives the Connections view (the serendipity engine's own surface): loads
/// surprising links between the owner's cards and can spend a little more LLM
/// budget to surface fresh ones on demand.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../../domain/models/feed.dart';

class ConnectionsViewModel extends ChangeNotifier {
  ConnectionsViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  List<Connection> _items = const [];
  List<Connection> get items => List.unmodifiable(_items);

  bool _loading = false;
  bool get loading => _loading;

  /// True while a user-triggered "find more" pass runs (distinct from the first
  /// load so the UI can keep showing existing links).
  bool _refreshing = false;
  bool get refreshing => _refreshing;

  String? _error;
  String? get error => _error;

  bool get isEmpty => _items.isEmpty;

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _refreshing = true;
    } else {
      _loading = true;
    }
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.connections(limit: 15, refresh: refresh);
    } on ApiException catch (e) {
      _error = e.statusCode == 503
          ? 'Connections need an AI backend to explain the links.'
          : "Couldn't load connections.";
    } catch (_) {
      _error = "Couldn't reach the backend.";
    }
    _loading = false;
    _refreshing = false;
    notifyListeners();
  }
}
