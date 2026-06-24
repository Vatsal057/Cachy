# 05 — Backend

Python / FastAPI. Async job pipeline. Designed to run on a small host with a
free-tier-friendly footprint.

## Project layout

```
backend/
  app/
    main.py            # FastAPI app, router registration
    config.py          # settings (env-driven)
    api/
      cards.py         # card endpoints
      search.py        # search + chat endpoints (phase 2/3)
    pipeline/
      worker.py        # job runner: ingest → extract → structure → persist
      ingestion/
        resolvers.py   # working resolver functions (untouched)
        downloader.py  # async orchestration layer
      extraction.py    # ffmpeg + Whisper + keyframes
      structuring.py   # Gemini call + schema validation
    models/
      card.py          # Card / Block ORM + Pydantic schemas
      job.py           # Job + state machine
    store/
      db.py            # DB session
      media.py         # media file storage (local / object store)
    services/
      cache.py         # url → existing card
      notify.py        # push / badge
  tests/
  pyproject.toml
```

## Endpoints (MVP)

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/cards` | Accept a shared URL. Create card (QUEUED), enqueue job, return `card_id` immediately. Returns existing card if URL is cached. |
| `GET` | `/cards/{id}/stream` | SSE endpoint to stream pipeline state changes to the client in real-time. |
| `GET` | `/cards/{id}` | Fetch a card (any state). Used for fetching full card once stream indicates READY. |
| `GET` | `/cards` | List cards (paginated, filter by state/collection/tag). |
| `DELETE` | `/cards/{id}` | Delete a card and its derived data + media. |
| `PATCH` | `/cards/{id}` | Update user-mutable state (checked items, collection, tags). |

Phase 2+: `POST /search` (semantic), `POST /chat` (query over library),
`POST /cards/{id}/export`, collection endpoints.

`POST /cards` returns the `card_id` immediately, and the client instantly connects to `GET /cards/{id}/stream` to show the user the pipeline's progress step-by-step.

## Job queue

The queue is the spine. Two viable free setups:

- **MVP / simplest:** a DB-backed queue (a `jobs` table polled by a worker
  process). No extra infra. Good enough to ship Phase 1.
- **When scaling:** Redis + a worker pool (RQ or Celery). Add when one worker
  can't keep up.

Worker loop per job: set PROCESSING → `download_content_async` → extraction →
structuring + validation → persist (writing `base` first for progressive render)
→ READY, or FAILED with a reason. Retries on transient errors; dead-letter after N.

## Storage

- **Database:** SQLite for dev, PostgreSQL for production. Schema in `08-data-model.md`.
- **Media:** downloaded video/keyframes/thumbnail. Local disk for MVP; an
  S3-compatible object store (e.g. Cloudflare R2, which has a free tier) when you
  need durability/scale. Thumbnails and keyframes are kept; the full source video
  can be discarded after extraction to save space (decision flagged in `11`).

## Config (env)

```
DATABASE_URL=
MEDIA_DIR=./downloads          # or object-store creds
GEMINI_API_KEY=
RAPIDAPI_KEY=                  # optional
WHISPER_BACKEND=local|groq
GROQ_API_KEY=                  # only if WHISPER_BACKEND=groq
PUSH_BACKEND=none|fcm          # FCM free tier
```

## Deployment (Hugging Face Spaces)

Target: **Hugging Face Spaces** (free tier), as a **Docker Space** running the
FastAPI app + worker. The app architecture is unchanged; HF runs FastAPI cleanly
— just expose the port. Two HF-specific constraints to design around:

- **Ephemeral filesystem.** The free-tier disk resets on every rebuild/restart,
  and Spaces sleep when idle. Local disk and a SQLite file do **not** persist
  across restarts.
  - For a demo/project: ephemeral is acceptable if you only need cards to live
    within a running session.
  - For persistence: use a free external Postgres (Neon / Supabase free tier) for
    the DB and an S3-compatible store (Cloudflare R2 free tier) for media, or HF
    persistent storage (paid).
- **CPU-only, limited RAM (free tier).** Local Whisper is slow/heavy here. Prefer
  **Groq hosted Whisper** (free tier) so the Space stays light and the demo is
  snappy. Local `faster-whisper` remains an option if you later move to a GPU
  Space or a different host.

Worker note: on a single free Space, run the worker in-process (background task)
or as a second process in the same container — a DB-backed queue is the simplest
fit (no Redis to host).

## Observability

- Per-resolver success rate (recorded on each card via `source.resolver`).
- Per-stage processing time (ingest / extract / structure).
- Failure counts by reason.
- LLM call count (watch against the Gemini free-tier ceiling).
