# UI Trust & Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four P1 trust leaks from the 2026-07-10 critique (fake cache-clear, dead Move-to-Folder, raw errors, cold-start cliff) plus the P2 polish items (reduced motion, onboarding brand pass, bounce easing).

**Architecture:** Pure Flutter changes, independent of the auth plans. Error mapping happens once in `ApiException`; move-to-folder reuses the existing `/collections/cards/{id}/move` endpoint and `ApiClient.moveCardToCollection`; cold-start becomes a distinct library/share status driven by retry-with-backoff in the repository layer.

**Tech Stack:** Flutter, provider, flutter_animate, flutter_test.

## Global Constraints

- Spec: "UI trust & polish fixes" section of `docs/superpowers/specs/2026-07-10-public-distribution-auth-quotas-design.md`; critique snapshot `.impeccable/critique/2026-07-10T11-11-16Z__app-lib.md`.
- Brand rules: all type through `brand.dart` tokens (no direct GoogleFonts outside it), motion 150–260ms ease-out, no bounce/overshoot, glass tokens shared.
- Never surface `e.toString()`, `ApiException(...)` bodies, or server tracebacks in UI copy.
- `cd app && flutter test && flutter analyze` after every task.
- No commits unless the user has granted it in-session; Commit steps are conditional on that.

---

### Task 1: Real "Clear offline cache"

**Files:**
- Modify: `app/lib/data/services/local_store.dart`
- Modify: `app/lib/ui/features/profile/views/profile_screen.dart:251-256`
- Create: `app/test/local_store_test.dart`

