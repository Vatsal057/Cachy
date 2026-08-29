---
title: Cachy
emoji: 🧠
colorFrom: purple
colorTo: blue
sdk: docker
pinned: false
---

# Cachy 🧠

**Reel-to-knowledge.** Share an Instagram Reel, TikTok, YouTube Short, or article — get back a structured knowledge card: a one-liner, TL;DR, and typed content blocks (steps, facts, checklists, tables), plus the concepts and artifacts (books, movies, products) mentioned in it.

Your cards link to each other through a semantic knowledge graph, and a reel-style **Feed** replays your own saved knowledge back to you — so your library becomes a knowledge garden, not a bookmark graveyard.

**Try it:** [vatxzz-cachy.hf.space](https://vatxzz-cachy.hf.space) · **Android APK:** [latest release](../../releases/latest)

## Features

- **Share → card in seconds** — share sheet on Android, paste a link on web; watch the pipeline stream progress live (SSE)
- **Typed knowledge blocks** — steps, key-value facts, checklists, callouts, maps, tables — not a wall of summary text
- **Knowledge graph** — Obsidian-style force-directed graph linking cards by semantic similarity, shared tags, and referenced artifacts, with auto-labeled clusters
- **Feed** — insights, highlights, quizzes, and serendipitous cross-card connections replayed reel-style, at zero extra LLM cost
- **Chat** — with a single card, or across your whole library
- **Concepts & catalog** — extracted concepts get on-demand AI definitions; mentioned books/movies/products collect into a browsable catalog
- **Free-first** — every AI dependency has a fallback chain (Gemini → Cerebras → Groq → local); missing keys degrade gracefully, never fail the job

## Architecture

Dual-client: a **Flutter** app (`/app`, web + Android) talking to an async **FastAPI** backend (`/backend`) over REST + Server-Sent Events.

- Single SQLite DB, in-process async job worker — no Redis, no Celery, deploys as one free HF Space
- Ingestion via `yt-dlp` / `instaloader` / `trafilatura`; keyframe OCR with `pytesseract` + OpenCV; transcription via Groq Whisper with local `faster-whisper` fallback
- Card generation LLM chain: Gemini 2.5 Flash → Cerebras Llama 3.3 70B → Groq Llama 3.3 70B → plain-paragraph fallback
- Pure-Python graph clustering (label propagation); force-directed layout computed client-side in Flutter

See [CACHY_OVERVIEW.md](CACHY_OVERVIEW.md) for the full technical breakdown.

## The database kept running out of quota

The Space lost its database part-way through every month. No traffic spike, plenty
of storage left. It reads like a quota problem and it was a polling problem.

The in-process job worker asked the jobs table for work **every second**, whether
or not anything was queued. Neon's free plan suspends compute after 5 minutes idle
and allows 100 CU-hours a month, which is roughly 400 hours at the 0.25 CU floor
against about 730 hours in a month. Polling once a second means it never gets five
quiet minutes, so it never suspends. That is ~86,400 empty checks a day, ~2.6M a
month, and the whole allowance gone in about **17 days** of an app nobody was using.

The loop now waits on an `asyncio.Event` that `POST /cards` fires once the job row
is committed, and doubles its wait up to 30 minutes while the queue is empty. Job
pickup is as fast as it was, because the enqueue path wakes the worker directly.

My first ceiling was 6 minutes and getting that wrong is the part worth keeping.
It clears the 5-minute window, so it looked right, and it drops the query count by
99.7%. But every query restarts the suspend timer, so at interval `P` the compute
stays awake `min(P, S)/P` of the time. At 6 minutes that is **83% awake**, 608
hours a month, which moves the failure from day 17 to day 20 and calls it fixed.
Fewer queries and less compute turned out to be two different problems. At 30
minutes it is 17% awake, about 122 hours, with room to spare.

Moving to a provider that does not meter compute would have made the symptom go
away and left the 2.6M queries running, so the provider stayed.
`worker_idle_max_seconds` in `backend/app/config.py` carries the arithmetic, and
`backend/tests/test_worker_idle.py` asserts the awake fraction against the budget
rather than just checking the interval beats five minutes, so the 6-minute version
cannot quietly come back.

## Run it yourself

### Full stack (backend + web frontend)

```bash
./start.py
```

### Backend alone

```bash
cd backend && .venv/bin/uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API keys (all optional — missing ones fall back) load from `.env`; see `backend/app/config.py`.

### Flutter app

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=CACHY_API_BASE=http://localhost:8000
```

### Docker (as deployed on HF Spaces)

```bash
docker build -t cachy . && docker run -p 7860:7860 cachy
```

## License

MIT — see [LICENSE](LICENSE)
