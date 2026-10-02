import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cachy/data/services/api_client.dart';

void main() {
  test('quota() parses /me/quota', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/me/quota');
      return http.Response(jsonEncode({
        'cards': {'used': 3, 'limit': 10},
        'chat': {'used': 1, 'limit': 30},
        'resets_at': '2026-07-11T00:00:00+00:00',
      }), 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: mock);
    final q = await api.quota();
    expect(q.cardsUsed, 3);
    expect(q.cardsLimit, 10);
  });

  test('claimLegacyLibrary returns claimed count', () async {
    final mock = MockClient((req) async => http.Response(jsonEncode({'claimed': 7}), 200));
    final api = ApiClient(baseUrl: 'http://x', client: mock);
    expect(await api.claimLegacyLibrary('Vatsal'), 7);
  });

  test('getInstagramLink returns parsed handle', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/me/instagram');
      expect(req.method, 'GET');
      return http.Response(jsonEncode({'ig_username': 'vatsal_dev'}), 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: mock);
    expect(await api.getInstagramLink(), 'vatsal_dev');
  });

  test('linkInstagram posts handle and returns normalized username', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/me/instagram');
      expect(req.method, 'POST');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['ig_username'], '@Vatsal_Dev');
      return http.Response(jsonEncode({'ig_username': 'vatsal_dev'}), 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: mock);
    expect(await api.linkInstagram('@Vatsal_Dev'), 'vatsal_dev');
  });

  test('unlinkInstagram issues DELETE /me/instagram', () async {
    var deleted = false;
    final mock = MockClient((req) async {
      expect(req.url.path, '/me/instagram');
      expect(req.method, 'DELETE');
      deleted = true;
      return http.Response(jsonEncode({'unlinked': true}), 200);
    });
    final api = ApiClient(baseUrl: 'http://x', client: mock);
    await api.unlinkInstagram();
    expect(deleted, isTrue);
  });
}
