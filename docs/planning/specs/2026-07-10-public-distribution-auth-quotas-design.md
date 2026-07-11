# Cachy Public Distribution: Auth, Quotas, Backend Hardening

**Date:** 2026-07-10
**Status:** Approved
**Scope:** V1 for distributing Cachy to non-technical users (GitHub APK + hosted web) while shared free-tier AI keys survive. On-device model, Play Store, payments, email auth are explicitly out of scope (V2+).

## Problem

Cachy today identifies users by a self-declared name sent as the `x-owner-id` header. The backend trusts it blindly:

- Anyone can read any user's library by guessing a name (`curl -H "x-owner-id: Vatsal"`).
- Name collisions silently merge libraries.
- Per-user quotas are unenforceable (attacker rotates header values), so shared free-tier API keys (Cerebras, Groq, Gemini pool) cannot be protected.
- `/admin/stats`, `/debug/jobs`, `/debug/kill_stuck` are unauthenticated; 500 responses leak tracebacks; CORS is `*`.

## Decision Summary

| Decision | Choice |
|---|---|
| Identity | Firebase Auth: anonymous sign-in on first launch, optional upgrade to Google Sign-In via `linkWithCredential` (same uid, data preserved) |
| Token transport | `Authorization: Bearer <Firebase ID token>` on every API request |
| Backend verification | `firebase-admin` `verify_id_token`; `owner_id` = verified `uid` |
| Quota policy | Per-user daily quotas; past card quota → degrade to existing paragraph-fallback path (card still saves), never hard-fail |
| Quota storage | `usage(owner_id, day, kind, count)` table in existing DB (SQLite / Neon) |
| Abuse defense | Per-IP daily cap on card creation (same usage table, keyed by IP) |
| Admin/debug routes | Gated by `X-Admin-Token` matching env secret |
| Migration | Temporary `/auth/claim` endpoint: authed user claims rows whose `owner_id` equals their old display name, first-claim-wins; removed after ~1 month |

### Why Firebase Auth (alternatives considered)

- **Firebase Auth (chosen):** anonymous→Google linking is a native feature; free unlimited for anonymous + Google providers; backend verification is one call. Google lock-in acceptable — stack is already Google-centric (Gemini keys, Android target).
- **Supabase Auth:** comparable free tier but anonymous→permanent linking is manual, and it adds a new vendor.
- **Hand-rolled JWT (Google Identity Services direct):** no new dependency but we own token issuance, refresh, revocation — auth bugs become breaches. Rejected.

## Architecture

### 1. Client auth flow (Flutter)

- Packages: `firebase_auth`, `google_sign_in` (+ `firebase_core`).
- **First launch:** onboarding (including the existing name screen) runs first; the login screen comes after it:
  - Primary button: "Continue with Google" (`signInWithCredential`).
  - Below, small quiet text link: "Or use without login…" → `signInAnonymously()`.
  - Either path yields a stable Firebase `uid`.
  - The name entered during onboarding is kept for both paths — it stays the display/greeting name (local + stored server-side as profile field), but is no longer the identity; `uid` is.
- **Anonymous upgrade:** Profile screen shows a persistent banner while anonymous: "Your library isn't backed up — sign in with Google." Tapping runs `linkWithCredential(GoogleAuthProvider credential)` — uid unchanged, no data migration.
- **Warning copy:** anonymous users are told data may be lost if the app is uninstalled / data cleared.
- Display name: everyone types a name during onboarding (kept as greeting/profile name); Google linking may additionally surface the Google profile name/avatar. Name is never identity.

### 2. Token transport (ApiClient)

- `_ownerHeader` in `app/lib/data/services/api_client.dart` is replaced by an auth header provider: every request attaches `Authorization: Bearer <ID token>` from `FirebaseAuth.instance.currentUser.getIdToken()` (SDK caches + auto-refreshes; cheap to call per request).
- SSE stream request (`streamCard`) attaches the same header.

### 3. Backend verification (FastAPI)

- New dependency `get_owner(request) -> str`:
  - Extracts bearer token, verifies via `firebase_admin.auth.verify_id_token` (public JWKS; needs only the Firebase project ID configured via env).
  - Returns `uid`; raises 401 on missing/invalid/expired token.
- Every route currently reading `x-owner-id` swaps to `Depends(get_owner)`. The `owner_id` column semantics are unchanged — only its source becomes trustworthy.
- `x-owner-id` header support is removed entirely (no fallback); the legacy name only survives as the body parameter of the temporary `/auth/claim` endpoint below.

### 4. Migration of existing name-based data

- `POST /auth/claim {name: str}` (authenticated): re-points all rows with `owner_id == name` to the caller's `uid`, if that name has not already been claimed. First-claim-wins; a `claims` table records name→uid to prevent double claims.
- Client: after first sign-in, if a legacy local `userName` exists, offer "Restore my old library" which calls this endpoint.
- Endpoint is temporary; delete after ~1 month.

### 5. Quotas

