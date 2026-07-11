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
  static const _themeModeKey = 'theme_mode';
  static const _seenOnboardingKey = 'seen_onboarding';
  static const _userNameKey = 'user_name';
  static const _apiBaseUrlKey = 'api_base_url';
  static const _splitPaneFractionKey = 'split_pane_fraction';
  static const _localAiEnabledKey = 'local_ai_enabled';
  static const _hfTokenKey = 'hf_token';

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // --------------------------------------------------------------------- //
  // App preferences (presentation): theme mode + first-run gate.
  // --------------------------------------------------------------------- //

  /// 'system' | 'light' | 'dark'. Defaults to 'system'.
  String get themeMode => _prefs.getString(_themeModeKey) ?? 'system';
  Future<void> setThemeMode(String mode) => _prefs.setString(_themeModeKey, mode);

  bool get seenOnboarding => _prefs.getBool(_seenOnboardingKey) ?? false;
  Future<void> setSeenOnboarding(bool seen) =>
      _prefs.setBool(_seenOnboardingKey, seen);

  String? get userName => _prefs.getString(_userNameKey);
  Future<void> setUserName(String name) => _prefs.setString(_userNameKey, name);

  String? get apiBaseUrl => _prefs.getString(_apiBaseUrlKey);
  Future<void> setApiBaseUrl(String url) => _prefs.setString(_apiBaseUrlKey, url);

  /// On-device AI opt-in (V2). Model may be on disk while this is off.
  bool get localAiEnabled => _prefs.getBool(_localAiEnabledKey) ?? false;
  Future<void> setLocalAiEnabled(bool v) => _prefs.setBool(_localAiEnabledKey, v);

  /// HuggingFace token for the license-gated local model download.
  String? get hfToken {
    final t = _prefs.getString(_hfTokenKey);
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> setHfToken(String token) => _prefs.setString(_hfTokenKey, token);

  /// Split-pane divider position as a fraction of available width.
  /// Defaults to ~0.35 (≈420/1200).
  double get splitPaneFraction =>
      _prefs.getDouble(_splitPaneFractionKey) ?? 0.35;
  Future<void> setSplitPaneFraction(double v) =>
      _prefs.setDouble(_splitPaneFractionKey, v);

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
