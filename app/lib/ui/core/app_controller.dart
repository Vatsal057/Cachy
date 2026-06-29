/// App-wide presentation state: theme mode (System/Light/Dark) and the first-run
/// onboarding gate. Backed by [LocalStore] so choices persist across launches.
/// Lives in the UI layer (not data) because it owns no contract data — just how
/// the app presents itself.
library;

import 'package:flutter/material.dart';

import '../../data/services/local_store.dart';

class AppController extends ChangeNotifier {
  AppController(this._store) : _themeMode = _decode(_store.themeMode);

  final LocalStore _store;

  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  bool get seenOnboarding => _store.seenOnboarding;
  String? get userName => _store.userName;
  bool get hasUserName => (_store.userName ?? '').isNotEmpty;

  Future<void> setUserName(String name) async {
    await _store.setUserName(name.trim());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _store.setThemeMode(_encode(mode));
  }

  Future<void> completeOnboarding() => _store.setSeenOnboarding(true);

  static ThemeMode _decode(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