- Table: `usage(owner_id TEXT, day TEXT, kind TEXT, count INT, PRIMARY KEY(owner_id, day, kind))`. Day = UTC date string.
- FastAPI dependency factory `spend_quota(kind, daily_limit)` applied to expensive routes:
  - `POST /cards` (AI card creation): **10/day**
  - Card chat + library chat + rabbithole: **30/day** combined
  - `GET /connections?refresh=true`: **3/day**
  - Limits are env-configurable (`QUOTA_CARDS_PER_DAY`, etc.).
- **Degrade, don't fail (cards):** past quota, `POST /cards` still succeeds but the job row is flagged `degraded=1`; the worker skips LLM structuring and uses the existing paragraph-fallback path. This flag is also the V2 hook — a device with an installed local model can fetch the raw bundle and structure it client-side.
- **Chat past quota:** 429 with structured body `{error: "quota", kind, used, limit, resets_at}`; UI renders "recharges tomorrow" state.
- Quota status: expensive-route responses include `quota: {used, limit}`; plus `GET /me/quota` for the profile meter.
- **Anon-farming defense:** card creation also increments a per-IP counter (same table, `owner_id = "ip:<addr>"`), capped at e.g. 30/day/IP (env-configurable). Prevents scripted fresh anonymous uids from draining keys.

### 6. Backend hardening

- `/admin/stats`, `/debug/jobs`, `/debug/kill_stuck`: require `X-Admin-Token` header equal to `ADMIN_TOKEN` env secret (404/401 otherwise).
- Global 500 handler: full traceback to server logs only; client gets `{"detail": "internal error"}`.
- CORS: `allow_origins` restricted to the hosted Space origin + `http://localhost:*` dev origins (native APK traffic is unaffected by CORS).

### 7. UI changes (Flutter)

- **Login screen** (new, shown after onboarding/name screen): Google button + small "Or use without login…" link; brand styling consistent with `brand.dart` tokens.
- **Profile screen:** account section — avatar/name/email when linked; "Sign in with Google" banner when anonymous; quota meter ("7/10 AI cards today"); sign out.
- **Share/pipeline UI:** quota chip; degraded card shows "AI recharges tomorrow".

### 8. Error handling

- 401 from API → client forces token refresh once, retries; still 401 → return to login screen.
- Firebase unreachable at launch → app opens read-only from repository cache with "reconnecting" banner.
- Quota 429 → friendly states everywhere; raw errors never shown.
- `verify_id_token` failures log the reason server-side (expired vs malformed vs wrong project).

### 9. Testing

- `backend/tests/` is deleted on the current branch — restore the pytest harness first.
- Backend: `get_owner` (valid/expired/forged/missing token, mocked verifier); quota spend/rollover/degrade flag; per-IP cap; admin-token gate; `/auth/claim` first-claim-wins.
- Flutter: auth controller transitions (anonymous → linked); quota meter widget; 401-retry logic in ApiClient.

## UI trust & polish fixes (from 2026-07-10 whole-app critique, score 26/40)

Ship with this release; full report in `.impeccable/critique/2026-07-10T11-11-16Z__app-lib.md`.

**P1 — trust (all four required):**
1. **Real cache clear**: `_confirmClear` (profile_screen.dart) currently shows "Offline cache cleared" without clearing anything. Wire to the local store's actual clear, or remove the tile.
2. **Move to Folder**: implement the bulk-selection "Move to Folder" action (collections + move endpoint already exist); replace both "coming soon" stubs (home_shell.dart, library_screen.dart). Dedupe the duplicated bulk-delete dialog while there.
3. **Friendly errors**: map `ApiException` → human strings at the repository boundary; never surface `e.toString()` in snackbars/error states (pairs with server-side traceback removal above).
4. **Cold-start state**: HF Space sleeps; first connect must show "Waking Cachy up — first load takes ~30s" with auto-retry (library + share view models) instead of "Can't reach Cachy".

**P2 — polish:**
5. **Reduced motion**: honor `MediaQuery.disableAnimations` via one shared gate covering all flutter_animate/AnimatedScale usages.
6. **Onboarding brand pass**: replace lightning `_LogoBadge` with CachyGlyph, Fraunces w800 → w600, route type through `Brand` instead of direct GoogleFonts (onboarding_screen.dart, name_screen.dart). This screen precedes the new login screen, so it's touched anyway.
7. **Motion curve**: `Motion.spring` easeOutBack → easeOutCubic (and the matching bounce cubic-bezier in app/web/index.html splash).

**Minors (fold in where files are already open):** stale doc comments (library_screen.dart header), audit stray hex literals outside tokens, dev password constant gets a `ponytail:` note or moves behind the admin token.

## One-time owner setup (~30 min)

1. Create Firebase project; enable Anonymous + Google sign-in providers.
2. Android: add `google-services.json`, register release-keystore SHA-1.
3. Web: Firebase JS config in Flutter web init.
4. HF Space env: `FIREBASE_PROJECT_ID` (token verification needs no service-account secret for `verify_id_token` with JWKS), `ADMIN_TOKEN`, quota env vars.

## Out of scope (V2+)

- On-device quantized model (opt-in "offline AI" past quota) — the `degraded` job flag + raw-bundle fetch is the designed extension point.
- Play Store / App Store distribution, payments, email/password auth, multi-device conflict resolution beyond what Firebase uid sync gives for free.
