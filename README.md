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
