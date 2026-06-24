# CLAUDE.md

Project memory for Claude Code. Kept lean on purpose — detailed specs live in
`/docs`; reference them with `@docs/<file>` when working a relevant area.

## What this is

A mobile app + backend that turns shared short-form videos (Instagram Reels,
TikTok, YouTube Shorts) into structured, readable, actionable knowledge cards.
Frontend: Flutter. Backend: Python/FastAPI, async job pipeline. Deploys to
**Hugging Face Spaces (Docker, free tier)** — assume ephemeral filesystem,
CPU-only, Groq hosted Whisper for transcription.

## Where things are

- `@docs/04-structuring-and-schema.md` — the block schema. **The backend↔frontend
  contract. Conform to it on both sides; it is the source of truth.**
- `@docs/01-architecture.md` — pipeline + state machine.
- `@docs/05-backend.md` / `@docs/06-frontend.md` — per-side structure.
- `@docs/02-ingestion.md` — the resolver cascade.
- `@docs/11-assumptions-and-open-decisions.md` — defaulted/open choices.

## Hard rules

- **Surgical changes only.** Smallest change that does the job. No unsolicited
  rewrites, no inflated diffs, no reformatting untouched code.
- **Do not touch `ingestion/resolvers.py` internals.** Those scrapers are fragile
  and "just work"; only the `downloader.py` orchestration layer is yours to change.
- **The schema is the contract.** Any block-shape change updates
  `@docs/04-structuring-and-schema.md` and bumps `schema_version`.
- **Always validate LLM output** before persisting; fall back to a paragraph block.
  A card must always render something sane.
- **The share path is transparent.** `POST /cards` returns immediately, but the client connects to an SSE stream to show pipeline progress to the user.
- **Free-first stack.** Prefer free/local tools (faster-whisper, ffmpeg, Gemini
  free tier). Flag anything that would incur cost before adding it.

## Commands

<!-- Fill these in once the project is scaffolded. -->
- Backend dev: `<uvicorn app.main:app --reload>`
- Backend test: `<pytest>`
- Frontend run: `<flutter run>`
- Frontend test: `<flutter test>`

## Conventions

- Backend: type hints + Pydantic schemas mirroring the block vocabulary.
- Frontend: a sealed `Block` type with one widget per vocabulary entry; unknown
  block types degrade gracefully, never crash.
- Work in plan mode for anything touching the pipeline or schema; show the plan
  before executing.
