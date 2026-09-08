import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cachy/data/services/api_client.dart';

void main() {
  test('friendly messages never leak bodies or tracebacks', () {
    expect(ApiException(500, '{"detail":"X","traceback":"Trace..."}').friendlyMessage,
        'Something went wrong on our side. Try again in a moment.');
    expect(ApiException(429, '{"error":"quota"}').friendlyMessage,
        "You've hit today's limit. It resets at midnight UTC.");
    expect(ApiException(401, 'x').friendlyMessage,
        'Session expired — please sign in again.');
    expect(ApiException(404, 'x').friendlyMessage,
        "That card isn't there anymore.");
    for (final code in [400, 401, 404, 429, 500, 503]) {
      final msg = ApiException(code, 'traceback secret').friendlyMessage;
      expect(msg.contains('traceback'), isFalse);
      expect(msg.contains('secret'), isFalse);
    }
  });

  test('friendlyError blames the connection only for transport failures', () {
    // What package:http actually throws when the request never lands: a dead
    // socket on mobile, a rejected `fetch` on web — both ClientException.
    expect(friendlyError(http.ClientException('Connection refused')),
        "Can't reach Cachy. Check your connection.");
    expect(friendlyError(TimeoutException('timed out')),
        "Can't reach Cachy. Check your connection.");
  });

  test('friendlyError does not blame the connection for decode failures', () {
    // Regression guard: a malformed-but-received response is our bug, not the
    // user's network. Reporting it as a connection problem sent debugging of a
    // server-side 500 down the wrong path entirely.
    for (final e in <Object>[
      FormatException('Unexpected character'),
      TypeError(),
      ArgumentError('bad field'),
    ]) {
      expect(friendlyError(e), 'Something went wrong loading that. Try again.');
    }
  });

  test('isOffline separates transport failures from everything else', () {
    expect(isOffline(http.ClientException('boom')), isTrue);
    expect(isOffline(TimeoutException('boom')), isTrue);
    expect(isOffline(ApiException(500, 'x')), isFalse);
    expect(isOffline(FormatException('x')), isFalse);
  });
}
