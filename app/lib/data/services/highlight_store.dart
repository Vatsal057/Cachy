library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/highlight.dart';

class HighlightStore extends ChangeNotifier {
  HighlightStore._(this._prefs) {
    _load();
  }

  static const _key = 'highlights_v1';

  final SharedPreferences _prefs;
  List<Highlight> _highlights = [];

  List<Highlight> get highlights => List.unmodifiable(_highlights);

  static Future<HighlightStore> open() async =>
      HighlightStore._(await SharedPreferences.getInstance());

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      _highlights = (jsonDecode(raw) as List)
          .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _highlights = [];
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _key,
      jsonEncode(_highlights.map((h) => h.toJson()).toList()),
    );
  }

  Future<void> add(Highlight h) async {
    _highlights.insert(0, h);
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _highlights.removeWhere((h) => h.id == id);
    await _persist();
    notifyListeners();
  }
}
