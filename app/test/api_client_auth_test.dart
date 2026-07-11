import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cachy/data/services/api_client.dart';

void main() {
  test('attaches bearer token to requests', () async {
    String? seenAuth;
    final mock = MockClient((req) async {
      seenAuth = req.headers['authorization'];
      return http.Response(jsonEncode([]), 200);
    });
    final api = ApiClient(
      baseUrl: 'http://x',
      client: mock,
      tokenProvider: ({bool forceRefresh = false}) async => 'tok-1',
    );
    await api.listCards();
    expect(seenAuth, 'Bearer tok-1');
  });

  test('one forced-refresh retry on 401', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      if (req.headers['authorization'] == 'Bearer stale') {
        return http.Response('unauthorized', 401);
      }
      return http.Response(jsonEncode([]), 200);
    });
    var fresh = false;
    final api = ApiClient(
      baseUrl: 'http://x',
      client: mock,
      tokenProvider: ({bool forceRefresh = false}) async {
        if (forceRefresh) fresh = true;
        return fresh ? 'fresh' : 'stale';
      },
    );
    final cards = await api.listCards();
    expect(cards, isEmpty);
    expect(calls, 2); // 401 then success — exactly one retry
  });
}
