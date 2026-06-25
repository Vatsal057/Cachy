# 11 — Assumptions & Open Decisions

These docs make a few decisions on your behalf so the set is complete and
buildable. All are **reversible** (this is documentation) and none block Phase 1.
Confirm or correct each; I've marked the default I assumed.

## Deployment (decided)

**Backend deploys to Hugging Face Spaces (free tier), as a Docker Space.** This is
a final-year project, so free-tier constraints are accepted. Consequences folded
into the docs:

- Transcription default flipped to **Groq hosted Whisper** (free HF tier is
  CPU-only; local Whisper is too slow there).
- Filesystem is **ephemeral** — cards/media don't survive restarts on free tier.
  Acceptable for demo. For persistence, attach free external Postgres (Neon/
  Supabase) + R2, or HF persistent storage (paid). See `05-backend.md`.
- Worker runs in-process / same container; DB-backed queue (no Redis to host).

## Assumed (correct me if wrong)

1. **Frontend = Flutter, backend = Python/FastAPI.** (Stated by you.)
2. **Transcription = Groq hosted Whisper** (free tier), given HF free CPU.
3. **Structuring = text-only LLM** via HuggingFace Inference Providers
   (`Qwen/Qwen2.5-72B-Instruct`, default) or Groq (`llama-3.1-70b-versatile`,
   fallback). OCR runs locally on Tesseract; visual/scene description is a rare
   conditional HF Inference VLM call. No single multimodal call — vision is kept
   off the structuring LLM.
4. **Database = SQLite** for now (ephemeral on HF, fine for a project demo);
   external Postgres only if you want persistence.
5. **Job queue = DB-backed**, worker in-process on the Space.
6. **Media storage = local/ephemeral** for now; R2 only if persistence is needed.
7. **Accounts = none; cards are device/session-scoped.** (`owner_id` nullable in
   schema, ready if you add accounts later.)
8. **Push = local notifications**; FCM only if you want real push later.

## Genuinely open — your call

Most decisions are now settled by the HF / project-scope choice. What remains:

1. **Persistence vs. ephemeral.** Free HF wipes data on restart. Fine for a live
   demo; if you need cards to survive between sessions (e.g. an examiner tries it
   the next day), wire up free external Postgres + R2. Default assumed: **ephemeral**.

2. **Source video retention.** Keep the full downloaded video, or discard after
   extraction and keep only keyframes + thumbnail? On ephemeral HF this barely
   matters; default assumed: **discard**.

3. **Embedding model for semantic search (P2/P3).** Free/local keeps the no-cost
   stack. Decide when you reach P2.

## Verify before building around them

- **Current HF Inference & Groq free-tier limits** — these shift; check live numbers
  before sizing your quota strategy. Single-pass + caching keeps you under
  whatever the ceiling is.

## Resolved

- ~~Budget ceiling~~ → free tier; final-year project scope.
- ~~Hosting~~ → Hugging Face Spaces (Docker).
- ~~Accounts / cross-device sync~~ → none for now; device/session-scoped.
- ~~Distribution intent~~ → project/personal; resolver cascade is acceptable.
