/// Actions hub state (MVVM, docs/13). Loads every card the user has *followed*
/// the actions of, flattens their to-dos grouped by source reel, and toggles
/// done state (optimistic + PATCH). The hub is a read-across-cards view; the
/// per-card list itself is owned by the card.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart';

enum ActionsStatus { idle, loading, ready, error, empty }

/// One reel's followed to-dos, for a sectioned display.
class ActionGroup {
  const ActionGroup({required this.card, required this.items});
  final Card card;
  final List<ActionItem> items;

  int get pending => items.where((i) => !i.done).length;
  bool get allDone => items.isNotEmpty && pending == 0;
}

class ActionsViewModel extends ChangeNotifier {
  ActionsViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  ActionsStatus _status = ActionsStatus.idle;
  ActionsStatus get status => _status;

  String? _error;
  String? get error => _error;

  List<ActionGroup> _groups = const [];
  List<ActionGroup> get groups => _groups;

  /// Total to-dos still open across every followed reel — drives a nav badge.
  int get pendingCount =>
      _groups.fold(0, (sum, g) => sum + g.pending);

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _status = ActionsStatus.loading;
      notifyListeners();
    }
    try {
      final cards = await _repository.list();
      final groups = <ActionGroup>[
        for (final c in cards)
          if (c.actionItems.followed && c.actionItems.items.isNotEmpty)
            ActionGroup(card: c, items: c.actionItems.items),
      ];
      _groups = groups;
      _status = groups.isEmpty ? ActionsStatus.empty : ActionsStatus.ready;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _status = ActionsStatus.error;
    }
    notifyListeners();
  }

  /// Tick a to-do off (or back on). Optimistic; reverts the group on failure.
  Future<void> toggle(String cardId, String itemId, bool done) async {
    final idx = _groups.indexWhere((g) => g.card.cardId == cardId);
    if (idx < 0) return;
    final before = _groups[idx];

    final updatedItems = [
      for (final it in before.items)
        it.id == itemId ? ActionItem(id: it.id, text: it.text, done: done) : it,
    ];
    final updatedActions =
        ActionItems(followed: true, items: updatedItems);
    _groups = [..._groups]
      ..[idx] = ActionGroup(
        card: before.card.copyWith(actionItems: updatedActions),
        items: updatedItems,
      );
    notifyListeners();

    try {
      await _repository.patchActionItems(cardId, updatedActions.toJson());
    } catch (_) {
      _groups = [..._groups]..[idx] = before; // revert
      notifyListeners();
    }
  }

  /// Stop following a reel's actions — drops it from the hub.
  Future<void> unfollow(String cardId) async {
    final idx = _groups.indexWhere((g) => g.card.cardId == cardId);
    if (idx < 0) return;
    final before = _groups[idx];
    _groups = [..._groups]..removeAt(idx);
    _status = _groups.isEmpty ? ActionsStatus.empty : ActionsStatus.ready;
    notifyListeners();
    try {
      await _repository.patchActionItems(
        cardId,
        ActionItems(followed: false, items: before.items).toJson(),
      );
    } catch (_) {
      _groups = [..._groups]..insert(idx, before); // revert
      _status = ActionsStatus.ready;
      notifyListeners();
    }
  }
}
