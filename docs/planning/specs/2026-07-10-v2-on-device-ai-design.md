# Cachy V2: On-Device AI + Distribution Growth

**Date:** 2026-07-10
**Status:** Draft (V2 — build after the V1 auth/quota release ships and stabilizes)
**Depends on:** `2026-07-10-public-distribution-auth-quotas-design.md` (V1) — specifically the `degraded` job flag, quota system, and Firebase identity.

## Problem

V1 caps each user at N AI cards/day so shared free-tier keys survive. Past quota, cards degrade to paragraph fallback. Power users want more without the developer paying for it. V1's answer was "wait until tomorrow"; V2's answer is: **bring your own compute** — an optional quantized model running on the user's phone.

Also collected here: the rest of the deferred V2 items (store distribution, sustainability, claim-endpoint removal) so V2 has one source of truth.

## Part 1 — On-device AI (headline)

### Decision summary

| Decision | Choice | Why |
|---|---|---|
| Split point | Server extracts (download, whisper, OCR → text bundle); device structures (bundle → card JSON) | Extraction needs yt-dlp/ffmpeg — impossible on phone. Structuring is pure text→JSON — exactly what a small LLM can do |
| Trigger | Quota-degraded cards, when local model installed & enabled | Reuses V1's `degraded` flag; zero new quota logic |
| Runtime | MediaPipe LLM Inference API (Android), via `flutter_gemma` or direct platform channel | Google-maintained, handles quantized Gemma models on-device, no NDK build of llama.cpp needed. Re-validate at build time — this space moves fast |
| Model | Gemma 3 1B, int4 quantized (~550 MB) | Best small-model JSON-following per size; MediaPipe-native. Fallback candidate: Qwen2.5-1.5B-Instruct q4 |
| Platforms | Android APK only | Web can't (practically); iOS not distributed yet |
| Opt-in UX | Profile → "Offline AI" section: explicit download (~550 MB warning, Wi-Fi recommended), enable/disable toggle, delete model | Never surprise-download half a gigabyte |
| Output guard | Client validates generated JSON against the card block schema; invalid → paragraph fallback (same as server) | Small models fail JSON sometimes; the card must always render |

### Architecture

1. **Server persists the bundle for degraded jobs.** Worker, on a `degraded` job, stores the extraction bundle (transcript + OCR text + caption — text only, a few KB) on the card row (`cards.raw_bundle` TEXT, nullable) instead of discarding it after paragraph fallback.
2. **New endpoint** `GET /cards/{id}/bundle` (auth: owner only) → `{"bundle": str, "transcript": str, "caption": str}`; 404 when no stored bundle.
3. **New endpoint** `POST /cards/{id}/structure` (auth: owner only) → accepts client-generated `{blocks: [...], one_liner, tags, ...}`, validated server-side with the **same** Pydantic validation the LLM path uses (never trust device output), replaces the paragraph card's content, clears `raw_bundle`, re-embeds.
4. **Flutter `LocalAiService`:** model download manager (resumable, checksum), inference wrapper (`structureBundle(bundle) -> Map?`), prompt tuned for 1B models (short system prompt, few-shot single example, strict JSON instruction).
5. **Flow:** card comes back `quota_degraded` → app checks Local AI enabled → fetches bundle → structures on-device (progress UI: "Generating on your phone…") → POSTs result → card upgrades in place. Failure at any step → paragraph card stays (user never worse off).

### UX rules

- Quota chip gains a second state: past quota + model installed → "Generating on your phone" instead of "AI recharges tomorrow".
- Generation runs foreground-visible (reader shows progress), cancellable. No silent battery drain.
- Settings shows model size on disk, last-used, delete button.

### Explicitly rejected

