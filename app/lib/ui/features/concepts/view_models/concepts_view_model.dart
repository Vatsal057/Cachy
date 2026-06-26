/// Concepts state (MVVM). Loads deduplicated concept entries from the
/// repository. Flat list — no type sectioning. Mirrors CatalogViewModel.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/concept.dart';

enum ConceptsStatus { idle, loading, ready, error, empty }

class ConceptsViewModel extends ChangeNotifier {
  ConceptsViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

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
