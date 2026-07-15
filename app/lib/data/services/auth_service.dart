/// Identity layer: Firebase anonymous-first with optional Google upgrade.
/// The uid is the backend `owner_id`; linking preserves it so no data moves.
library;

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.isAnonymous,
    this.email,
    this.displayName,
    this.photoUrl,
  });
  final String uid;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final String? photoUrl;
}

abstract class AuthService {
  Stream<AuthUser?> get userChanges;
  AuthUser? get currentUser;
  Future<AuthUser> signInAnonymously();

  /// Sign in with Google. When the current session is an anonymous guest, the
  /// uid is linked (data stays put). If that Google account already has its own
  /// Cachy identity, linking is impossible, so we switch to it and — if
  /// [mergeGuestData] is provided — hand back the guest's ID token so the
  /// caller can fold the guest's server-side data into the account.
  Future<AuthUser> signInWithGoogle({
    Future<void> Function(String guestIdToken)? mergeGuestData,
  });

  Future<String?> idToken({bool forceRefresh = false});
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb.FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        // On web, `google_sign_in` asserts a client-id at construction and web
        // sign-in goes through Firebase's popup instead — so never build it there.
        _google = google ?? (kIsWeb ? null : GoogleSignIn());

  final fb.FirebaseAuth _auth;
  final GoogleSignIn? _google;

  AuthUser? _map(fb.User? u) => u == null
      ? null
      : AuthUser(
          uid: u.uid,
          isAnonymous: u.isAnonymous,
          email: u.email,
          displayName: u.displayName,
          photoUrl: u.photoURL,
        );

  @override
  Stream<AuthUser?> get userChanges => _auth.userChanges().map(_map);

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<AuthUser> signInAnonymously() async {
    final cred = await _auth.signInAnonymously();
    return _map(cred.user)!;
  }

  @override
  Future<AuthUser> signInWithGoogle({
    Future<void> Function(String guestIdToken)? mergeGuestData,
  }) async {
    // The `google_sign_in` plugin's imperative `signIn()` is unsupported on web
    // (throws UnimplementedError); Firebase's popup flow handles Google there.
    if (kIsWeb) return _signInWithGoogleWeb(mergeGuestData: mergeGuestData);

    final account = await _google!.signIn(); // non-null: web returns above
    if (account == null) throw fb.FirebaseAuthException(code: 'canceled');
    final gAuth = await account.authentication;
    final credential = fb.GoogleAuthProvider.credential(
      idToken: gAuth.idToken,
      accessToken: gAuth.accessToken,
    );
    final current = _auth.currentUser;
    fb.UserCredential cred;
    if (current != null && current.isAnonymous) {
      try {
        cred = await current.linkWithCredential(credential); // uid preserved
      } on fb.FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use') rethrow;
        // Google account already has a Cachy identity — linking is impossible.
        // Grab the guest's token before switching so its data can be merged,
        // then sign into the existing account.
        final guestToken = await current.getIdToken();
        cred = await _auth.signInWithCredential(credential);
        await _maybeMergeGuest(guestToken, mergeGuestData);
      }
    } else {
      cred = await _auth.signInWithCredential(credential);
    }
    return _map(cred.user)!;
  }

  /// Web variant: Firebase drives the OAuth popup directly, so no
  /// `google_sign_in` account/token round-trip is needed. Mirrors the mobile
  /// link-vs-switch semantics via `linkWithPopup` / `signInWithPopup`.
  Future<AuthUser> _signInWithGoogleWeb({
    Future<void> Function(String guestIdToken)? mergeGuestData,
  }) async {
    final provider = fb.GoogleAuthProvider();
    final current = _auth.currentUser;
    fb.UserCredential cred;
    if (current != null && current.isAnonymous) {
      try {
        cred = await current.linkWithPopup(provider); // uid preserved
      } on fb.FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use') rethrow;
        final resolved = e.credential;
        if (resolved == null) rethrow;
        final guestToken = await current.getIdToken();
        cred = await _auth.signInWithCredential(resolved);
        await _maybeMergeGuest(guestToken, mergeGuestData);
      }
    } else {
      cred = await _auth.signInWithPopup(provider);
    }
    return _map(cred.user)!;
  }

  /// Best-effort fold of a guest's server-side data into the account it just
  /// switched to. A failed merge must never block sign-in.
  Future<void> _maybeMergeGuest(
    String? guestToken,
    Future<void> Function(String guestIdToken)? mergeGuestData,
  ) async {
    if (guestToken == null || guestToken.isEmpty || mergeGuestData == null) {
      return;
    }
    try {
      await mergeGuestData(guestToken);
    } catch (_) {}
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) =>
      _auth.currentUser?.getIdToken(forceRefresh) ?? Future.value(null);

  @override
  Future<void> signOut() async {
    await _google?.signOut();
    await _auth.signOut();
  }
}
