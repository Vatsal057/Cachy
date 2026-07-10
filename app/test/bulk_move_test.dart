import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cachy/data/repositories/card_repository.dart';
import 'package:cachy/data/services/api_client.dart';
import 'package:cachy/data/services/local_store.dart';
import 'package:cachy/ui/features/library/view_models/library_view_model.dart';

/// Builds a VM over a real repo whose MockClient serves the given cards and
/// records every move POST as cardId -> collection_id.
Future<(LibraryViewModel, Map<String, String?>)> _vm(List<String> ids) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  final moves = <String, String?>{};
  final mock = MockClient((req) async {
    final path = req.url.path;
    if (path == '/cards') {
      return http.Response(
        jsonEncode([for (final id in ids) {'card_id': id, 'state': 'ready'}]),
        200,
      );
    }
    final move = RegExp(r'^/collections/cards/(.+)/move$').firstMatch(path);
    if (move != null) {
      moves[move.group(1)!] = jsonDecode(req.body)['collection_id'] as String?;
      return http.Response('{}', 200);
    }
    return http.Response('[]', 200);
  });
  final api = ApiClient(baseUrl: 'http://x', client: mock);
  final repo = CardRepository(api: api, store: store);
  return (LibraryViewModel(repository: repo), moves);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bulkMove moves every selected card and clears selection', () async {
    final (vm, moves) = await _vm(['a', 'b', 'c']);
    await vm.load();
    vm.toggleSelection('a');
    vm.toggleSelection('c');
    expect(vm.selectionActive, isTrue);

    await vm.bulkMove('folder-1');

    expect(moves, {'a': 'folder-1', 'c': 'folder-1'});
    expect(vm.selectionActive, isFalse);
  });
}
