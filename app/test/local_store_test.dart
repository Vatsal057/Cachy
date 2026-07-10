import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cachy/data/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearCardCache removes all cached cards and the index', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.cacheCard('c1', {'id': 'c1'});
    await store.cacheCard('c2', {'id': 'c2'});
    expect(store.cachedCardIds(), hasLength(2));

    final removed = await store.clearCardCache();
    expect(removed, 2);
    expect(store.cachedCardIds(), isEmpty);
    expect(store.readCard('c1'), isNull);
  });
}
