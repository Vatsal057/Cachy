# Flutter Auth Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Firebase identity in the app — anonymous sign-in after onboarding+name, optional Google login screen ("Or use without login…"), bearer-token transport, real sign-out, quota meter, and legacy-library claim.

**Architecture:** An `AuthService` wraps FirebaseAuth (anonymous start, Google link/sign-in, token access). `ApiClient` gains a token provider injected at construction and attaches `Authorization: Bearer` to every request with one 401-retry-after-refresh. `RootGate` gains a login step between onboarding/name and the shell. Profile gets an account section + quota meter.

**Tech Stack:** Flutter, firebase_core, firebase_auth, google_sign_in, provider, flutter_test with mocked services (no Firebase in unit tests).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-10-public-distribution-auth-quotas-design.md`. Backend plan (`2026-07-10-backend-auth-quotas.md`) must be deployed for end-to-end flows; unit tests here never hit the network.
- Login screen comes AFTER onboarding + name screen. Primary: "Continue with Google". Below, small quiet text: "Or use without login…". The typed name stays the greeting; uid is identity.
- Anonymous users see a persistent profile banner: "Your library isn't backed up — sign in with Google", plus warning copy that data may be lost.
- Dart style: provider/ChangeNotifier, business logic outside widgets, strict null safety, brand tokens from `brand.dart`/`theme.dart`.
- Run `cd app && flutter test` after every task; `flutter analyze` must stay clean.
- The user's standing rule: no commits unless asked in-session; Commit steps are conditional on that permission.

**One-time owner setup (NOT part of this plan; do first, manually):** create Firebase project → enable Anonymous + Google providers → `flutterfire configure` (writes `app/lib/firebase_options.dart` + `app/android/app/google-services.json`) → register release SHA-1 → set `FIREBASE_PROJECT_ID` on the HF Space. Tasks below assume `firebase_options.dart` exists.

---

### Task 1: AuthService — testable Firebase wrapper

**Files:**
- Modify: `app/pubspec.yaml` (add `firebase_core: ^3.6.0`, `firebase_auth: ^5.3.1`, `google_sign_in: ^6.2.1`)
- Create: `app/lib/data/services/auth_service.dart`
- Create: `app/test/auth_service_test.dart`
- Modify: `app/lib/main.dart` (Firebase.initializeApp before runApp)

**Interfaces:**
- Produces:

```dart
/// Wraps FirebaseAuth so the rest of the app never imports firebase directly
/// (and tests can fake it).
abstract class AuthService {
  Stream<AuthUser?> get userChanges;
  AuthUser? get currentUser;
  Future<AuthUser> signInAnonymously();
  Future<AuthUser> signInWithGoogle();   // links when currently anonymous
  Future<String?> idToken({bool forceRefresh = false});
  Future<void> signOut();
}

class AuthUser {
  const AuthUser({required this.uid, required this.isAnonymous, this.email, this.displayName, this.photoUrl});
  final String uid;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
  final String? photoUrl;
}
```

- [ ] **Step 1: Write the failing test** (against a `FakeAuthService` used by all later tests, plus the linking contract)

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cachy/data/services/auth_service.dart';

/// Deterministic in-memory AuthService for widget/unit tests.
class FakeAuthService implements AuthService {
  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();
  String tokenValue = 'fake-token';

  @override
  Stream<AuthUser?> get userChanges => _controller.stream;
  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInAnonymously() async {
    _user = const AuthUser(uid: 'anon-1', isAnonymous: true);
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    // Linking keeps the uid when the current user is anonymous.
    final uid = _user?.isAnonymous == true ? _user!.uid : 'google-1';
    _user = AuthUser(uid: uid, isAnonymous: false, email: 'a@b.c', displayName: 'A');
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _user == null ? null : tokenValue;

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

void main() {
  test('google sign-in after anonymous keeps the uid (link semantics)', () async {
    final auth = FakeAuthService();
    final anon = await auth.signInAnonymously();
    final linked = await auth.signInWithGoogle();
    expect(linked.uid, anon.uid);
    expect(linked.isAnonymous, isFalse);
  });

  test('no token when signed out', () async {
    final auth = FakeAuthService();
    expect(await auth.idToken(), isNull);
    await auth.signInAnonymously();
    expect(await auth.idToken(), 'fake-token');
  });
}
```

