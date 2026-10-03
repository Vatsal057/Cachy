/// Cachy ID auth (username + password, no email): register/login against the
/// backend `/id/*` endpoints. The returned JWT is the API bearer token and —
/// while an ID session exists — is preferred over the Firebase ID token (see
/// the combined tokenProvider in main.dart). The JWT's uid IS the backend
/// owner_id, so everything downstream works unchanged.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_store.dart';

class IdAuthException implements Exception {
  IdAuthException(this.message);
  final String message;
  @override
  String toString() => 'IdAuthException: $message';
}

/// Result of registration — the recovery code is shown to the user exactly
/// once and never returned again.
class IdRegistration {
  const IdRegistration({required this.recoveryCode});
  final String recoveryCode;
}

class IdAuthService extends ChangeNotifier {
  IdAuthService({required String Function() baseUrlOf, required LocalStore store})
      : _baseUrlOf = baseUrlOf,
        _store = store;

  final String Function() _baseUrlOf;
  final LocalStore _store;
  final http.Client _client = http.Client();

  String? get username => _store.idUsername;
  String? get token => _store.idToken;

  /// Null when there is no session OR the JWT has expired (30-day lifetime).
  /// The login gate treats an expired session as signed out, and the API
  /// tokenProvider falls back to Firebase instead of sending a dead token.
  String? get validToken {
    final t = token;
    if (t == null || (username ?? '').isEmpty || _isExpired(t)) return null;
    return t;
  }

  bool get isSignedIn => validToken != null;

  /// Unverified `exp` peek — only used to decide signed-in state, never for
  /// access control (the server verifies the signature).
  bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      ));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return true;
      return DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 >= exp;
    } catch (_) {
      return true;
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('${_baseUrlOf()}$path');
    late final http.Response resp;
    try {
      resp = await _client
          .post(uri,
              headers: {
                'content-type': 'application/json',
                ...?headers,
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw IdAuthException("Can't reach Cachy. Check your connection.");
    }
    Map<String, dynamic> decoded = const {};
    if (resp.body.isNotEmpty) {
      final d = jsonDecode(resp.body);
      if (d is Map<String, dynamic>) decoded = d;
    }
    if (resp.statusCode >= 400) {
      throw IdAuthException(_friendly(resp.statusCode, decoded));
    }
    return decoded;
  }

  /// Server `detail` strings for 422s are our own validation messages, safe
  /// to show. Everything else maps to a canned message — raw bodies never
  /// reach the UI (same rule as ApiException).
  String _friendly(int status, Map<String, dynamic> decoded) {
    final detail = decoded['detail'];
    switch (status) {
      case 401:
        return 'Wrong ID or password.';
      case 404:
        return "This account doesn't have a Cachy ID yet.";
      case 409:
        return 'That ID is taken. Try another.';
      case 422:
        return detail is String && detail.isNotEmpty
            ? detail
            : "That didn't work. Check the form and try again.";
      case 423:
        return detail is String && detail.isNotEmpty
            ? 'Locked: $detail'
            : 'Too many attempts. Try again later.';
      case 429:
        return 'Too many attempts. Slow down and try again.';
      case 503:
        return 'Cachy ID login is not set up on this server yet.';
      default:
        return "That didn't work. Try again.";
    }
  }

  Future<void> _saveSession(Map<String, dynamic> json) async {
    await _store.setIdToken(json['token'] as String);
    await _store.setIdUsername(json['username'] as String);
    notifyListeners();
  }

  /// Create a brand-new Cachy ID. Returns the recovery code — the caller MUST
  /// display it with a save-it-or-lose-it warning.
  Future<IdRegistration> register({
    required String username,
    required String password,
  }) async {
    final json = await _post('/id/register', {
      'username': username.trim(),
      'password': password,
    });
    await _saveSession(json);
    return IdRegistration(recoveryCode: json['recovery_code'] as String);
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final json = await _post('/id/login', {
      'username': username.trim(),
      'password': password,
    });
    await _saveSession(json);
  }

  /// Claim a Cachy ID onto the current Firebase account (Google/anonymous).
  /// Afterwards the same library is reachable via Google OR the ID — both
  /// resolve to the Firebase uid. [firebaseToken] is the caller's current
  /// Firebase ID token.
  Future<IdRegistration> link({
    required String username,
    required String password,
    required String firebaseToken,
  }) async {
    final json = await _post(
      '/id/link',
      {'username': username.trim(), 'password': password},
      headers: {'authorization': 'Bearer $firebaseToken'},
    );
    await _saveSession(json);
    return IdRegistration(recoveryCode: json['recovery_code'] as String);
  }

  Future<bool> usernameAvailable(String username) async {
    final u = username.trim();
    if (u.isEmpty) return false;
    final uri = Uri.parse('${_baseUrlOf()}/id/available')
        .replace(queryParameters: {'username': u});
    try {
      final resp =
          await _client.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final d = jsonDecode(resp.body);
      return d is Map && d['available'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final t = token;
    if (t == null) throw IdAuthException('Not signed in with a Cachy ID.');
    await _post(
      '/id/change-password',
      {'current_password': currentPassword, 'new_password': newPassword},
      headers: {'authorization': 'Bearer $t'},
    );
  }

  /// Reset via recovery code. Signs the user in on success.
  Future<void> resetPassword({
    required String username,
    required String recoveryCode,
    required String newPassword,
  }) async {
    final json = await _post('/id/reset', {
      'username': username.trim(),
      'recovery_code': recoveryCode.trim(),
      'new_password': newPassword,
    });
    await _saveSession(json);
  }

  Future<void> signOut() async {
    await _store.clearIdSession();
    notifyListeners();
  }
}
