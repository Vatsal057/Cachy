/// Library grid state (MVVM). Loads cards from the repository, supports
/// pull-to-refresh, filtering by state, and delete. Falls back to cache offline.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart';
import '../../../../domain/models/enums.dart';

enum LibraryStatus { idle, loading, ready, error, empty }

class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({required CardRepository repository})
      : _repository = repository {
    _repository.addListener(_onRepoChange);
  }

  final CardRepository _repository;

  void _onRepoChange() {
    if (_status != LibraryStatus.loading) {
      load(showSpinner: false);
    }
  }

  LibraryStatus _status = LibraryStatus.idle;
  LibraryStatus get status => _status;

  List<Card> _cards = const [];
  List<Card> get cards => List.unmodifiable(_cards);

  CardState? _filter;
  CardState? get filter => _filter;

  // --- tag filter (auto-tags, client-side over loaded cards) -------------- //
  String? _tagFilter;
  String? get tagFilter => _tagFilter;

  /// Tags that appear on 2+ cards, sorted by frequency. Single-occurrence tags
  /// are too specific to be useful as filters.
  List<String> get availableTags {
    final counts = <String, int>{};
    for (final c in _cards) {
      for (final t in c.base.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  void setTagFilter(String? tag) {
    _tagFilter = _tagFilter == tag ? null : tag;
    notifyListeners();
  }

  // --- desktop split-pane selection --------------------------------------- //
  String? _selectedCardId;
  String? get selectedCardId => _selectedCardId;

  void selectCard(String? cardId) {
    if (_selectedCardId == cardId) return;
    _selectedCardId = cardId;
    notifyListeners();
  }

  // --- multi-selection (Ctrl/Cmd-click, Shift range, mobile long-press) --- //
  final Set<String> _selectedIds = {};
  bool _selectionMode = false; // mobile long-press mode
  String? _selectionAnchorId; // anchor for Shift range-select

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedCount => _selectedIds.length;
  bool get selectionActive => _selectedIds.isNotEmpty;
  bool get selectionMode => _selectionMode;
  bool isSelected(String cardId) => _selectedIds.contains(cardId);

  /// Flip membership of [cardId] in the selection and set it as the anchor.
  void toggleSelection(String cardId) {
    if (_selectedIds.contains(cardId)) {
      _selectedIds.remove(cardId);
    } else {
      _selectedIds.add(cardId);
    }
    _selectionAnchorId = cardId;
    notifyListeners();
  }

  /// Select every card whose index in [visibleCards] lies within the inclusive
  /// range between the anchor and [toCardId] (union with the current
  /// selection). Falls back to [toggleSelection] when no valid anchor exists.
  void selectRange(String toCardId) {
    final anchor = _selectionAnchorId;
    if (anchor == null) {
      toggleSelection(toCardId);
      return;
    }
    final visible = visibleCards;
    final anchorIndex = visible.indexWhere((c) => c.cardId == anchor);
    final toIndex = visible.indexWhere((c) => c.cardId == toCardId);
    if (anchorIndex < 0 || toIndex < 0) {
      toggleSelection(toCardId);
      return;
    }
    final start = anchorIndex < toIndex ? anchorIndex : toIndex;
    final end = anchorIndex < toIndex ? toIndex : anchorIndex;
    for (var i = start; i <= end; i++) {
      _selectedIds.add(visible[i].cardId);
    }
    notifyListeners();
  }

  /// Enter mobile selection mode with [cardId] selected as the anchor.
  void enterSelectionMode(String cardId) {
    _selectionMode = true;
    _selectedIds.add(cardId);
    _selectionAnchorId = cardId;
    notifyListeners();
  }

  /// Clear the selection and exit selection mode.
  void clearSelection() {
    _selectedIds.clear();
    _selectionMode = false;
    _selectionAnchorId = null;
    notifyListeners();
  }

  String? _error;
  String? get error => _error;

  bool _offline = false;
  bool get offline => _offline;

  // --- search (full-text, /search endpoint) ------------------------------ //
  String _query = '';
  String get query => _query;
  bool get searching => _query.trim().isNotEmpty;

  List<Card> _results = const [];
  List<Card> get results => List.unmodifiable(_results);

  bool _searchBusy = false;
  bool get searchBusy => _searchBusy;

  Timer? _debounce;

  /// Cards to render: search hits when a query is active, else the library
  /// narrowed by the active tag filter (if any).
  List<Card> get visibleCards {
    if (searching) return _results;
    if (_tagFilter == null) return cards;
    return _cards.where((c) => c.base.tags.contains(_tagFilter)).toList();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _results = const [];
      _searchBusy = false;
      notifyListeners();
      return;
    }
    _searchBusy = true;
    notifyListeners();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(value));
  }

  void clearSearch() {
    _debounce?.cancel();
    _query = '';
    _results = const [];
    _searchBusy = false;
    notifyListeners();
  }

  Future<void> _runSearch(String value) async {
    try {
      final hits = await _repository.search(value.trim());
      if (value != _query) return; // a newer keystroke superseded this one
      _results = hits;
    } catch (_) {
      _results = const [];
    }
    _searchBusy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepoChange);
    _debounce?.cancel();
    super.dispose();
  }

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
    if (_selectedCardId == cardId) _selectedCardId = null;
    notifyListeners();
    try {
      await _repository.delete(cardId);
    } catch (_) {
      await load(showSpinner: false); // resync on failure
    }
  }

  /// Delete every currently-selected card. Optimistically removes the cards
  /// from the grid and clears the selection, then deletes each id through the
  /// repository. If any deletion fails, the card list and selection are
  /// restored exactly to their pre-operation values and an error is surfaced
  /// (Requirement 8.9).
  Future<void> bulkDelete() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    // Snapshot pre-operation state for exact restore-on-failure (Property 12).
    final cardsSnapshot = List<Card>.from(_cards);
    final selectionSnapshot = Set<String>.from(_selectedIds);
    final selectionModeSnapshot = _selectionMode;
    final anchorSnapshot = _selectionAnchorId;
    final statusSnapshot = _status;

    final idSet = ids.toSet();

    // Optimistically remove the selected cards and clear the selection.
    _cards = _cards.where((c) => !idSet.contains(c.cardId)).toList();
    if (_cards.isEmpty && _status == LibraryStatus.ready) {
      _status = LibraryStatus.empty;
    }
    if (_selectedCardId != null && idSet.contains(_selectedCardId)) {
      _selectedCardId = null;
    }
    _selectedIds.clear();
    _selectionMode = false;
    _selectionAnchorId = null;
    _error = null;
    notifyListeners();

    try {
      for (final id in ids) {
        await _repository.delete(id);
      }
    } catch (e) {
      // Restore card list and selection exactly to pre-operation values.
      _cards = cardsSnapshot;
      _status = statusSnapshot;
      _selectedIds
        ..clear()
        ..addAll(selectionSnapshot);
      _selectionMode = selectionModeSnapshot;
      _selectionAnchorId = anchorSnapshot;
      _error = '$e';
      notifyListeners();
    }
  }
}