**Interfaces:**
- Produces: `Future<int> LocalStore.clearCardCache()` — removes every cached card + index, returns removed count.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cachy/data/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearCardCache removes all cached cards and the index', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.cacheCard('c1', {'id': 'c1'});
    await store.cacheCard('c2', {'id': 'c2'});
    expect(store.cachedCardIds(), hasLength(2));

    final removed = await store.clearCardCache();
    expect(removed, 2);
    expect(store.cachedCardIds(), isEmpty);
    expect(store.readCard('c1'), isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure** — `cd app && flutter test test/local_store_test.dart` — Expected: FAIL, `clearCardCache` undefined.

- [ ] **Step 3: Implement**

`local_store.dart`, in the Card cache section:

```dart
  /// Remove every cached card and the index. Returns how many were removed.
  Future<int> clearCardCache() async {
    final ids = cachedCardIds();
    for (final id in ids) {
      await _prefs.remove('$_cardPrefix$id');
    }
    await _prefs.remove(_indexKey);
    return ids.length;
  }
```

`profile_screen.dart` `_confirmClear`, replace the lying success block:

```dart
    if (ok == true && mounted) {
      final removed = await context.read<LocalStore>().clearCardCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(removed == 0
              ? 'Nothing cached yet'
              : 'Cleared $removed offline ${removed == 1 ? 'card' : 'cards'}'),
        ));
      }
    }
```

If `LocalStore` isn't in the provider graph, expose it via `CardRepository` (e.g. `context.read<CardRepository>().store.clearCardCache()`) — check how the repository holds it and use the existing path; do not add a new provider if one route already exists.

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze` — Expected: PASS.

- [ ] **Step 5: Commit** — `fix: Clear offline cache actually clears (and reports the count)`

---

### Task 2: Friendly error mapping at the ApiException boundary

**Files:**
- Modify: `app/lib/data/services/api_client.dart` (ApiException gains `friendlyMessage`)
- Modify: `app/lib/ui/features/actions/view_models/actions_view_model.dart:73` and every VM assigning `e.toString()` to a user-visible error field (grep `toString()` under `app/lib/ui/**/view_models/` and `app/lib/ui/**/views/` for snackbar/error uses)
- Create: `app/test/api_exception_test.dart`

**Interfaces:**
- Produces: `String ApiException.friendlyMessage` and `String friendlyError(Object e)` helper (top-level in api_client.dart) — the ONLY strings VMs may store in user-visible error fields.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, `friendlyMessage` undefined.

- [ ] **Step 3: Implement**

In `api_client.dart`:

```dart
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message; // raw body — for logs only, never for UI

  /// What users see. Raw bodies (which may include server details) never
  /// leave the data layer.
  String get friendlyMessage => switch (statusCode) {
        401 || 403 => 'Session expired — please sign in again.',
        404 => "That card isn't there anymore.",
        429 => "You've hit today's limit. It resets at midnight UTC.",
        >= 500 => 'Something went wrong on our side. Try again in a moment.',
        _ => "That didn't work. Try again.",
      };

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// UI-safe message for any thrown object.
String friendlyError(Object e) => switch (e) {
      ApiException api => api.friendlyMessage,
      _ => "Can't reach Cachy. Check your connection.",
    };
```

Swap every user-visible assignment, e.g. `actions_view_model.dart:73`: `_error = e.toString();` → `_error = friendlyError(e);` (keep a `debugPrint('$e')` or logger call if the original context logged). Do the same wherever `SnackBar(content: Text('...$error'))` shows a VM error built from `toString()` (library bulk delete already shows `vm.error` — that's now friendly automatically).

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze`; then `grep -rn "toString()" app/lib/ui | grep -i "error\|snack"` — Expected: tests PASS; grep only shows non-UI/logging uses.

- [ ] **Step 5: Commit** — `fix: friendly error copy everywhere — raw exceptions never reach UI`

---

### Task 3: Cold-start "Waking Cachy up" state

**Files:**
- Modify: `app/lib/ui/features/library/view_models/library_view_model.dart` (new status + retry loop)
- Modify: `app/lib/ui/features/library/views/library_screen.dart` (`_body` renders the waking state)
- Create: `app/test/library_wakeup_test.dart`

**Interfaces:**
- Consumes: `friendlyError` (Task 2).
- Produces: `LibraryStatus.waking` enum value; `LibraryViewModel.load()` retries up to 6 times / 10s apart on connection-shaped failures before settling on `error`; `int get wakeAttempt`.

- [ ] **Step 1: Write the failing test**

Read `library_view_model.dart` first for its repository interface, then adapt this shape (fake repo that fails N times then succeeds):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cachy/ui/features/library/view_models/library_view_model.dart';

import 'fakes.dart'; // FakeCardRepository: fails with SocketException-ish twice, then returns []

void main() {
  test('connection failure enters waking state, then recovers', () async {
    final repo = FakeCardRepository(failuresBeforeSuccess: 2);
    final vm = LibraryViewModel(repository: repo, wakeRetryDelay: Duration.zero);
    final seen = <LibraryStatus>[];
    vm.addListener(() => seen.add(vm.status));
    await vm.load();
    expect(seen, contains(LibraryStatus.waking));
    expect(vm.status, anyOf(LibraryStatus.empty, LibraryStatus.ready));
  });

  test('persistent failure lands on error after max attempts', () async {
    final repo = FakeCardRepository(failuresBeforeSuccess: 99);
    final vm = LibraryViewModel(repository: repo, wakeRetryDelay: Duration.zero);
    await vm.load();
    expect(vm.status, LibraryStatus.error);
  });
}
```

Write `FakeCardRepository` in `app/test/fakes.dart` implementing only the members `LibraryViewModel` actually calls (check the VM; typically `list()` and the offline flag).

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, `LibraryStatus.waking` undefined.

- [ ] **Step 3: Implement**

In `library_view_model.dart`: add `waking` to `LibraryStatus`; constructor param `this.wakeRetryDelay = const Duration(seconds: 10)`; wrap the load's fetch:

```dart
  static const _maxWakeAttempts = 6;
  int _wakeAttempt = 0;
  int get wakeAttempt => _wakeAttempt;

  Future<List<model.Card>> _fetchWithWake() async {
    for (_wakeAttempt = 0; ; _wakeAttempt++) {
      try {
        return await repository.list();
      } catch (e) {
        final connectionShaped = e is! ApiException; // socket/timeouts, not HTTP
        if (!connectionShaped || _wakeAttempt >= _maxWakeAttempts) rethrow;
        _status = LibraryStatus.waking;
        notifyListeners();
        await Future<void>.delayed(wakeRetryDelay);
      }
    }
  }
```

and call `_fetchWithWake()` where `load()` currently calls the repository (keep the existing offline-cache fallback: if the cache has cards while waking fails, show cached cards with the offline chip instead — reuse the current offline path).

`library_screen.dart` `_body`, add before the error case:

```dart
      case LibraryStatus.waking:
        return _scrollable(
          EmptyState(
            showGlyph: true,
            title: 'Waking Cachy up…',
            message: 'The free server naps when idle. First load takes about '
                '30 seconds — your library is on its way.',
          ),
        );
```

- [ ] **Step 4: Share flow cold-start copy**

The share pipeline already degrades to `ShareStatus.queuedOffline` on connection failure (`share_screen.dart:129-149`) — that state doubles as the cold-start path for captures. Update its copy so a sleeping server doesn't read as "you're offline":

- Title: `'Saved offline'` → `'Saved — will process shortly'`
- Body: `"We'll process this reel as soon as you're back online."` → `"We'll process this as soon as Cachy is reachable — the free server can take ~30s to wake up."`

- [ ] **Step 5: Run** — `cd app && flutter test && flutter analyze` — Expected: PASS.

- [ ] **Step 6: Commit** — `feat: cold-start waking state with auto-retry instead of instant failure`

---

### Task 4: Move to Folder — replace both stubs

**Files:**
- Modify: `app/lib/ui/features/library/view_models/library_view_model.dart` (`bulkMove`)
- Create: `app/lib/ui/features/collections/views/folder_picker_sheet.dart`
- Modify: `app/lib/ui/core/home_shell.dart:483-485` and `app/lib/ui/features/library/views/library_screen.dart:315-319` (call the picker; also dedupe `_confirmBulkDelete` into one shared helper `confirmBulkDelete(BuildContext, LibraryViewModel)` living in `library_view_model.dart`'s file or a small `library_dialogs.dart`)
- Create: `app/test/bulk_move_test.dart`

**Interfaces:**
- Consumes: `ApiClient.moveCardToCollection` + `listCollections`/`createCollection` (already exist).
- Produces: `Future<void> LibraryViewModel.bulkMove(String? collectionId)` — moves all selected cards, clears selection, refreshes; `Future<void> showFolderPicker(BuildContext context, LibraryViewModel vm)` — adaptive sheet listing folders + "New folder…" row.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cachy/ui/features/library/view_models/library_view_model.dart';

import 'fakes.dart'; // FakeCardRepository records moveCardToCollection calls

void main() {
  test('bulkMove moves every selected card and clears selection', () async {
    final repo = FakeCardRepository(cards: ['a', 'b', 'c']);
    final vm = LibraryViewModel(repository: repo);
    await vm.load();
    vm.toggleSelected('a');
    vm.toggleSelected('c');

    await vm.bulkMove('folder-1');

    expect(repo.moves, {'a': 'folder-1', 'c': 'folder-1'});
    expect(vm.selectionActive, isFalse);
  });
}
```

Match the VM's real selection API names (`toggleSelected`/`selectionActive` — read the VM first and mirror; extend `FakeCardRepository` with a `moves` map).

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, `bulkMove` undefined.

- [ ] **Step 3: Implement**

`library_view_model.dart`:

```dart
  /// Move every selected card into [collectionId] (null = remove from folders).
  Future<void> bulkMove(String? collectionId) async {
    final ids = List<String>.from(selectedIds);
    try {
      for (final id in ids) {
        await repository.moveCardToCollection(id, collectionId);
      }
      clearSelection();
      await refresh();
    } catch (e) {
      _error = friendlyError(e);
      notifyListeners();
    }
  }
```

(If the repository lacks `moveCardToCollection`, add a one-line passthrough to `api.moveCardToCollection`.)

`folder_picker_sheet.dart` — adaptive modal (reuse `showAdaptiveModal`) listing collections from `ApiClient.listCollections()`, one `ListTile` per folder (folder icon, name), a divider, then "New folder…" which prompts a name via `AlertDialog` + `createCollection`, then moves. Selecting any row: `await vm.bulkMove(entry.id); Navigator.pop(ctx);` with a confirmation snackbar `Moved N cards to "<name>"`.

Replace both stubs: `onMoveToFolder: () => showFolderPicker(context, vm)`. Delete the duplicated `_confirmBulkDelete` from `home_shell.dart` and `library_screen.dart`; both call the new shared `confirmBulkDelete`.

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze`; then `grep -rn "coming soon" app/lib` — Expected: tests PASS, grep empty.

- [ ] **Step 5: Commit** — `feat: bulk Move to Folder (replaces coming-soon stubs); dedupe bulk-delete dialog`

---

### Task 5: Reduced motion honored everywhere

**Files:**
- Modify: `app/lib/ui/core/theme.dart` (motion gate helper)
- Modify: all 16 `.animate()` call sites + `AnimatedScale` durations (grep `\.animate(` and `Motion.fast`/`Motion.spring` under `app/lib`)
- Create: `app/test/reduced_motion_test.dart`

**Interfaces:**
- Produces: `extension MotionGate on BuildContext { bool get motionEnabled; Duration gated(Duration d); }` in theme.dart.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cachy/ui/core/theme.dart';

void main() {
  testWidgets('motionEnabled follows MediaQuery.disableAnimations', (tester) async {
    late bool enabled;
    late Duration gated;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (context) {
        enabled = context.motionEnabled;
        gated = context.gated(Motion.medium);
        return const SizedBox();
      }),
    ));
    expect(enabled, isFalse);
    expect(gated, Duration.zero);
  });
}
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, extension undefined.

- [ ] **Step 3: Implement**

`theme.dart`:

```dart
/// Reduced-motion gate: animations collapse to zero duration when the OS asks.
extension MotionGate on BuildContext {
  bool get motionEnabled => !MediaQuery.of(this).disableAnimations;
  Duration gated(Duration d) => motionEnabled ? d : Duration.zero;
}
```

Then sweep call sites:
- flutter_animate chains: `.animate()` → wrap the whole chain: `motionEnabled ? child.animate()...fadeIn(...) : child` OR simpler global switch in `main.dart` root build: `Animate.restartOnHotReload = true;` is unrelated — instead set `child.animate(autoPlay: context.motionEnabled)` where supported, else the conditional wrap. Use the conditional wrap; it's explicit and testable.
- `AnimatedScale`/`AnimatedContainer` durations: `duration: Motion.fast` → `duration: context.gated(Motion.fast)`.
- Also change `Motion.spring = Curves.easeOutBack` → `Curves.easeOutCubic` (bounce ban) and in `app/web/index.html` replace `cubic-bezier(0.34, 1.56, 0.64, 1)` with `cubic-bezier(0.22, 1, 0.36, 1)`.

- [ ] **Step 4: Run** — `cd app && flutter test && flutter analyze`; then `grep -rn "easeOutBack" app/` — Expected: PASS, grep empty.

- [ ] **Step 5: Commit** — `fix: honor reduced-motion everywhere; retire bounce easing`

---

### Task 6: Onboarding brand pass + stale comments

**Files:**
- Modify: `app/lib/ui/features/onboarding/views/onboarding_screen.dart`
- Modify: `app/lib/ui/features/onboarding/views/name_screen.dart`
- Modify: `app/lib/ui/features/library/views/library_screen.dart:1-7` (doc comment)

**Interfaces:** none new — visual conformance only.

- [ ] **Step 1: Apply the brand pass**

`onboarding_screen.dart`:
- `_LogoBadge`: replace the lightning-in-a-box with the real mark: `Row(children: [const CachyGlyph(size: 30), const SizedBox(width: 10), Text('cachy', style: Brand.wordmarkStyle(20, color: scheme.onSurface))])` — delete the Container/lightning entirely.
- Every `GoogleFonts.fraunces(... fontWeight: FontWeight.w800 ...)` headline → `theme.textTheme.displaySmall` / `displayMedium` (Brand's w600 serif), keeping the accent-colored `TextSpan`s; drop the glow `Shadow` on "Captured." (calm over clever). Remove the `google_fonts` import.
- File doc comment: delete "adapted from Insightr (demo)" wording — describe what it is now.

`name_screen.dart`: headline `GoogleFonts.fraunces(...)` → `theme.textTheme.displaySmall`; remove the glow shadow and the `google_fonts` import.

`library_screen.dart` header comment: "Two segments — Cards and To-do" → "Three segments — Cards, Concepts, Catalog".

- [ ] **Step 2: Verify**

Run: `cd app && flutter analyze && flutter test` — Expected: clean, all PASS. Then `grep -rn "GoogleFonts" app/lib | grep -v core/brand.dart` — Expected: empty.

- [ ] **Step 3: Visual check** — `cd app && flutter run -d chrome` , clear browser storage to re-trigger onboarding; confirm the glyph mark, w600 headlines, no glow.

- [ ] **Step 4: Commit** — `polish: onboarding on-brand (glyph mark, w600 serif, no glow); fix stale comments`
