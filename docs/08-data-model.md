# 08 — Data Model

Relational. SQLite (dev) / PostgreSQL (prod). Blocks are stored as structured
JSON on the card rather than a table-per-block-type — the vocabulary is fixed and
always read/written together, so one JSON column is simpler and avoids joins.

## Tables

### cards
| column | type | notes |
|--------|------|-------|
| id | uuid PK | |
| state | enum | queued / processing / ready / failed |
| failure_reason | text null | |
| source_url | text | indexed; used for dedup cache |
| platform | text | instagram / tiktok / youtube |
| creator | text null | |
| caption | text null | |
| duration_seconds | int null | |
| resolver | text null | which resolver succeeded (metrics) |
| content_type | text null | recipe / workout / ... |
| type_confidence | float null | |
| one_liner | text null | base layer |
| tldr | text null | base layer |
| primary_action | jsonb null | { kind, label, payload } |
| blocks | jsonb | ordered block list (schema in 04) |
| thumbnail | text null | media ref |
| keyframes | jsonb null | list of media refs |
| schema_version | text | e.g. "1.0" |
| created_at | timestamp | |
| updated_at | timestamp | |
| owner_id | uuid null | null until accounts exist (see 11) |

Indexes: `source_url` (dedup), `state`, `content_type`, `created_at`.

### jobs
| column | type | notes |
|--------|------|-------|
| id | uuid PK | |
| card_id | uuid FK → cards | |
| state | enum | queued / processing / done / failed / dead |
| attempts | int | for retry/dead-letter |
| last_error | text null | |
| created_at | timestamp | |
| started_at | timestamp null | |
| finished_at | timestamp null | |

(If using a DB-backed queue, this table *is* the queue. If using Redis, this is
just an audit record.)

### collections
| column | type | notes |
|--------|------|-------|
| id | uuid PK | |
| name | text | |
| owner_id | uuid null | |

### card_collections (join)
| card_id | uuid FK |
| collection_id | uuid FK |

### tags / card_tags
Auto-tagging populates tags; `card_tags` joins them to cards. (Phase 2.)

### users (Phase 2)
Added when accounts arrive. Until then cards are device-scoped (see `11`).

## User-mutable state

Stored on the card and updated via `PATCH /cards/{id}`:
- checklist `checked` flags (lives inside `blocks` JSON)
- collection membership, tags

## Media lifecycle

- Keyframes + thumbnail: kept (they're the card's content-visuals).
- Source video: may be discarded after extraction to save space (decision in `11`).
- On `DELETE /cards/{id}`: remove card row, derived data, and all media refs.

## Search (Phase 2/3)

- Full-text over one_liner + tldr + block text.
- Semantic: an embedding per card (over tldr + block text) in a vector index for
  semantic search and chat-over-library. Embedding model: a free/local option to
  keep with the no-cost stack (flagged in `11`).
