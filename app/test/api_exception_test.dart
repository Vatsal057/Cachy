import 'package:flutter_test/flutter_test.dart';
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

  test('friendlyError handles non-Api exceptions', () {
    expect(friendlyError(Exception('SocketException: conn refused')),
        "Can't reach Cachy. Check your connection.");
  });
}
