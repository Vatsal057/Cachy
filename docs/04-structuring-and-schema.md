# 04 — Structuring & the Block Schema (keystone)

This is the contract between backend and frontend. The backend produces cards in
exactly this shape; the frontend renders exactly these block types. Getting this
right is what prevents the schema-mismatch drift that plagues backend↔frontend
work. **Treat this file as the source of truth; both sides conform to it.**

## Principle

A fixed, small **vocabulary** of renderable blocks. The content type does not
select a rigid template — it shapes the *arrangement* of these shared primitives.
The model emits an ordered list of blocks; the renderer only ever needs to know
how to draw the vocabulary. Adding a new content type is usually a prompt change,
not new UI code.

## Card object

```json
{
  "schema_version": "1.1",
  "card_id": "uuid",
  "state": "queued | processing | ready | failed",
  "failure_reason": null,

  "source": {
    "url": "https://...",
    "platform": "instagram | tiktok | youtube",
    "creator": "@handle",
    "caption": "",
    "duration_seconds": 30,
    "resolver": "vidssave"
  },

  "base": {
    "one_liner": "3 ways to cut your AWS bill",
    "tldr": "Short standalone summary the card can be understood by alone.",
    "content_type": "recipe | workout | tutorial | tip | product_list | travel | news_explainer | other",
    "type_confidence": 0.0
  },

  "primary_action": {
    "kind": "shopping_list | schedule | save_place | reminder | export | none",
    "label": "Add to shopping list",
    "payload": {}
  },

  "blocks": [],

  "media": {
    "thumbnail": "url_or_path",
    "keyframes": ["url_or_path"]
  },

  "meta": {
    "created_at": "ISO-8601",
    "extraction": { "transcript": true, "ocr": true, "visual": true }
  }
}
```

### Unconditional base layer
`base.one_liner`, `base.tldr`, and `source` are **always present**, regardless of
type-detection success. A card that confuses the type logic still renders usefully.

- `one_liner` describes what the reel *gives you*, not what it's *about*.
  Good: "3 ways to cut your AWS bill." Bad: "A video discussing cloud costs."
- `tldr` must let the card stand alone later, when the user has forgotten the reel.

## Block vocabulary

Every block has `type` and `id`. Type-specific fields below. Phase-2 blocks marked.

```json
// heading
{ "type": "heading", "id": "b1", "text": "Ingredients", "level": 2 }

// paragraph
{ "type": "paragraph", "id": "b2", "text": "Plain prose." }

// bullet_list
{ "type": "bullet_list", "id": "b3", "items": ["point one", "point two"] }

// step_list  (ordered; steps are individually checkable in the UI)
{ "type": "step_list", "id": "b4",
  "steps": [ { "text": "Preheat oven to 200C", "checkable": true } ] }

// key_value  (sets/reps, prep time, price, specs)
{ "type": "key_value", "id": "b5",
  "pairs": [ { "key": "Prep time", "value": "15 min" },
             { "key": "Serves",    "value": "4" } ] }

// checklist  (shopping, packing — persists checked state)
{ "type": "checklist", "id": "b6",
  "items": [ { "text": "Olive oil", "checked": false } ] }

// callout  (caveats, warnings, source notes; carries a confidence signal)
{ "type": "callout", "id": "b7",
  "variant": "info | warning | caveat | source",
  "text": "Creatine claims are widely supported.",
  "confidence": "high | medium | low | unverified",
  "source_url": null }

// link
{ "type": "link", "id": "b8", "url": "https://...", "label": "Original study" }

// map   (PHASE 2)
{ "type": "map", "id": "b9",
  "places": [ { "name": "Cafe X", "lat": 12.97, "lng": 77.59, "note": "" } ] }

// table (PHASE 2)
{ "type": "table", "id": "b10",
  "headers": ["Item", "Price"], "rows": [["A", "$5"], ["B", "$9"]] }
```

## How content types map to blocks (illustrative, not enforced)

| content_type | typical block arrangement |
|--------------|---------------------------|
| recipe | heading → key_value(time/serves) → checklist(ingredients) → step_list(steps) |
| workout | heading → key_value(sets/reps) → step_list(exercises) |
| tutorial | heading → step_list → callout(tip) |
| tip | paragraph(tldr) → bullet_list(takeaways) → callout(caveat) |
| product_list | bullet_list or table → link(s) |
| travel | heading → map → bullet_list |
| news_explainer | paragraph → bullet_list(key points) → callout(source) |
| other | paragraph + bullet_list (the safe fallback) |

## Primary action mapping

`primary_action.kind` is derived from content type:

| content_type | primary action |
|--------------|----------------|
| recipe | shopping_list (from the ingredients checklist) |
| workout | schedule (a session) |
| travel | save_place (places → map) |
| tutorial / tip | reminder (or export) |
| product_list | export |
| other | none |

## The LLM output contract

The structuring call is a **single text-only LLM call** — always. The default
backend is **HuggingFace Inference Providers** (`Qwen/Qwen2.5-72B-Instruct`), with
**Groq** (`llama-3.1-70b-versatile`) as a selectable fallback; both are text-only.
All vision (OCR, scene description) is handled upstream (see `03`), so the
structuring call never carries images. It receives the aggregated text bundle and
returns **only** a JSON card object matching this schema — no prose, no markdown
fences. The prompt:

1. Provides the aggregated text (caption + transcript + on-screen OCR [+ scene]).
2. Lists the exact block vocabulary and forbids any type outside it.
3. Requires `base.one_liner` and `base.tldr` always be filled.
4. Asks it to choose `content_type` and arrange blocks accordingly.
5. Requires strict JSON output.

## Validation (server-side, before persisting)

Never trust raw model output. After parsing:

- Strip code fences if present; parse JSON; on parse failure → **paragraph fallback**
  (wrap transcript/caption into a single `paragraph` block + a generated `tldr`).
- Drop any block whose `type` is outside the vocabulary (or coerce to `paragraph`).
- Drop blocks missing required fields for their type.
- Ensure `base.one_liner` and `base.tldr` are non-empty; synthesize from transcript
  if the model omitted them.
- Assign stable `id`s if missing.

The guarantee: **a card always renders something sane**, even on a degraded
model response. This validation step is the difference between "occasionally
renders garbage" and "always usable."

## Artifacts (catalog) — separate from blocks

The same single structuring call also emits an `artifacts` list — concrete,
named things the video *references* (books, movies, podcasts, products, places).
These are **not blocks** and never render inside the card; they feed the global
catalog. Validated separately (title required, dedupe, drop malformed). See
`@docs/12-catalog-and-artifacts.md`. Their addition to the structuring output is
what took `schema_version` to `1.1`.

## Versioning

`schema_version` is on every card. When the vocabulary changes, bump it; the
client renders known versions and degrades gracefully on unknown future blocks
(render their `text`/`items` if present, else skip). **1.1** added the
`artifacts` list to the structuring output (block vocabulary unchanged).
