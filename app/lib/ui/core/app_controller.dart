/// App-wide presentation state: theme mode (System/Light/Dark) and the first-run
/// onboarding gate. Backed by [LocalStore] so choices persist across launches.
/// Lives in the UI layer (not data) because it owns no contract data — just how
/// the app presents itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/auth_service.dart';
import '../../data/services/id_auth_service.dart';
import '../../data/services/local_store.dart';

class AppController extends ChangeNotifier {
  AppController(this._store, this._auth, this._idAuth)
      : _themeMode = _decode(_store.themeMode),
        _authUser = _auth.currentUser {
    _authSub = _auth.userChanges.listen((u) {
      _authUser = u;
      notifyListeners();
    });
    _idAuth.addListener(_onIdAuthChanged);
  }

  final LocalStore _store;
  final AuthService _auth;
  final IdAuthService _idAuth;
  late final StreamSubscription<AuthUser?> _authSub;

  void _onIdAuthChanged() => notifyListeners();

  AuthUser? _authUser;

  /// The current Firebase identity (uid = backend owner_id), or null when
  /// signed out. Drives the login gate and the profile account section.
  AuthUser? get authUser => _authUser;

  /// True once the user has cleared onboarding but has no identity yet — the
  /// one moment [RootGate] shows the login screen. Identity is the Firebase
  /// uid (Google or anonymous) or a Cachy ID session.
  bool get needsLogin =>
      seenOnboarding && _authUser == null && !_idAuth.isSignedIn;

  Future<void> signInWithGoogle({
    Future<void> Function(String guestIdToken)? mergeGuestData,
  }) =>
      _auth.signInWithGoogle(mergeGuestData: mergeGuestData);
  Future<void> continueAnonymously() => _auth.signInAnonymously();

  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  bool get seenOnboarding => _store.seenOnboarding;
  String? get userName => _store.userName;
  bool get hasUserName => (_store.userName ?? '').isNotEmpty;

  double get splitPaneFraction => _store.splitPaneFraction;

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

  /// Signs out of Firebase and clears the Cachy ID session, the user's name +
  /// onboarding flag so [RootGate] redirects back to the name-entry screen on
  /// the next render. Also wipes the offline card cache so the next account
  /// on this device can't read the previous user's library.
  Future<void> logout() async {
    await _auth.signOut();
    await _idAuth.signOut();
    await _store.clearUser();
    await _store.clearCardCache();
    notifyListeners();
  }

  Future<void> setSplitPaneFraction(double fraction) async {
    final clamped = fraction.clamp(0.25, 0.5);
    await _store.setSplitPaneFraction(clamped);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub.cancel();
    _idAuth.removeListener(_onIdAuthChanged);
    super.dispose();
  }

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
