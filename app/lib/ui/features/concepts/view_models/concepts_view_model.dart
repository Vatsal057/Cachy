/// Concepts state (MVVM). Loads deduplicated concept entries from the
/// repository. Flat list — no type sectioning. Mirrors CatalogViewModel.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/concept.dart';
import '../../../core/safe_notifier.dart';

enum ConceptsStatus { idle, loading, ready, error, empty }

class ConceptsViewModel extends ChangeNotifier with SafeNotifier {
  ConceptsViewModel({required CardRepository repository})
      : _repository = repository {
    _repository.addListener(_onRepoChange);
  }

  final CardRepository _repository;

  void _onRepoChange() {
    if (_status != ConceptsStatus.loading) {
      load(showSpinner: false);
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _repository.removeListener(_onRepoChange);
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  ConceptsStatus _status = ConceptsStatus.idle;
  ConceptsStatus get status => _status;

  List<ConceptEntry> _entries = const [];
  List<ConceptEntry> get entries => List.unmodifiable(_entries);

  String? _error;
  String? get error => _error;

  int get entryCount => _entries.length;
  int get referencedCardCount =>
      {for (final e in _entries) ...e.sourceCardIds}.length;

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _status = ConceptsStatus.loading;
      notifyListeners();
    }
    try {
      _entries = await _repository.concepts();
      _status = _entries.isEmpty ? ConceptsStatus.empty : ConceptsStatus.ready;
      _error = null;
    } catch (e) {
      _error = '$e';
      _status = _entries.isEmpty ? ConceptsStatus.error : ConceptsStatus.ready;
    }
    notifyListeners();
  }

  Future<void> refresh() => load(showSpinner: false);

  Future<void> delete(String conceptId) async {
    _entries = _entries.where((e) => e.id != conceptId).toList();
    if (_entries.isEmpty) _status = ConceptsStatus.empty;
    notifyListeners();
    try {
      await _repository.deleteConcept(conceptId);
    } catch (_) {
      await load(showSpinner: false);
    }
  }
}