Save `FakeAuthService` in the test file now; Task 3 moves it to `app/test/fakes.dart` for reuse.

- [ ] **Step 2: Run to verify failure** — `cd app && flutter test test/auth_service_test.dart` — Expected: FAIL, `auth_service.dart` missing.

- [ ] **Step 3: Implement `auth_service.dart`**

```dart
/// Identity layer: Firebase anonymous-first with optional Google upgrade.
/// The uid is the backend `owner_id`; linking preserves it so no data moves.
library;

import 'package:firebase_auth/firebase_auth.dart' as fb;
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
  Future<AuthUser> signInWithGoogle();
  Future<String?> idToken({bool forceRefresh = false});
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb.FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _google = google ?? GoogleSignIn();

  final fb.FirebaseAuth _auth;
  final GoogleSignIn _google;

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
  Future<AuthUser> signInWithGoogle() async {
    final account = await _google.signIn();
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
        // Google account already has a Cachy identity — switch to it.
        cred = await _auth.signInWithCredential(credential);
      }
    } else {
      cred = await _auth.signInWithCredential(credential);
    }
    return _map(cred.user)!;
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) =>
      _auth.currentUser?.getIdToken(forceRefresh) ?? Future.value(null);

  @override
  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
```

`main.dart`: before `runApp`, add

```dart
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

with imports `package:firebase_core/firebase_core.dart` and `firebase_options.dart`; provide `AuthService` alongside the existing providers: `Provider<AuthService>(create: (_) => FirebaseAuthService())`.

- [ ] **Step 4: Run** — `cd app && flutter test test/auth_service_test.dart && flutter analyze` — Expected: PASS, no new analyzer issues.

- [ ] **Step 5: Commit** — `feat: AuthService — anonymous-first Firebase identity with Google linking`

---

### Task 2: Bearer token transport in ApiClient (with one 401 retry)

**Files:**
- Modify: `app/lib/data/services/api_client.dart`
- Create: `app/test/api_client_auth_test.dart`

**Interfaces:**
- Consumes: `AuthService.idToken` (Task 1).
- Produces: `ApiClient({..., Future<String?> Function({bool forceRefresh})? tokenProvider})`; private `Future<http.Response> _send(...)` used by all verbs; `_ownerHeader` and every `x-owner-id` reference deleted.

- [ ] **Step 1: Write the failing test** (MockClient counts auth headers + retry behavior)

```dart
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
```

- [ ] **Step 2: Run to verify failure** — `cd app && flutter test test/api_client_auth_test.dart` — Expected: FAIL, no `tokenProvider` parameter.

- [ ] **Step 3: Implement in `api_client.dart`**

Constructor gains `this.tokenProvider`; field `final Future<String?> Function({bool forceRefresh})? tokenProvider;`. Replace `_ownerHeader` with:

```dart
  Future<Map<String, String>> _authHeader({bool forceRefresh = false}) async {
    final token = await tokenProvider?.call(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) return const {};
    return {'authorization': 'Bearer $token'};
  }

  /// All verbs funnel through here: auth header + one refresh-retry on 401.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) go, {
    Map<String, String> extra = const {},
  }) async {
    var resp = await go({...extra, ...await _authHeader()});
    if (resp.statusCode == 401 && tokenProvider != null) {
      resp = await go({...extra, ...await _authHeader(forceRefresh: true)});
    }
    return resp;
  }
```

Then mechanically rewrite each call site, e.g.:

```dart
  Future<List<Card>> listCards({...}) async {
    final resp = await _send((h) => _client.get(_uri('/cards', {...}), headers: h));
    return _decodeList(resp).map(Card.fromJson).toList();
  }

  Future<CreateCardResult> createCard(String url) async {
    final resp = await _send(
      (h) => _client.post(_uri('/cards'), headers: h, body: jsonEncode({'url': url})),
      extra: const {'content-type': 'application/json'},
    );
    ...
  }
