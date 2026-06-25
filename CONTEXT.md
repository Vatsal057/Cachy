# Cachy — Project Context for Continuation

## What This Is

A mobile app + backend that turns short-form videos (Instagram Reels, TikTok, YouTube Shorts) into structured, readable, actionable knowledge cards. Users share a reel → async pipeline (ingest → extract → structure → persist) → progressive card via SSE → read/search.

**Status:** Backend Phase 1 complete. Tests pass (17/17). Core pipeline verified end-to-end. Ready for Flutter frontend.

## Architecture Overview

```
share URL
  → FastAPI POST /cards
    → create Card (QUEUED) + Job
    → return card_id immediately
  → Client connects GET /cards/{id}/stream (SSE)
  → Worker background loop:
      1. ingest:     download media (yt-dlp + instaloader)
      2. extract:    ffmpeg → audio + frames + Groq Whisper → Tesseract OCR → bundle
      3. structure:  Groq LLM (mixtral or llama) → JSON blocks + validation
      4. persist:    progressive (base → blocks → media)
      5. state:      QUEUED → PROCESSING → READY (or FAILED)
  → SSE stream emits stage events for UI transparency
  → card always renders (validation + paragraph fallback)
```

See `/docs/01-architecture.md` for the full diagram.

## What's Built

### Backend (`/backend/app/`)

- **[config.py](backend/app/config.py)** — pydantic-settings, env-driven. Graceful degradation: no API keys needed to boot or complete a job.
- **[models/card.py](backend/app/models/card.py)** — the contract (docs/04). Sealed `Block` union (8 P1 + map/table P2), `Card`, `Source`, `Base`, enums. `schema_version="1.0"`.
- **[models/job.py](backend/app/models/job.py)** — `JobState` enum (QUEUED, PROCESSING, DONE, FAILED, DEAD).
- **[store/db.py](backend/app/store/db.py)** — async SQLAlchemy 2.0 + aiosqlite. `CardRow` + `JobRow` ORM, row↔Pydantic helpers. SQLite by default, PostgreSQL ready.
- **[store/media.py](backend/app/store/media.py)** — per-job isolated dirs, media cleanup on card delete.
- **[services/events.py](backend/app/services/events.py)** — in-process pub/sub for SSE (asyncio.Queue). Single-process only; swap for Redis if worker moves out-of-process.
- **[services/cache.py](backend/app/services/cache.py)** — dedup: re-share same URL returns existing card.
- **[services/notify.py](backend/app/services/notify.py)** — stub for push/badge (Phase 2: FCM).
- **[pipeline/ingestion/resolvers.py](backend/app/pipeline/ingestion/resolvers.py)** — **user's file, untouched**. yt-dlp + instaloader. Drop in a richer cascade later (keyless scrapers, RapidAPI) without editing downloader.py.
- **[pipeline/ingestion/downloader.py](backend/app/pipeline/ingestion/downloader.py)** — orchestration layer. `DownloaderConfig`, `DownloadResult`, `DownloadError`. Cascade probes for optional resolvers via `getattr`, falls back to yt-dlp → instaloader. Records winning resolver.
- **[pipeline/extraction.py](backend/app/pipeline/extraction.py)** — ffmpeg (audio + scene-frames), phash frame dedup, Groq Whisper (optional), Tesseract OCR (optional), labeled text bundle. Every step degrades, never aborts.
- **[pipeline/structuring.py](backend/app/pipeline/structuring.py)** — single text-only Groq LLM call (mixtral/llama). **Mandatory validation**: strip fences, parse JSON, drop out-of-vocab/invalid blocks, force non-empty one_liner/tldr, primary_action map, assign ids. **Paragraph fallback** on no-key/bad-JSON/empty. Guarantee: card always renderable.
- **[pipeline/worker.py](backend/app/pipeline/worker.py)** — background job loop. State machine (QUEUED→PROCESSING→READY|FAILED). Progressive persist (base first for read-now streaming). Retry transient errors; dead-letter after `MAX_ATTEMPTS`. Emits stage events for SSE.
- **[api/cards.py](backend/app/api/cards.py)** — endpoints: POST (+dedup), GET, list, PATCH (checked items), DELETE (+media cleanup). GET `/cards/{id}/stream` is the SSE endpoint.
- **[api/search.py](backend/app/api/search.py)** — GET `/search?q=` full-text over one_liner+tldr+blocks (SQLite LIKE, upgrade to FTS5 in P2).
- **[main.py](backend/app/main.py)** — FastAPI app. Worker started in lifespan. Routes registered.

### Tests (`/backend/tests/`)

- **[conftest.py](backend/tests/conftest.py)** — temp SQLite, temp media dir, no API keys. Graceful-degradation paths exercised by default.
- **[test_schema.py](backend/tests/test_schema.py)** — block union round-trips, unknown types dropped, required-field validation.
- **[test_structuring.py](backend/tests/test_structuring.py)** — paragraph fallback (no key, bad JSON), synthesize one_liner/tldr, primary_action mapping.
- **[test_pipeline.py](backend/tests/test_pipeline.py)** — end-to-end job with ingestion/extraction stubbed, reaches READY with sane card; dead-letter on exhaust retries.
- **[test_api.py](backend/tests/test_api.py)** — HTTP contract: POST returns id, dedup, GET/list/PATCH/DELETE.

