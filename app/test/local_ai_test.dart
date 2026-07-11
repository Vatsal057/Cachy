/// On-device AI: JSON guard, fake-service state machine, and the degrade-path
/// upgrade flow (bundle -> local structuring -> upload) with fakes.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cachy/data/repositories/card_repository.dart';
import 'package:cachy/data/services/api_client.dart';
import 'package:cachy/data/services/local_ai/local_ai_service.dart';
import 'package:cachy/data/services/local_store.dart';

// ---------------------------------------------------------------------------
// Fake service (mirrors the interface the app injects everywhere)
// ---------------------------------------------------------------------------

class FakeLocalAiService extends LocalAiService {
  FakeLocalAiService({
    LocalAiPhase phase = LocalAiPhase.ready,
    bool enabled = true,
    this.result,
  })  : _phase = phase,
        _enabled = enabled;

  LocalAiPhase _phase;
  bool _enabled;

  /// What structureBundle returns (null simulates model failure).
  Map<String, dynamic>? result;
  int structureCalls = 0;
  String? lastBundle;

  @override
  LocalAiStatus get status => LocalAiStatus(_phase);

  @override
  bool get enabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
  }

  @override
  Future<void> saveHfToken(String token) async {}

  @override
  Future<void> download() async {
    _phase = LocalAiPhase.downloading;
    notifyListeners();
    _phase = LocalAiPhase.ready;
    notifyListeners();
  }

  @override
  Future<void> delete() async {
    _phase = LocalAiPhase.notInstalled;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>?> structureBundle(
    String bundle, {
    String transcript = '',
    String caption = '',
  }) async {
    structureCalls++;
    lastBundle = bundle;
    return result;
  }
}

const _validCard = {
  'base': {
    'one_liner': 'Quick pasta technique',
    'tldr': 'Salt and finish in pan.',
    'content_type': 'recipe',
    'tags': ['cooking'],
  },
  'blocks': [
    {
      'type': 'checklist',
      'items': [
        {'text': 'salt water', 'checked': false},
      ],
    },
  ],
};

Future<CardRepository> _repoWith(MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final api = ApiClient(baseUrl: 'http://test', client: client, store: store);
  return CardRepository(api: api, store: store);
}

void main() {
  group('parseModelCardJson', () {
    test('accepts clean JSON', () {
      final out = parseModelCardJson(jsonEncode(_validCard));
      expect(out, isNotNull);
      expect((out!['base'] as Map)['one_liner'], 'Quick pasta technique');
    });

    test('strips markdown fences and surrounding prose', () {
      final raw = 'Sure! Here is the card:\n```json\n${jsonEncode(_validCard)}\n```';
      expect(parseModelCardJson(raw), isNotNull);
    });

    test('rejects non-JSON, empty blocks, and missing base', () {
      expect(parseModelCardJson('not json at all'), isNull);
      expect(parseModelCardJson('{"base": {"one_liner": "x"}, "blocks": []}'), isNull);
      expect(parseModelCardJson('{"blocks": [{"type": "paragraph"}]}'), isNull);
      expect(
        parseModelCardJson('{"base": {"one_liner": ""}, "blocks": [{"t": 1}]}'),
        isNull,
      );
    });
  });

  group('FakeLocalAiService state machine', () {
    test('download moves notInstalled -> ready; delete reverses', () async {
      final ai = FakeLocalAiService(phase: LocalAiPhase.notInstalled);
      expect(ai.status.phase, LocalAiPhase.notInstalled);
      expect(ai.canStructure, isFalse);
      await ai.download();
      expect(ai.status.phase, LocalAiPhase.ready);
      expect(ai.canStructure, isTrue);
      await ai.delete();
      expect(ai.status.phase, LocalAiPhase.notInstalled);
    });

    test('disabled blocks structuring even when ready', () async {
      final ai = FakeLocalAiService(enabled: false);
      expect(ai.status.phase, LocalAiPhase.ready);
      expect(ai.canStructure, isFalse);
    });
  });

  group('upgradeOnDevice', () {
    test('happy path: fetch bundle, structure, upload, cache', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path == '/cards/c1/bundle') {
          return http.Response(
            jsonEncode({'bundle': 'B', 'transcript': 'T', 'caption': 'C'}),
            200,
          );
        }
        if (req.url.path == '/cards/c1/structure') {
          expect(jsonDecode(req.body), _validCard);
          return http.Response(
            jsonEncode({
              'card_id': 'c1',
              'state': 'ready',
              'base': _validCard['base'],
              'blocks': _validCard['blocks'],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final repo = await _repoWith(client);
      final ai = FakeLocalAiService(result: Map.of(_validCard));

      final upgraded = await repo.upgradeOnDevice('c1', ai);

      expect(upgraded, isTrue);
      expect(ai.structureCalls, 1);
      expect(ai.lastBundle, 'B');
      expect(calls, contains('GET /cards/c1/bundle'));
      expect(calls, contains('POST /cards/c1/structure'));
    });

    test('model returns null -> no upload, paragraph kept', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        return http.Response(
          jsonEncode({'bundle': 'B', 'transcript': '', 'caption': ''}),
          200,
        );
      });
      final repo = await _repoWith(client);
      final ai = FakeLocalAiService(result: null);

      expect(await repo.upgradeOnDevice('c1', ai), isFalse);
      expect(calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    test('no stored bundle (404) -> false, model never invoked', () async {
      final client = MockClient((req) async => http.Response('{}', 404));
      final repo = await _repoWith(client);
      final ai = FakeLocalAiService(result: Map.of(_validCard));

      expect(await repo.upgradeOnDevice('c1', ai), isFalse);
      expect(ai.structureCalls, 0);
    });

    test('model not ready -> false immediately', () async {
      final client = MockClient((req) async => http.Response('{}', 200));
      final repo = await _repoWith(client);
      final ai = FakeLocalAiService(phase: LocalAiPhase.notInstalled);

      expect(await repo.upgradeOnDevice('c1', ai), isFalse);
      expect(ai.structureCalls, 0);
    });

    test('server 422 on upload -> false, no crash', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/cards/c1/bundle') {
          return http.Response(
            jsonEncode({'bundle': 'B', 'transcript': '', 'caption': ''}),
            200,
          );
        }
        return http.Response(jsonEncode({'detail': 'invalid'}), 422);
      });
      final repo = await _repoWith(client);
      final ai = FakeLocalAiService(result: Map.of(_validCard));

      expect(await repo.upgradeOnDevice('c1', ai), isFalse);
    });
  });
}
