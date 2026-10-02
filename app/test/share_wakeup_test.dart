import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cachy/data/repositories/card_repository.dart';
import 'package:cachy/data/services/api_client.dart';
import 'package:cachy/data/services/local_store.dart';
import 'package:cachy/ui/features/share/view_models/share_view_model.dart';

Future<ShareViewModel> _vm(int naps, {int status = 200}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  var calls = 0;
  final mock = MockClient((req) async {
    calls++;
    if (calls <= naps) {
      if (status == 200) throw http.ClientException('nap');
      return http.Response('{"detail": "waking"}', status);
    }
    return http.Response(
      '{"card_id": "test-card-1", "state": "queued", "cached": false}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final api = ApiClient(baseUrl: 'http://x', client: mock);
  final repo = CardRepository(api: api, store: store);
  return ShareViewModel(repository: repo, wakeRetryDelay: Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('503 during cold-start enters waking state, then recovers and processes', () async {
    final vm = await _vm(2, status: 503);
    final seen = <ShareStatus>[];
    vm.addListener(() => seen.add(vm.status));

    final cardId = await vm.submit('https://instagram.com/reel/xyz123');

    expect(seen, contains(ShareStatus.waking));
    expect(vm.status, ShareStatus.processing);
    expect(cardId, 'test-card-1');
  });

  test('502 during cold-start is also retried and succeeds', () async {
    final vm = await _vm(1, status: 502);
    final seen = <ShareStatus>[];
    vm.addListener(() => seen.add(vm.status));

    final cardId = await vm.submit('https://instagram.com/reel/xyz123');

    expect(seen, contains(ShareStatus.waking));
    expect(vm.status, ShareStatus.processing);
    expect(cardId, 'test-card-1');
  });

  test('socket nap/offline during cold-start enters waking state and recovers', () async {
    final vm = await _vm(2);
    final seen = <ShareStatus>[];
    vm.addListener(() => seen.add(vm.status));

    final cardId = await vm.submit('https://instagram.com/reel/xyz123');

    expect(seen, contains(ShareStatus.waking));
    expect(vm.status, ShareStatus.processing);
    expect(cardId, 'test-card-1');
  });

  test('persistent 503 lands on failed with server message after max attempts', () async {
    final vm = await _vm(99, status: 503);
    final seen = <ShareStatus>[];
    vm.addListener(() => seen.add(vm.status));

    final cardId = await vm.submit('https://instagram.com/reel/xyz123');

    expect(cardId, isNull);
    expect(vm.status, ShareStatus.failed);
    expect(vm.failureReason, 'Something went wrong on our side. Try again in a moment.');
  });

  test('persistent network disconnect lands on queuedOffline after max attempts', () async {
    final vm = await _vm(99);
    final seen = <ShareStatus>[];
    vm.addListener(() => seen.add(vm.status));

    final cardId = await vm.submit('https://instagram.com/reel/xyz123');

    expect(cardId, isNull);
    expect(vm.status, ShareStatus.queuedOffline);
  });
}
