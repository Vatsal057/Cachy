# Cachy — Project Overview

Reference doc for reports/presentations. Source of truth is the code; this is a snapshot as of 2026-07-01. Regenerate/update if the codebase moves on.

## 1. What it is

Cachy turns short-form media (Instagram Reels, TikToks, YouTube Shorts) and web articles into structured **knowledge cards**: a one-liner, TL;DR, and typed content blocks (steps, key-value facts, checklists, callouts, maps, tables), plus **concepts** and **artifacts** (books/movies/products mentioned) extracted from the content. Cards link to each other via a semantic knowledge graph, and a "Feed" replays your own saved knowledge back to you reel-style.

Dual-client: Flutter app (`/app`, web + mobile) talking to an async FastAPI backend (`/backend`) over REST + Server-Sent Events.

## 2. Design principles

- **Free-first, graceful degradation**: every external AI/API dependency is optional. Missing key or rate limit → fallback chain → paragraph/local fallback. Never fails the job.
- **Cost discipline**: expensive steps (LLM calls) are cached, deduped, and bounded (e.g. serendipity connections capped per request).
- **Progressive persistence**: a job writes its base fields first (so the UI can stream the one-liner immediately), then blocks, then media.
- **No external infra**: single SQLite DB (`aiosqlite`), in-process background worker (no Redis/Celery), pure-Python graph algorithms (no graph library), single free HF Space deployable.

## 3. Backend architecture (`/backend/app`)

