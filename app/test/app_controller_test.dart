import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cachy/data/services/local_store.dart';
import 'package:cachy/ui/core/app_controller.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logout signs out and wipes user + offline card cache', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final auth = FakeAuthService();
    await auth.signInWithGoogle();
    await store.setUserName('Vats');
    await store.setSeenOnboarding(true);
    await store.cacheCard('c1', {'id': 'c1'});

    final app = AppController(store, auth);
    await app.logout();

    expect(auth.currentUser, isNull);
    expect(store.userName, isNull);
    expect(store.cachedCardIds(), isEmpty,
        reason: 'next account on this device must not see the old library');
  });
}
