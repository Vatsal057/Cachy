/// Catalog state (MVVM). Loads aggregated artifacts from the repository, groups
/// them by type for sectioned display, and supports a type filter + delete.
library;

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/artifact.dart';

enum CatalogStatus { idle, loading, ready, error, empty }

/// One display section: a type and its entries.
class CatalogSection {
  const CatalogSection(this.type, this.entries);
  final ArtifactType type;
  final List<CatalogEntry> entries;
}

class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({required CardRepository repository})
      : _repository = repository;

  final CardRepository _repository;

  CatalogStatus _status = CatalogStatus.idle;
  CatalogStatus get status => _status;

  List<CatalogEntry> _entries = const [];

  ArtifactType? _filter;
  ArtifactType? get filter => _filter;

  String? _error;
  String? get error => _error;

  /// Dashboard counts over the WHOLE catalog (ignore the active filter).
  int get entryCount => _entries.length;
  int get typeCount => {for (final e in _entries) e.type}.length;
  int get referencedCardCount =>
      {for (final e in _entries) ...e.sourceCardIds}.length;

  /// The type filters that actually have entries, in catalog order — so the
  /// filter bar never offers an empty category.
  List<ArtifactType> get availableTypes {
    final seen = <ArtifactType>{for (final e in _entries) e.type};
    return ArtifactType.values.where(seen.contains).toList();
  }

  /// Entries grouped into sections (respecting the active filter).
  List<CatalogSection> get sections {
    final visible = _filter == null
        ? _entries
        : _entries.where((e) => e.type == _filter).toList();
    final out = <CatalogSection>[];
    for (final type in ArtifactType.values) {
      final group = visible.where((e) => e.type == type).toList();
      if (group.isNotEmpty) out.add(CatalogSection(type, group));
    }
    return out;
  }

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) {
      _status = CatalogStatus.loading;
      notifyListeners();
    }
    try {
      _entries = await _repository.catalog();
      _status =
          _entries.isEmpty ? CatalogStatus.empty : CatalogStatus.ready;
      _error = null;
    } catch (e) {
      _error = '$e';
      _status = _entries.isEmpty ? CatalogStatus.error : CatalogStatus.ready;
    }
    notifyListeners();
  }

  Future<void> refresh() => load(showSpinner: false);

  void setFilter(ArtifactType? type) {
    if (_filter == type) return;
    _filter = type;
    notifyListeners();
  }

  Future<void> delete(String artifactId) async {
    _entries = _entries.where((e) => e.id != artifactId).toList();
    if (_entries.isEmpty) _status = CatalogStatus.empty;
    notifyListeners();
    try {
      await _repository.deleteCatalogEntry(artifactId);
    } catch (_) {
      await load(showSpinner: false); // resync on failure
    }
  }
}
