/// Local persistence for offline reading and the offline share queue (docs/06).
/// Cards are cached as raw JSON keyed by id; the share queue holds URLs that were
/// shared while offline, flushed when the backend is reachable again.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _cardPrefix = 'card:';
  static const _indexKey = 'card_index';
  static const _shareQueueKey = 'share_queue';

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // --------------------------------------------------------------------- //
  // Card cache
  // --------------------------------------------------------------------- //

  Future<void> cacheCard(String cardId, Map<String, dynamic> json) async {
    await _prefs.setString('$_cardPrefix$cardId', jsonEncode(json));
    final index = cachedCardIds().toSet()..add(cardId);
    await _prefs.setStringList(_indexKey, index.toList());
  }

  Map<String, dynamic>? readCard(String cardId) {
    final raw = _prefs.getString('$_cardPrefix$cardId');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  List<String> cachedCardIds() => _prefs.getStringList(_indexKey) ?? const [];

  List<Map<String, dynamic>> readAllCards() {
    final out = <Map<String, dynamic>>[];
    for (final id in cachedCardIds()) {
      final json = readCard(id);
      if (json != null) out.add(json);
    }
    return out;
  }

  Future<void> removeCard(String cardId) async {
    await _prefs.remove('$_cardPrefix$cardId');
    final index = cachedCardIds().toSet()..remove(cardId);
    await _prefs.setStringList(_indexKey, index.toList());
  }

  // --------------------------------------------------------------------- //
  // Offline share queue
  // --------------------------------------------------------------------- //

  Future<void> enqueueShare(String url) async {
    final queue = pendingShares().toList();
    if (!queue.contains(url)) {
      queue.add(url);
      await _prefs.setStringList(_shareQueueKey, queue);
    }
  }

  List<String> pendingShares() => _prefs.getStringList(_shareQueueKey) ?? const [];

  Future<void> removeShare(String url) async {
    final queue = pendingShares().toList()..remove(url);
    await _prefs.setStringList(_shareQueueKey, queue);
  }
}