- Shipping the whole pipeline on-device (yt-dlp on Android: no).
- Auto-downloading the model for everyone.
- Trusting device JSON without server-side validation (auth'd users could inject arbitrary blocks otherwise).

## Part 2 — Distribution & sustainability (V2 grab-bag)

1. **Play Store**: $25 one-time, release signing already exists; needs privacy policy page (host on the HF Space at `/privacy`), Data Safety form (declares: account IDs, user content stored server-side), target API compliance. Do after auth ships — store review with anonymous+Google auth is straightforward.
2. **Sustainability hooks**: GitHub Sponsors / Ko-fi link in Profile → About ("Keep Cachy free"); apply for GitHub Student Pack + Cerebras/Groq startup/edu credits to raise free ceilings.
3. **Cleanup task**: delete `/auth/claim` endpoint + `claims` table ~1 month after V1 auth ships (calendar it).
4. **Deferred still**: email/password auth, payments, iOS, multi-device conflict resolution. Not in V2 either unless users demand.

## Part 3 — Private media (thumbnails/keyframes off the public HF dataset)

### Problem

Thumbnails and keyframes for every user's saved content currently live in a **public** HF dataset repo (`hf_media_repo` in `config.py`). The onboarding name screen promises "Your library stays private. Only you see your cards" — false for images today. Backend currently returns HF dataset URLs directly to the client (`resolveMedia` in `api_client.dart` joins bare paths, or passes through absolute URLs).

### Decision

Flip the HF dataset repo to **private**, add an owner-checked proxy endpoint, keep everything else (HF storage, `hf_api_key`) as-is. No new vendor — R2/S3 migration stays a "later, if bandwidth ever hurts" option, not part of this task (ponytail: don't add infrastructure for a problem that doesn't exist yet at this scale).

### Architecture

1. **Flip `hf_media_repo` to private** in the HF dataset settings (one-time manual step, no code).
2. **New endpoint** `GET /media/{card_id}/{filename}` — `OwnerDep`-gated (must own the card, verified via `CardRow.owner_id`), streams bytes from the private HF dataset using the existing `hf_api_key` (server-side `hf_hub_download` or the HF `hfh` HTTP API), sets correct `content-type` from the file extension.
3. **Backend media writer** (wherever thumbnails/keyframes are currently persisted, likely `store/media.py`) stores media under a `{card_id}/...` path scheme if not already, so the proxy route can validate ownership before any HF fetch.
4. **Client**: `ApiClient.resolveMedia` continues to just join bare paths onto `baseUrl` — no change needed if the backend now returns `/media/{card_id}/{filename}` instead of absolute HF URLs (check `structuring.py`/`worker.py` for where media refs are written into card JSON; update to emit the proxy path instead of the raw HF URL).
5. **Caching**: proxy response gets `Cache-Control: private, max-age=3600` (browser/client caches per-session; still requires re-auth on a fresh session, avoiding stale public exposure).

### Testing

- Backend: proxy route 404s for non-owned cards; 200 + correct bytes for owned cards; unauthenticated request 401.
- Manual: confirm the HF dataset repo is actually private (attempt an unauthenticated raw HF URL fetch — must fail) after the flip.
- Regression: existing cards' media still resolves after the path-scheme change (migrate old absolute-URL refs or keep a fallback branch in `resolveMedia`/backend for pre-migration cards).

## Success criteria

- A quota-exhausted user with the model installed gets a structured (not paragraph) card, fully offline of AI providers, in <2 min on a mid-range phone.
- Server AI spend for that card: zero.
- Users without the model see zero change.
- No thumbnail or keyframe is fetchable without a valid owner session (public dataset browsing no longer exposes any user's media).

## Testing

- Backend: bundle persisted only for degraded jobs; `/bundle` owner-scoped 404/200; `/structure` rejects schema-invalid payloads, upgrades card, clears bundle.
- Flutter: `LocalAiService` faked in tests (interface like `AuthService`); download-manager state machine (idle→downloading→ready→error) unit-tested; JSON-invalid model output → paragraph kept.
- Manual: one real mid-range Android device before release (emulators lie about inference speed).