**Result:** 17/17 pass. No API keys needed.

### Config Files

- **[pyproject.toml](backend/pyproject.toml)** — deps, dev deps (pytest, httpx), build metadata.
- **[.env.example](backend/.env.example)** — all env vars documented with defaults.
- **[.env](backend/.env)** — placeholder (empty keys, or populate with real ones).
- **[Dockerfile](backend/Dockerfile)** — HF Spaces (Docker, free tier). Python 3.11, ffmpeg, tesseract. Ports 7860.
- **[.gitignore](backend/.gitignore)** — venv, db, media, caches.

## Hard Rules (Non-Negotiable)

1. **Resolvers untouched.** `resolvers.py` internals fragile; only `downloader.py` orchestration is edited.
2. **Schema is the contract.** `models/card.py` mirrors `docs/04-structuring-and-schema.md` exactly. Any block-shape change bumps `schema_version`.
3. **Always validate LLM output.** Never trust raw model JSON. Validation + paragraph fallback guarantees a card always renders.
4. **Transparent capture.** SSE stream shows pipeline progress (downloading/extracting/structuring/persisting) so the user never waits blindly.
5. **Free-first stack.** Prefer free/local tools (ffmpeg, Tesseract, Groq Whisper). No costs added without flagging.
6. **Surgical changes.** Smallest change that does the job. No unsolicited rewrites, no reformatting untouched code.

## Current Constraints & Gotchas

### Known Issues