```

Apply to every method that used `_ownerHeader` (grep: `_ownerHeader` must return zero hits afterwards). `streamCard` (SSE): add the awaited auth header to `request.headers` before `_client.send(request)` (no retry loop needed — the reader screen re-subscribes on error). In `main.dart`/composition root, construct `ApiClient(..., tokenProvider: ({bool forceRefresh = false}) => context.read<AuthService>().idToken(forceRefresh: forceRefresh))` — wire via the existing repository setup (pass AuthService into wherever ApiClient is built today).

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: bearer-token transport with single 401 refresh-retry`

---

### Task 3: Login screen after onboarding + RootGate wiring

**Files:**
- Create: `app/lib/ui/features/onboarding/views/login_screen.dart`
- Modify: `app/lib/ui/core/root_gate.dart` (insert login step after name; read its current step logic first and mirror its pattern)
- Modify: `app/lib/ui/core/app_controller.dart` (expose `authUser`, `signInWithGoogle()`, `continueAnonymously()`, listening to `AuthService.userChanges`)
- Create: `app/test/fakes.dart` (move `FakeAuthService` here)
- Create: `app/test/login_screen_test.dart`

**Interfaces:**
- Consumes: `AuthService` (Task 1).
- Produces: `LoginScreen({required VoidCallback onDone})`; AppController: `AuthUser? get authUser`, `bool get needsLogin` (seen onboarding + has name + no firebase user), `Future<void> signInWithGoogle()`, `Future<void> continueAnonymously()`.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cachy/data/services/auth_service.dart';
import 'package:cachy/ui/features/onboarding/views/login_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets('login screen: Google primary, quiet anonymous path', (tester) async {
    final auth = FakeAuthService();
    var done = 0;
    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: MaterialApp(home: LoginScreen(onDone: () => done++)),
      ),
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Or use without login…'), findsOneWidget);

    await tester.tap(find.text('Or use without login…'));
    await tester.pumpAndSettle();
    expect(auth.currentUser?.isAnonymous, isTrue);
    expect(done, 1);
  });
}
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, `login_screen.dart` missing.

- [ ] **Step 3: Implement `login_screen.dart`**

Visual language mirrors `name_screen.dart` (same radial gradient scaffold, Fraunces headline via theme, `Brand` tokens — no direct GoogleFonts). Core structure:

```dart
/// Login gate, shown after onboarding + name. Google is primary; anonymous is
/// a quiet escape hatch with an honest data-loss caveat.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/auth_service.dart';
import '../../../core/brand.dart';
import '../../../core/widgets/responsive_center.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't sign in. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = context.read<AuthService>();
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: ResponsiveCenter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                const CachyGlyph(size: 56),
                const SizedBox(height: 32),
                Text('Keep your\nlibrary safe.',
                    style: theme.textTheme.displaySmall),
                const SizedBox(height: 16),
                Text(
                  'Sign in so your cards follow you to any device — and survive a reinstall.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant, height: 1.5),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(() async { await auth.signInWithGoogle(); }),
                  icon: const PhosphorIcon(PhosphorIconsRegular.googleLogo, size: 20),
                  label: const Text('Continue with Google'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => _run(() async { await auth.signInAnonymously(); }),
                    child: Text(
                      'Or use without login…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Without an account, your library lives only on this device.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

`app_controller.dart`: inject `AuthService`, subscribe to `userChanges` (notifyListeners), add the three members from Interfaces. `root_gate.dart`: current gate is onboarding → name → shell; make it onboarding → name → login → shell, keyed on `needsLogin` (a returning signed-in user skips the login screen because `currentUser != null`).

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: post-onboarding login screen (Google primary, anonymous quiet path)`

---

### Task 4: Profile account section — banner, real sign-out, quota meter, claim

