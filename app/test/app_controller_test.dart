import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cachy/data/services/id_auth_service.dart';
import 'package:cachy/data/services/local_store.dart';
import 'package:cachy/ui/core/app_controller.dart';

import 'fakes.dart';

IdAuthService _idAuth(LocalStore store) =>
    IdAuthService(baseUrlOf: () => 'http://localhost', store: store);

/// Unsigned JWT-shaped token; only the `exp` claim matters to the client,
/// which peeks at it (unverified) to decide signed-in state.
String _fakeJwt({bool expired = false}) {
  String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  final exp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 +
      (expired ? -3600 : 3600);
  return "${b64('{"alg":"HS256"}')}.${b64('{"sub":"id_x","exp":$exp}')}.sig";
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logout signs out and wipes user + offline card cache', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final auth = FakeAuthService();
    final idAuth = _idAuth(store);
    await auth.signInWithGoogle();
    await store.setUserName('Vats');
    await store.setSeenOnboarding(true);
    await store.cacheCard('c1', {'id': 'c1'});
    await store.setIdToken(_fakeJwt());
    await store.setIdUsername('vats');
    expect(idAuth.isSignedIn, isTrue);

    final app = AppController(store, auth, idAuth);
    await app.logout();

    expect(auth.currentUser, isNull);
    expect(store.userName, isNull);
    expect(store.idToken, isNull,
        reason: 'ID session must not survive logout');
    expect(store.idUsername, isNull);
    expect(idAuth.isSignedIn, isFalse);
    expect(store.cachedCardIds(), isEmpty,
        reason: 'next account on this device must not see the old library');
  });

  test('needsLogin is false with only a Cachy ID session', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setSeenOnboarding(true);
    await store.setIdToken(_fakeJwt());
    await store.setIdUsername('vats');

    final app = AppController(store, FakeAuthService(), _idAuth(store));
    expect(app.authUser, isNull);
    expect(app.needsLogin, isFalse,
        reason: 'a Cachy ID session is an identity for the login gate');
  });

  test('expired ID token counts as signed out', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setSeenOnboarding(true);
    await store.setIdToken(_fakeJwt(expired: true));
    await store.setIdUsername('vats');

    final idAuth = _idAuth(store);
    expect(idAuth.isSignedIn, isFalse);
    expect(idAuth.validToken, isNull);
    final app = AppController(store, FakeAuthService(), idAuth);
    expect(app.needsLogin, isTrue);
  });

  test('needsLogin is true with no identity at all', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setSeenOnboarding(true);

    final app = AppController(store, FakeAuthService(), _idAuth(store));
    expect(app.needsLogin, isTrue);
  });
}
