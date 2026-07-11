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
}