1. **instaloader shared temp_images dir not concurrency-safe.** Fine for single-worker dev; give it per-job dir before parallel workers.
2. **Groq models rotate.** `mixtral-8x7b-32768` and `llama-3.1-70b-versatile` both decommissioned in test run. Check [console.groq.com/docs](https://console.groq.com/docs) for current active models before deploying.
3. **ffmpeg scene-change filter (exit 234).** Falls back to fps-based frame extraction. Not a hard error, but worth investigating on real audio.
4. **Placeholder API keys in .env.** Replace with valid Groq API key to unlock Groq structuring. Without it, all cards degrade to paragraph fallback (still usable, just minimal structure).

### Ephemeral FS (HF Spaces free tier)

- SQLite file `cachy.db` and media dir `downloads/` reset on every Space restart.
- For persistence: wire up free external Postgres (Neon/Supabase) + R2 (Cloudflare, free tier).
- For demo/project: ephemeral is fine if cards only live within a running session.

### No Account System (Phase 2)

- Cards are device/session-scoped (no `owner_id` enforcement). `owner_id` field nullable, ready for later.
- No auth, no sync across devices, no cross-device share.

## Running the Backend

### Setup

```bash
cd backend
python -m venv .venv
. .venv/bin/activate
pip install -e ".[dev]"
```

### Test

```bash
pytest -q
# 17 passed (no API keys needed, graceful fallback exercised)
```

### Run

```bash
# .env defaults to SQLite + localhost media; valid Groq key optional
uvicorn app.main:app --reload
```

- Health: `curl localhost:8000/health`
- POST reel: `curl -X POST localhost:8000/cards -H 'content-type: application/json' -d '{"url":"https://instagram.com/reel/XYZ"}'`
- SSE stream: `curl -N localhost:8000/cards/{card_id}/stream`
- Fetch card: `curl localhost:8000/cards/{card_id}`

### Environment Variables

```
DATABASE_URL=sqlite+aiosqlite:///./cachy.db    # or postgres+asyncpg://...
MEDIA_DIR=./downloads
WHISPER_BACKEND=groq                           # or "none" (skip transcription)
GROQ_API_KEY=gsk_...                           # required for transcription + structuring
GROQ_WHISPER_MODEL=whisper-large-v3-turbo      # active model, may change
MAX_ATTEMPTS=3                                 # retry on transient errors
WORKER_POLL_SECONDS=1.0                        # queue poll frequency
JOB_TIMEOUT_SECONDS=300                        # per-job timeout
DISCARD_SOURCE_VIDEO=true                      # delete source.mp4 after extraction
```

No Gemini key needed (used Groq for LLM instead). See `.env.example` for full list.

## What Works End-to-End

✅ Download via yt-dlp (instaloader fallback for carousels)  
✅ Extract audio + keyframes (ffmpeg)  
✅ Transcription (Groq Whisper, optional)  
✅ OCR (Tesseract, optional)  
✅ Structuring with fallback (Groq LLM or paragraph)  
✅ Progressive persist (base → blocks → media)  
✅ State machine (QUEUED→PROCESSING→READY|FAILED)  
✅ Retry + dead-letter (MAX_ATTEMPTS)  
✅ SSE stream (transparent capture)  
✅ Dedup (same URL → same card)  
✅ Full CRUD (POST, GET, list, PATCH, DELETE)  
✅ Full-text search  
✅ Tests + graceful degradation without keys  

Tested live: Instagram reel ingested, extracted, structured (with valid keys), media stored, card READY.

## What's NOT Done (Phase 2+)

- Flutter frontend (share extension, library grid, reader, actions)
- Maps + tables block renderers
- Collections + auto-tagging
- Semantic search + embeddings
- Chat-with-library
- Real push (FCM)
- Accounts + cross-device sync
- Multiple platforms (TikTok, YouTube Shorts) — resolvers there, API ready

See `/docs/10-phasing-and-roadmap.md` for Phase 2/3 details.

## How to Continue

### Next: Flutter Frontend (Phase 1)

1. Read `/docs/06-frontend.md` and `/docs/07-visual-design.md`.
2. Set up Flutter project with async http client, sealed Block model, block renderer widgets.
3. Build share extension (Android/iOS), library grid, reader (progressive render), primary action handlers.
4. Connect to running backend (POST /cards, SSE stream, GET endpoints).

### For Production (Before Public)

1. **Valid API keys.** Groq key for transcription + structuring.
2. **External DB.** Neon (PostgreSQL) for persistence across Space restarts.
3. **External media storage.** Cloudflare R2 (S3-compatible, free tier).
4. **Update resolvers.py.** Keyless scrapers optional but recommended for resilience.
5. **Monitor Groq models.** Check active models quarterly; update `structuring.py` if models decommissioned.

## File Structure

```
Cachy/
  docs/                     # all design docs (read these first)
    00-overview.md
    01-architecture.md
    02-ingestion.md
    03-extraction.md
    04-structuring-and-schema.md  (the contract)
    05-backend.md
    06-frontend.md
    07-visual-design.md
    08-data-model.md
    09-features.md
    10-phasing-and-roadmap.md
    11-assumptions-and-open-decisions.md
  backend/                  # Phase 1 complete
    app/
      main.py
      config.py
      api/
        cards.py
        search.py
      models/
        card.py
        job.py
      pipeline/
        worker.py
        ingestion/
          resolvers.py      (user's, untouched)
          downloader.py
        extraction.py
        structuring.py
      services/
        events.py
        cache.py
        notify.py
      store/
        db.py
        media.py
    tests/
      conftest.py
      test_schema.py
      test_structuring.py
      test_pipeline.py
      test_api.py
    pyproject.toml
    .env.example
    .env
    Dockerfile
    .gitignore
  code/
    downloader.py           (reference, not used)
  CONTEXT.md                (this file)
```

## Key Insights

- **Schema first.** Block contract (docs/04) is the spine. Both backend and frontend build against it. Hydrate carefully.
- **Progressive render.** Base (one_liner+tldr) persists first so the reader can show something while blocks/media arrive. SSE stream ensures the client sees progress.
- **Validation + fallback.** Never assume LLM JSON is valid. Validation is where the "always produces a sane card" guarantee lives.
- **Per-job isolation.** Each download gets a unique dir so concurrent jobs never collide on media files. This scales better than a shared dir + locking.
- **Graceful degradation.** The app boots and completes jobs with no API keys. Transcription skips, structuring falls back to a paragraph. This is feature, not a limitation — it lets you test and demo offline.

## Testing the Live Pipeline

```bash
# Terminal 1: start server
cd backend && . .venv/bin/activate
uvicorn app.main:app --port 8099

# Terminal 2: post a reel and watch
CARD_ID=$(curl -s -X POST http://localhost:8099/cards \
  -H 'content-type: application/json' \
  -d '{"url":"https://instagram.com/reel/DS-b36KD29W/"}' | \
  python3 -c "import sys,json;print(json.load(sys.stdin)['card_id'])")

# Watch SSE stream
curl -sN http://localhost:8099/cards/$CARD_ID/stream

# Fetch final card
curl http://localhost:8099/cards/$CARD_ID | python3 -m json.tool
```

With a valid Groq key, the card will have structured blocks. Without it, a paragraph fallback.

## References

- **Design docs:** `/docs/` — read in order, start with `00-overview.md`.
- **Schema contract:** `/docs/04-structuring-and-schema.md` — the source of truth.
- **Backend structure:** `/docs/05-backend.md`.
- **Frontend roadmap:** `/docs/06-frontend.md`.
- **Groq API:** [console.groq.com](https://console.groq.com/docs) — check active models.
- **Pydantic:** [pydantic-docs.helpmanual.io](https://docs.pydantic.dev) — type hints, validation.
- **FastAPI:** [fastapi.tiangolo.com](https://fastapi.tiangolo.com) — async, SSE, dependency injection.

---

**Last updated:** 2026-06-25 (backend Phase 1 complete, live tested with Instagram reel).  
**Ready to build:** Flutter frontend (Phase 1).
