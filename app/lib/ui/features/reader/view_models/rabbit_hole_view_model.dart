/// The rabbit-hole explorer (docs/14): a generative, branching "go deeper"
/// journey over a card. Each tapped thread is explored via the backend into an
/// explanation plus fresh follow-on threads; the view model holds the ordered
/// trail and replays it on every turn so the exploration stays coherent.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../core/safe_notifier.dart';

class RabbitHoleViewModel extends ChangeNotifier with SafeNotifier {
  RabbitHoleViewModel({required CardRepository repository, required this.cardId})
      : _repository = repository;

  final CardRepository _repository;
  final String cardId;

  /// The topic the journey started from — the persistence key (docs/14).
  String _root = '';

  final List<RabbitHoleStep> _steps = [];

  /// The explored trail, oldest → newest.
  List<RabbitHoleStep> get steps => List.unmodifiable(_steps);

  bool _busy = false;
  bool get busy => _busy;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// The topic currently being fetched — shown as a pending breadcrumb.
  String? _pendingTopic;
  String? get pendingTopic => _pendingTopic;

  /// Topic to retry after a failure (null when there is nothing to retry).
  String? _failedTopic;
  bool get canRetry => _failedTopic != null && !_busy;

  bool get isEmpty => _steps.isEmpty;

  /// The deepest step reached — what the screen renders.
  RabbitHoleStep? get current => _steps.isEmpty ? null : _steps.last;

  /// Restore this owner's saved exploration for [seed] on entry; if none exists,
  /// kick off the first dive. Runs after the first frame.
  void start(String seed) {
    _root = seed.trim();
    Future.microtask(() async {
      _loading = true;
      notifyListeners();
      try {
        final saved = await _repository.rabbitHoleHistory(cardId, _root);
        _steps.addAll(saved);
      } catch (_) {
        // Best-effort restore; a fresh exploration is fine.
      }
      _loading = false;
      notifyListeners();
      if (_steps.isEmpty) dive(seed);
    });
  }

  /// Push a new thread onto the trail and explore it one hop deeper.
  Future<void> dive(String topic) async {
    final trimmed = topic.trim();
    if (trimmed.isEmpty || _busy) return;

    _busy = true;
    _error = null;
    _failedTopic = null;
    _pendingTopic = trimmed;
    notifyListeners();

    final trail = _steps.map((s) => s.topic).toList();
    try {
      final step =
          await _repository.exploreRabbitHole(cardId, trimmed, trail, _root);
      _steps.add(step);
    } on ApiException catch (e) {
      _failedTopic = trimmed;
      _error = e.statusCode == 503
          ? 'The rabbit hole is unavailable — no AI backend is configured.'
          : "Couldn't explore that thread. Try again.";
    } catch (_) {
      _failedTopic = trimmed;
      _error = "Couldn't reach the backend.";
    }
    _busy = false;
    _pendingTopic = null;
    notifyListeners();
  }

  /// Retry the dive that just failed.
  void retry() {
    final topic = _failedTopic;
    if (topic != null) dive(topic);
  }

  /// Jump back to an already-explored step (breadcrumb tap), discarding the
  /// deeper trail so the reader can branch a different way.
  void jumpTo(int index) {
    if (_busy || index < 0 || index >= _steps.length - 1) return;
    _steps.removeRange(index + 1, _steps.length);
    _error = null;
    _failedTopic = null;
    notifyListeners();
  }
}
