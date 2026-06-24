# 01 — Architecture

## High-level shape

Three pieces:

- **Mobile client (Flutter)** — share extension, library, card reader, actions,
  search. Holds no heavy processing.
- **Backend service (Python / FastAPI)** — job queue, ingestion, extraction,
  structuring, storage, search.
- **Async job pipeline** — the phone shares, which opens the app to stream pipeline updates (downloading, extracting, structuring) until the result is ready.

```
┌──────────────┐      share / paste       ┌──────────────────────────┐
│ Flutter app  │ ────────────────────────▶│ FastAPI: POST /cards      │
│  - share ext │                          │  enqueue job, return id   │
│  - library   │◀──── card (poll/push) ───│                           │
│  - reader    │                          └────────────┬─────────────┘
└──────────────┘                                       │
                                                        ▼
                                          ┌──────────────────────────┐
                                          │ Worker (job queue)        │
                                          │  download → extract →     │
                                          │  structure → persist      │
                                          └────────────┬─────────────┘
                                                        │
                                   ┌────────────────────┼───────────────────┐
                                   ▼                    ▼                   ▼
                            ingestion          extraction           structuring
                          (resolvers)     (ffmpeg/Whisper)            (Gemini)
```

## The pipeline (share → card)

```
Share / paste
  → Opens app
  → POST /cards : create card (state = QUEUED), enqueue job
  → Client subscribes to SSE stream at GET /cards/{id}/stream
  → Worker picks up job (state = PROCESSING)
      1. ingestion:   download media + caption           (02-ingestion.md)
      2. extraction:  ffmpeg → audio + keyframes
                      Whisper → transcript
                      (OCR + visual via Gemini)           (03-extraction.md)
      3. structuring: Gemini → validated block list       (04-...-schema.md)
      4. persist:     save card + blocks + media refs
  → state = READY  (or FAILED with a reason)
  → Stream pushes updates to client at each step so user sees progress.
```

## Card state machine

```
QUEUED ──▶ PROCESSING ──▶ READY
   │            │
   └────────────┴──▶ FAILED (reason: unavailable | no_content | unsupported | timeout)
```

- **QUEUED** — accepted, not yet started. Shows as a pending card in the library.
- **PROCESSING** — worker is running it. In read-now, partial content may stream.
- **READY** — card complete and renderable.
- **FAILED** — surfaced gently via the streaming progress UI. Always carries a reason.

## Progressive rendering (read-now)

The card persists incrementally so the reader can stream it:

1. `base` (one-liner + TL;DR + source) is written as soon as structuring returns
   the head of its output.
2. `blocks` fill in beneath.
3. `media` (thumbnail/keyframes) attaches when extraction finishes.

The client renders whatever is present and shows lightweight placeholders for
what's still arriving — never one blocking spinner over the whole card.

## Concurrency

Multiple jobs run in parallel. Two consequences baked into the design:

- Each download gets an **isolated job directory** (see `02-ingestion.md`) so
  media files never collide.
- The job queue + worker pool size is a deployment knob; Whisper is the heaviest
  step and effectively sets per-worker memory/CPU needs.

## Reliability requirements

- Retry transient extraction failures; dead-letter jobs that can't complete.
- No silent drops — every job ends in READY or FAILED with a recorded reason.
- Cached cards readable offline on the client; shares queued locally if the
  backend is unreachable and synced when it returns.
- Observability: success rate per resolver, processing time per stage, failure
  reasons. (Which resolver succeeded is recorded on every card.)
