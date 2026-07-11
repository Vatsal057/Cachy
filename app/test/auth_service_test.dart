import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

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
