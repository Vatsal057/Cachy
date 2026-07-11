# V2 On-Device AI + Distribution Implementation Plan (Roadmap)

> **For agentic workers:** This is a V2 roadmap plan. Prerequisites: V1 plans (`2026-07-10-backend-auth-quotas.md`, `2026-07-10-flutter-auth.md`) executed and deployed. Before executing any task here, RE-VALIDATE the runtime choice (MediaPipe LLM Inference / `flutter_gemma` / model availability) — the on-device LLM ecosystem changes monthly. Then expand each task into full TDD steps via superpowers:writing-plans.

**Goal:** Quota-exhausted users with an installed local model get structured cards generated on their own phone — zero server AI spend. Plus Play Store readiness and sustainability hooks.

**Spec:** `docs/superpowers/specs/2026-07-10-v2-on-device-ai-design.md`

## Phase A — Backend bundle round-trip (independent, testable now-ish)

### Task A1: Persist raw bundle on degraded jobs
- `cards.raw_bundle: TEXT NULL` column + additive migration entry.
- Worker: when `job.degraded`, store the extraction bundle text on the card before paragraph fallback.
- Test: degraded job → `raw_bundle` set; normal job → NULL.

### Task A2: `GET /cards/{id}/bundle`
- Owner-scoped (OwnerDep). 200 `{bundle, transcript, caption}` when stored; 404 otherwise.
- Test: owner gets bundle; other uid 404; non-degraded card 404.

### Task A3: `POST /cards/{id}/structure`
- Owner-scoped. Body = client-generated structured card JSON.
- Validate with the SAME Pydantic models the LLM path uses (`structuring` validation) — reject invalid with 422.
- On accept: replace paragraph content, clear `raw_bundle`, re-run `_embed_card`, bump card state.
- Test: valid payload upgrades card + clears bundle; schema-garbage 422; foreign owner 404.

## Phase B — Flutter local AI

### Task B1: `LocalAiService` interface + fake
- Mirror the `AuthService` pattern: abstract interface, `FakeLocalAiService` for tests.
- API: `status` (notInstalled|downloading(progress)|ready|error), `download()`, `delete()`, `Future<Map<String,dynamic>?> structureBundle(String bundle, {String transcript, String caption})` (null = generation failed/invalid JSON).

### Task B2: Model download manager
- Resumable download of Gemma 3 1B int4 (~550 MB) to app storage, sha256 check, Wi-Fi-recommended warning dialog.
- State machine unit-tested against the fake HTTP layer.

### Task B3: Inference integration
- MediaPipe LLM Inference via platform channel (or `flutter_gemma` if healthy at build time). Android only; feature-gate everywhere else.
- Prompt: short instruction + one few-shot example + strict "JSON only" suffix; client-side JSON parse + block-schema validation; invalid → return null.

### Task B4: Wire the degrade path
- Card returns `quota_degraded` → if `LocalAiService.status == ready`: fetch `/bundle`, run `structureBundle`, POST `/structure`, refresh card. Progress UI in reader ("Generating on your phone…"), cancellable.
- Any failure → paragraph card remains, no error dialog (silent grace, log only).
- Widget test with fakes: degraded card + ready model → upgraded card; model returns null → paragraph kept.

### Task B5: Profile "Offline AI" section
- Download/enable/disable/delete UI, size on disk, honest copy ("~550 MB, runs on your phone, slower than cloud").
- Quota chip second state: "Generating on your phone".

## Phase C — Distribution & sustainability

### Task C1: Privacy policy page at `/privacy` on the Space; link from Profile → About.
### Task C2: Play Store submission — Data Safety form, target API check, store listing (screenshots from web build), $25 account.
### Task C3: Sponsors/Ko-fi link in Profile → About ("Keep Cachy free"); apply GitHub Student Pack + Cerebras/Groq edu credits.
### Task C4 (calendar ~1 month post-V1): delete `/auth/claim` + `claims` table + client claim flow.

## Phase D — Private media (thumbnails/keyframes off the public HF dataset)

Closes a real privacy gap: onboarding promises "Only you see your cards" but thumbnails currently sit in a **public** HF dataset repo. Spec: `docs/superpowers/specs/2026-07-10-v2-on-device-ai-design.md` Part 3.

### Task D1: Flip the HF dataset repo to private
- Manual, one-time: HF dataset settings → private. No code change. Verify with an unauthenticated raw-URL fetch attempt (must fail after the flip).

### Task D2: Owner-checked media proxy endpoint
- `GET /media/{card_id}/{filename}` — `OwnerDep`-gated (card's `owner_id` must match caller), streams bytes from the private HF dataset via `hf_api_key` (`hf_hub_download` or HF HTTP API), correct `content-type` by extension, `Cache-Control: private, max-age=3600`.
- Test: 404 for non-owned cards, 200 + correct bytes for owned cards, 401 unauthenticated.

### Task D3: Emit proxy paths instead of raw HF URLs
- Update wherever media refs are written into card JSON (`store/media.py` / `worker.py`) to emit `/media/{card_id}/{filename}` instead of the absolute HF dataset URL.
- Confirm `ApiClient.resolveMedia` needs no change (it already joins bare paths onto `baseUrl`; only absolute-URL passthrough becomes dead code for new cards).
- Regression: existing cards written before this change carry old absolute HF URLs — keep a fallback branch (client or backend) so pre-migration cards still resolve, or run a one-time backfill rewriting stored refs to the new scheme.

## Order & gates

- A before B (B needs the endpoints). C anytime after V1. D anytime after V1 (independent of A/B/C) — recommended right after V2's on-device work, per user sequencing preference; could move earlier since it's a live privacy gap, revisit if that becomes urgent.
- Gate before B3: benchmark chosen model on one real mid-range Android phone — if structuring takes >2 min or JSON validity <~70%, drop to paragraph-only and re-evaluate model choice.
- Gate before D1: confirm no other consumer (embed codes shared externally, cached CDN links, etc.) depends on the media repo being public before flipping it private.