**Files:**
- Modify: `app/lib/ui/features/profile/views/profile_screen.dart`
- Modify: `app/lib/data/services/api_client.dart` (+`me()` quota fetch, +`claim(name)`)
- Modify: `app/lib/ui/core/app_controller.dart` (`logout()` also calls `AuthService.signOut()`)
- Create: `app/test/profile_account_test.dart`

**Interfaces:**
- Consumes: `AuthService`, `AppController.authUser` (Task 3), backend `GET /me/quota` + `POST /auth/claim`.
- Produces: `ApiClient.quota() -> Future<QuotaStatus>` where

```dart
class QuotaStatus {
  const QuotaStatus({required this.cardsUsed, required this.cardsLimit, required this.chatUsed, required this.chatLimit});
  final int cardsUsed, cardsLimit, chatUsed, chatLimit;
}
```

and `ApiClient.claimLegacyLibrary(String name) -> Future<int>` (claimed row count; throws ApiException 409 when taken).

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, `quota`/`claimLegacyLibrary` undefined.

- [ ] **Step 3: Implement**

`api_client.dart` additions (using `_send` from Task 2):

```dart
class QuotaStatus {
  const QuotaStatus({required this.cardsUsed, required this.cardsLimit, required this.chatUsed, required this.chatLimit});
  final int cardsUsed;
  final int cardsLimit;
  final int chatUsed;
  final int chatLimit;
}

  Future<QuotaStatus> quota() async {
    final resp = await _send((h) => _client.get(_uri('/me/quota'), headers: h));
    final json = _decodeMap(resp);
    int pick(String kind, String field) =>
        ((json[kind] as Map<String, dynamic>?)?[field] as num?)?.toInt() ?? 0;
    return QuotaStatus(
      cardsUsed: pick('cards', 'used'),
      cardsLimit: pick('cards', 'limit'),
      chatUsed: pick('chat', 'used'),
      chatLimit: pick('chat', 'limit'),
    );
  }

  Future<int> claimLegacyLibrary(String name) async {
    final resp = await _send(
      (h) => _client.post(_uri('/auth/claim'), headers: h, body: jsonEncode({'name': name})),
      extra: const {'content-type': 'application/json'},
    );
    return (_decodeMap(resp)['claimed'] as num?)?.toInt() ?? 0;
  }
```

`profile_screen.dart` Account section replaces the current sign-out-only block:
- Signed-in (Google): row with photo/initial avatar, displayName, email; "Sign out" tile below (existing confirm dialog; copy updated to "Your cards stay safe in your account.").
- Anonymous: banner tile (primary-tinted container, not a snackbar): title "Your library isn't backed up", subtitle "Sign in with Google — if you uninstall or clear data, your cards are gone.", trailing FilledButton "Sign in" → `context.read<AppController>().signInWithGoogle()`; on success and when `LocalStore.userName` is set, offer the claim dialog: "Restore my old library" → `api.claimLegacyLibrary(name)`; on 409 show "That name was already claimed."
- Quota meter: under Library section, a `_Tile`-style row "AI usage today" with subtitle `"${q.cardsUsed}/${q.cardsLimit} cards · ${q.chatUsed}/${q.chatLimit} chats"`, loaded via `FutureBuilder(api.quota())`, hidden on error (quota is a nicety, never a blocker).
- `AppController.logout()`: call `await _auth.signOut()` in addition to the existing `LocalStore.clearUser()`.

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze` — Expected: PASS.

- [ ] **Step 5: Manual end-to-end check (requires deployed backend + Firebase setup)**

Run `cd app && flutter run -d chrome --dart-define=CACHY_API_BASE=http://localhost:8000` with the backend running and `FIREBASE_PROJECT_ID` set. Verify: onboarding → name → login screen appears once → "Or use without login…" enters the shell → profile shows the not-backed-up banner → Google sign-in links (library unchanged) → banner replaced by account row → sign out returns to onboarding gate.

- [ ] **Step 6: Commit** — `feat: profile account section — banner, quota meter, legacy claim, real sign-out`