### Request/job flow
1. Client `POST /cards` with a URL (or shares to the app).
2. A `Job` row is queued (`app/models/job.py`: QUEUED → PROCESSING → DONE / FAILED / DEAD after `max_attempts`).
3. `pipeline/worker.py` — an in-process `asyncio` background loop (started in `main.py`'s FastAPI `lifespan`) — claims runnable jobs (QUEUED, or FAILED with attempts left). `POST /cards` calls `notify_new_job()` after committing the row so the loop wakes immediately; when the queue is empty it doubles its wait up to `worker_idle_max_seconds` (1800s) and stops touching the database entirely. Polling once a second used to keep a scale-to-zero Postgres permanently awake and drained Neon's monthly CU-hour allowance in ~17 days with nobody using the app. The interval is 30 minutes rather than 6 because every query restarts the 5-minute suspend timer, so a 6-minute poll still leaves the compute awake 83% of the time. Arithmetic is in `config.py`; written up as B8 in `AUDIT.md`.
4. Per job, pipeline stages run in order, each emitting an SSE event so the client can stream progress:
   - **Ingest** (`pipeline/ingestion/`): resolve the URL, download video via `yt-dlp`/`instaloader`, or extract readable article text via `trafilatura` for web articles. Source video is discarded after extraction — nothing stored locally.
   - **Extract** (`pipeline/extraction.py`): keyframe extraction, OCR (`pytesseract` + OpenCV preprocessing) for on-screen text/carousels, audio transcription.
   - **Structure** (`pipeline/structuring.py`): the AI card-generation step. LLM fallback chain: **Gemini 2.5 Flash (primary) → Cerebras llama-3.3-70b (60k TPM free tier) → Groq llama-3.3-70b-versatile → plain-paragraph fallback**. Produces the typed block schema (`app/models/card.py`, `SCHEMA_VERSION`).
   - **Insight** (`pipeline/insight.py`): gated follow-up insight/quiz generation layered on top of the card.
5. Card persisted; `GET /cards/{id}/stream` (SSE) lets the client watch it go from queued → ready live.

### Transcription
- Primary: Groq Whisper (`whisper-large-v3-turbo`, free tier).
- Fallback: **local `faster-whisper`** (no API, no rate limits, model downloads once — tiny/base/small).

### API surface (`app/api/`)
| Router | Endpoints | Purpose |
|---|---|---|
| `cards.py` | `POST /cards`, `GET/PATCH/DELETE /cards/{id}`, `GET /cards/{id}/stream` (SSE), `POST /cards/import`, `POST /cards/{id}/chat` + history, `POST /cards/{id}/rabbithole` + history | Core CRUD + per-card AI chat + "rabbit hole" deep-insight follow-up |
| `catalog.py` | `GET /catalog`, `GET/{id}`, `POST /{id}/save`, `POST /{id}/fetch-info`, `DELETE /{id}` | Artifacts (books/movies/products) referenced across cards |
| `concepts.py` | `GET /concepts`, `GET/{id}`, `POST /{id}/define`, `DELETE /{id}` | Extracted concepts, on-demand AI definitions |
| `collections.py` | `GET/POST /collections`, `PATCH/DELETE /{id}`, `POST /cards/{id}/move` | User-defined card groupings |
| `connections.py` | `GET /connections` | Serendipitous card-to-card links |
| `graph.py` | `GET /graph` | Multi-entity knowledge graph (below) |
| `feed.py` | `GET /feed` | The "Feed" reel-style replay of saved knowledge |
| `library_chat.py` | `POST/GET /chat` | Chat over the whole library (not just one card) |
| `search.py` | `GET /search` | Semantic (embeddings) + full-text fallback |
| `presenter.py` | `POST /presenter/ask` | Powers the in-app "Present" mode — answers audience questions/tasks server-side (LLM key stays on server) and returns an ordered list of `{say, action}` beats so the browser agent *performs* the answer (navigate, search, drive the graph, etc.), not just speaks it |

### Knowledge graph (`app/api/graph.py`)
- Nodes: cards + catalog artifacts.
- Edges: **semantic similarity** (cosine over embeddings, boosted by shared tags), **reference edges** (artifact ↔ referencing cards), **tag edges** (shared tags below the semantic threshold).
- Clustering: pure-Python **label propagation**, auto-labels each cluster.
- Layout: computed **client-side** in Flutter — a live Obsidian-style force-directed physics sim (repulsion + spring + center + damping). Server only returns topology + cluster metadata.
- Cached in-memory, keyed by a fingerprint of the underlying data (card count + latest `updated_at` + artifact count); invalidates automatically on change.

### Feed (`app/services/feed.py`)
Turns your saved cards into a shuffled "moments" stream:
- `insight` (one-liner/TL;DR), `highlight` (punchy body line), `quiz` (stored quiz question), `thread` (rabbit-hole entry), `connection` (serendipitous cross-card link).
- Everything except `connection` reuses data already on the card — **zero LLM cost**. Connections reuse cached serendipity links, topping up a small bounded number of new ones per load.
- Moments interleaved so consecutive items rarely repeat a card.

### Serendipity engine (`app/services/serendipity.py`)
Finds "surprising but genuine" links between two cards: mid-band embedding similarity (`0.26`–`0.66` — related enough, not near-duplicate) with a cross-content-type bonus (e.g. a recipe and a startup video). One cheap LLM call explains the link; results cached in the `connections` table, `max_new` bounds spend per request.

### Data models (`app/models/`)
- `card.py` — `Card`, `CardState` (queued/processing/ready/failed), `FailureReason`, `ContentType`, and the **typed block schema** (`SCHEMA_VERSION = "1.6"`): `HeadingBlock`, `ParagraphBlock`, `BulletListBlock`, `StepListBlock`, `KeyValueBlock`, `ChecklistBlock`, `CalloutBlock` (with `confidence` + `source_url`), `LinkBlock`, `MapBlock` (lat/lng places), `TableBlock`.
- `concept.py` — `Concept`, `ConceptEntry` (name, definition, linked source cards).
- `artifact.py` — `Artifact`/`CatalogEntry` (type, creator, year, thumbnail, source cards).
- `job.py` — `JobState` enum (the job-queue lifecycle).

### Storage (`app/store/`)
- `db.py` — async SQLite via `aiosqlite` (swappable to Postgres/Neon via `DATABASE_URL`). On a serverless Postgres that bills compute by the hour and suspends when idle, background work on a fixed timer is expensive; the worker's idle backoff exists for that reason.
- `media.py` — local file/media management; optional persistent media via a Hugging Face Dataset repo (`hf_media_repo` + `hf_api_key`).

### Config (`app/config.py`)
`pydantic-settings`, all env-driven (`.env`). Every external dependency has an `_enabled` property so the pipeline can check availability and degrade gracefully: `groq_enabled`, `cerebras_enabled`, `gemini_*_keys` (7-account pool for spare quota), `nvidia_vision_enabled`, `local_whisper_enabled`, `hf_media_enabled`.

### Misc
- `discovery.py` — UDP broadcast responder so phones on the same LAN can auto-discover the API server (no manual IP entry).

## 4. Frontend architecture (`/app/lib`)

- **Pattern**: MVVM via `provider` + `ChangeNotifier`.
- `ui/core/` — shell (`home_shell.dart`), navigation gate (`root_gate.dart`), design tokens/branding (`brand.dart`, `theme.dart` — Google Fonts, `flutter_animate` motion).
- `ui/features/` — one module per feature: `library`, `reader`, `capture`, `catalog`, `concepts`, `graph`, `search`, `share`, `collections`, `actions`, `feed`, `profile`, `onboarding`, `blocks` (block-type renderers).
- `data/repositories/` — HTTP client to the FastAPI backend + SSE stream parsing; local disk caching via `shared_preferences`; native share-intent receiver (`receive_sharing_intent`) so the OS share sheet can hand URLs to Cachy directly.
- `domain/models/` — Dart models mirroring the backend Pydantic schemas.
- Action layer: `share_plus`, `url_launcher`, `add_2_calendar` — export/shopping-list → OS share sheet, save-place → Maps, reminder → native calendar event. Library export as an Obsidian vault (`.zip` of markdown via `archive`).

### Present mode (self-driving demo agent)
Built into the web app so it ships with the deployed HF Space — open the URL, click
**Present**. A Siri-like glowing glyph floats in the corner and becomes the agent: it
speaks each segment via the browser's Web Speech API (free, any OS, no install) while
**operating the app across every feature area**. The scripted tour walks the whole
product end-to-end — create a card from a U R L and watch it stream in, tick a step off
in the reader, run + filter search, scroll/reshuffle the Feed, drive the graph (wander,
focus a node, filter a cluster, toggle concept hubs, recenter), define a concept, browse
the catalog, create a folder and move a card into it, follow a card's to-dos and tick one
off in the Actions hub, ask a single card a question, fall down a rabbit hole, chat across
the whole library, surface serendipitous connections, and show the profile/export. Tap
the glyph any time to hand it a question or task: it interrupts, posts to
`POST /presenter/ask` (LLM runs server-side via the same free-first chain), which returns
a sequence of `{say, action}` beats it **performs** live, then resumes the tour. Every
action degrades gracefully — empty data or a failed call yields a spoken fallback and the
presentation continues.
- Frontend: `app/lib/ui/features/presenter/` — `agent_bus.dart` (the command channel:
  shell navigation/open callbacks + per-screen imperative hooks for graph, feed, search,
  and reader), `presenter_controller.dart` (tour beats + TTS with natural-voice selection
  + barge-in state machine + the full action executor + fuzzy target resolution),
  `presenter_overlay.dart` (the glowing glyph + expandable ask/task panel). Launched from a
  "Present" chip in `home_shell.dart`, which wires the bus callbacks and renders reader /
  graph / search / catalog / concepts / connections / concept-detail / card-chat /
  library-chat / rabbit-hole under the glyph. Heavier or overlay screens (chat, library
  chat, rabbit hole, concept detail) are driven by seeding their existing auto-run entry
  points rather than new hooks. Interactive screens attach/detach their hooks on
  mount/unmount so the agent only ever drives what's on screen.
- The frontend action vocabulary and the backend `POST /presenter/ask` validator share the
  same verb set, so any answer the backend returns is executable.
- A separate `presenter/agent.py` at the repo root is an older **macOS-only local variant**
  (uses `say` + `osascript` to drive a local Chrome) — superseded by the in-app mode; kept
  for local Mac dev.

## 5. Running it locally

- Full stack: `./start.py` (FastAPI on :8000 + Flutter web in Chrome, `--dart-define=CACHY_API_BASE=http://localhost:8000`).
- Backend only: `cd backend && .venv/bin/uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`
- Backend tests: `cd backend && .venv/bin/pytest`
- Frontend only: `cd app && flutter run -d chrome --dart-define=CACHY_API_BASE=http://localhost:8000`

## 6. Notable recent work (per git log)

- DB fixes.
- "Feed" and "Serendipity" — the reel-style knowledge replay and the cross-card surprise-connection engine (sections above).
- Chat history (per-card + whole-library chat).
- Processing-state UI ("glyph") polish, broad UI/brand pass.
