# 10 — Phasing & Roadmap

Build order front-loads a production-quality *core* rather than spreading thin
across half-finished features. Each phase is shippable.

## Phase 1 — MVP (production-quality core)

**Goal:** one platform, end-to-end, genuinely solid. Share a reel → get a good
card → read it → find it later.

- Share-sheet ingestion (Instagram), link paste, batch + dedup
- Async pipeline: queue + worker + state machine
- Ingestion cascade integrated (resolvers + downloader async layer)
- Extraction: ffmpeg + Whisper + Tesseract OCR (conditional HF VLM for visual)
- Single adaptive structuring pass + schema validation + fallback
- Base layer + core block vocabulary (8 blocks)
- Library with card states (visual grid + keyframe thumbnails)
- Reader with progressive render + multi-depth hierarchy
- One primary action per card
- Basic full-text search
- Core visual layer (color/motion/depth, thumbnails)
- Offline reading + offline share queue
- Retry/dead-letter, observability, delete
- "AI-generated" labeling

**Exit criteria:** a reel shared while scrolling reliably becomes a useful card
without the user waiting; a reel shared then opened streams readable content fast;
failures surface gently; nothing silently drops.

## Phase 2 — Breadth & action

- TikTok + YouTube Shorts ingestion
- Action layer: shopping list, reminders/calendar, export (Notion/Obsidian/Notes)
- Richer content-visuals: maps with pins, charts, product thumbnails, step strips
- Map + table blocks
- Collections + auto-tagging
- Semantic search
- Accounts (if chosen — see `11`)

## Phase 3 — Intelligence & retention

- Chat-with-your-library
- Spaced resurfacing engine
- Weekly digest
- Trust/claim-quality signals on health/finance/medical content

## Sequencing logic

- **Schema first.** `04` is the contract; both backend and frontend build against
  it from day one. Highest-leverage thing to lock before code.
- **Pipeline before polish.** A working async share→card→read loop is the spine;
  visuals and actions layer onto it.
- **Keyframe extraction is the cheapest high-impact visual** — it turns the library
  from text rows into something alive to browse, and you're already processing the
  video. Do it in P1.
- **Single-pass structuring stays** until measured quality demands splitting —
  don't pay double on verticals the single pass already handles.
