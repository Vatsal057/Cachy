import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cachy/data/repositories/card_repository.dart';
import 'package:cachy/data/services/api_client.dart';
import 'package:cachy/data/services/local_store.dart';
import 'package:cachy/ui/features/library/view_models/library_view_model.dart';

/// Real repository driven by a MockClient that "naps" (throws) a fixed number
/// of times before answering — exactly the sleeping-HF-Space cold start.
Future<LibraryViewModel> _vm(int naps, {int status = 200}) async {
  SharedPreferences.setMockInitialValues({}); // empty cache => list() rethrows
  final store = await LocalStore.open();
  var calls = 0;
  final mock = MockClient((req) async {
    calls++;
    if (calls <= naps) {
      if (status == 200) throw http.ClientException('nap');
      return http.Response('waking', status);
    }
    return http.Response('[]', 200);
  });
  final api = ApiClient(baseUrl: 'http://x', client: mock);
  final repo = CardRepository(api: api, store: store);
  return LibraryViewModel(repository: repo, wakeRetryDelay: Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connection nap enters waking state, then recovers', () async {
    final vm = await _vm(2);
    final seen = <LibraryStatus>[];
    vm.addListener(() => seen.add(vm.status));
    await vm.load();
    expect(seen, contains(LibraryStatus.waking));
    expect(vm.status, LibraryStatus.empty);
  });

  test('503 while waking is retried too', () async {
    final vm = await _vm(2, status: 503);
    await vm.load();
    expect(vm.status, LibraryStatus.empty);
  });

  test('persistent failure lands on error after max attempts', () async {
    final vm = await _vm(99);
    await vm.load();
    expect(vm.status, LibraryStatus.error);
  });
}
