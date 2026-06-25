# 12 — Catalog & Artifacts

A second top-level space alongside the card Library: a **catalog** of the
real-world things videos *reference* — books, movies, podcasts, music, products,
places — deduplicated across every card and shown as a wall of covers.

This is a **parallel surface to the block schema, not a new block type**. The
block vocabulary (docs/04) is unchanged. Structuring's output simply grows an
`artifacts` list, which the worker aggregates into a global catalog.

## What an artifact is

A concrete, named thing the video mentions, distinct from the how-to content of
the card itself. A booktuber's video *is* a `tip`/`product_list` card **and**
contributes its named books to the catalog.

```json
// artifact (as emitted by structuring, per card)
{ "type": "book|movie|tv_show|podcast|music|product|place|app|other",
  "title": "Atomic Habits",
  "creator": "James Clear",   // author / director / artist / host / brand (nullable)
  "year": 2018 }              // nullable
```

## Pipeline fit (one LLM call, still)

Artifact extraction piggybacks on the **existing single text-only structuring
call** (docs/04) — the prompt gains an `artifacts` field in its JSON output. No

```
structuring LLM → { base, blocks, artifacts }
  → validate blocks      (docs/04, unchanged)
  → validate artifacts   (drop title-less / malformed; dedupe within the card)
  → worker: for each artifact
       → resolve thumbnail (free image API, best-effort)
       → upsert into the global catalog (dedupe by type + normalized title)
```

Artifacts are validated like blocks: never trusted raw. A malformed entry is
dropped; an empty list is normal. Artifact failure never affects the card —
the card still reaches READY.

## Thumbnails (free, keyless, hotlinked)

`services/artifact_images.py` routes by type to a public, no-key API and returns
a remote `https` URL (nothing is downloaded or stored — fits the ephemeral
free tier). Best-effort: any miss/timeout/error → `None` → typed placeholder.

| Artifact type | Source | Key? |
|---|---|---|
| book | Open Library (cover by id/isbn), Wikipedia fallback | no |
| movie / tv_show / podcast / music / app | iTunes Search API (`artworkUrl`) | no |
| product / place / other | Wikipedia REST summary thumbnail | no |

## Aggregation & dedupe

A global `artifacts` table (docs/08 style: one row per catalog item). Dedupe key
is `(type, normalized_title)`. Re-seeing the same artifact in another card appends
that `card_id` to `source_card_ids` and backfills any missing thumbnail/creator/
year rather than creating a duplicate.

## API

```
GET    /catalog            list entries (optional ?type=, paginated)
GET    /catalog/{id}       one entry + its source_card_ids
DELETE /catalog/{id}       remove an entry (data ownership)
```

`CatalogEntry`:

```json
{ "id": "a_xxxxxxxx", "type": "book", "title": "Atomic Habits",
  "creator": "James Clear", "year": 2018,
  "thumbnail": "https://covers.openlibrary.org/...",
  "source_card_ids": ["uuid", "uuid"], "created_at": "ISO-8601" }
```

## Frontend

A second tab in the root `NavigationBar` (Library | Catalog). The Catalog screen
shows entries grouped by type, each a cover tile with title + creator·year. Covers
load via `Image.network` and degrade to a typed icon placeholder on error — never

## Schema version

Adding `artifacts` to the structuring/card contract bumps `SCHEMA_VERSION`
**1.0 → 1.1**. The block vocabulary is unchanged, so existing cards and the
renderer are unaffected; the client tolerates the new version (it never hard-fails
on a version it doesn't recognize).
