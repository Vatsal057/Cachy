# Reel-to-Knowledge App — Documentation Set

This folder is the complete design documentation for the app: a mobile tool that
turns short-form videos (Instagram Reels, TikTok, YouTube Shorts) shared to it
into structured, readable, actionable knowledge cards — so watching feels
productive instead of disposable.

## How to read these docs

Start at `00-overview.md`, then read in order. The keystone document is
`04-structuring-and-schema.md` — the block schema is the contract between
backend and frontend, and most other docs depend on it.

| File | What it covers |
|------|----------------|
| `00-overview.md` | Product summary, the two usage modes, design principles |
| `01-architecture.md` | System architecture, components, the share→card pipeline, state machine |
| `02-ingestion.md` | The resolver cascade, how downloading works, integration |
| `03-extraction.md` | ffmpeg + Whisper + Gemini; turning media into raw signal |
| `04-structuring-and-schema.md` | **The block schema contract** (the keystone) |
| `05-backend.md` | FastAPI structure, endpoints, job queue, storage, deployment |
| `06-frontend.md` | Flutter structure, screens, share extension, card renderer |
| `07-visual-design.md` | The two-tier visual system (content-visuals vs design-visuals) |
| `08-data-model.md` | Database schema: cards, blocks, jobs, collections |
| `09-features.md` | Full feature list by area |
| `10-phasing-and-roadmap.md` | Phase 1 → 3 build order |
| `11-assumptions-and-open-decisions.md` | What was assumed + what you still must decide |
| `CLAUDE.md` | Ready-to-drop Claude Code project memory file |

## Status

Draft v1. The product/design decisions are settled enough to begin Phase 1.
Open items (hosting/budget, accounts model, push strategy) are defaulted and
flagged in `11-assumptions-and-open-decisions.md` for your confirmation.

## Using this with Claude Code

Drop the whole folder into `/docs` in your repo. Move `CLAUDE.md` to the repo
root. Then point Claude Code at `@docs/04-structuring-and-schema.md` and
`@docs/05-backend.md` (or `06-frontend.md`) when working a specific phase.
Keep `CLAUDE.md` lean — it references these docs rather than duplicating them.
