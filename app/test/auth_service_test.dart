import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cachy/data/services/auth_service.dart';

/// Deterministic in-memory AuthService for widget/unit tests.
class FakeAuthService implements AuthService {
  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();
  String tokenValue = 'fake-token';

  @override
  Stream<AuthUser?> get userChanges => _controller.stream;
  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInAnonymously() async {
    _user = const AuthUser(uid: 'anon-1', isAnonymous: true);
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    // Linking keeps the uid when the current user is anonymous.
    final uid = _user?.isAnonymous == true ? _user!.uid : 'google-1';
    _user = AuthUser(uid: uid, isAnonymous: false, email: 'a@b.c', displayName: 'A');
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _user == null ? null : tokenValue;

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

void main() {
  test('google sign-in after anonymous keeps the uid (link semantics)', () async {
    final auth = FakeAuthService();
    final anon = await auth.signInAnonymously();
    final linked = await auth.signInWithGoogle();
    expect(linked.uid, anon.uid);
    expect(linked.isAnonymous, isFalse);
  });

  test('no token when signed out', () async {
    final auth = FakeAuthService();
    expect(await auth.idToken(), isNull);
    await auth.signInAnonymously();
    expect(await auth.idToken(), 'fake-token');
  });
}
