# 06 — Frontend

Flutter. The client is share-in, library, reader, and actions. It holds no heavy
processing — all extraction/structuring is backend. Its hardest jobs are the
**share extension** (must be invisible) and the **block renderer** (must draw the
schema vocabulary and stream progressively).

## Project layout

```
app/lib/
  main.dart
  core/
    api_client.dart        # talks to FastAPI
    models/                # Card, Block (mirror 04-...-schema.md exactly)
    block.dart             # sealed Block type + fromJson dispatch
  features/
    share/                 # share-extension receiver + enqueue
    library/               # visual grid of cards (with states)
    reader/                # card view + progressive render
    blocks/                # one widget per block type (the renderer)
    actions/               # shopping list, schedule, reminder, export
    search/                # search + chat (phase 2/3)
  design/
    theme.dart             # color system, type scale, motion tokens
    components/            # shared visual components
```

## Screens

### Share receiver (Visible Pipeline)
Registered as a share target for Instagram/TikTok/YouTube. On receive:
The OS opens the app immediately. The app POSTs the URL to `/cards`, gets a `card_id`, and subscribes to the pipeline stream. It displays the progression (Downloading → Extracting → Structuring) so the user sees the work happening instead of waiting blindly.

### Library (visual grid, not a list)
Cards as a grid of thumbnails — each card has a real face (keyframe), never a row
of text. Shows state badges (queued / processing / ready / failed). This is the
first place the "heavily visual" principle shows up: a browsable wall of images,
not a feed of text. Sort/filter by recency, type, collection, tag.

### Reader (progressive)
Opens directly on the shared card (even mid-processing in read-now). Renders
top-down as content arrives:

1. one_liner + tldr render first,
2. blocks fill in beneath,
3. thumbnail/keyframes attach.

Multi-depth layout: instant layer (one_liner) always visible; skim layer
(takeaways/steps) below; depth layer collapsed/expandable. The `primary_action`
is the visually dominant control. Lightweight placeholders for not-yet-arrived
content — never one blocking spinner.

## The block renderer (core)

A sealed `Block` type with one widget per vocabulary entry. The renderer maps a
block list to a column of widgets. It only ever needs to know the fixed
vocabulary from `04`:

| block | widget behavior |
|-------|-----------------|
| heading | section header at `level` |
| paragraph | prose |
| bullet_list | bulleted items |
| step_list | ordered; each step a checkable row |
| key_value | label/value pairs (compact grid) |
| checklist | checkable items, **persist checked state** (PATCH card) |
| callout | tinted box by `variant`; shows `confidence` + optional source link |
| link | tappable link chip |
| map (P2) | embedded map with pins |
| table (P2) | simple table |

Unknown/future block types degrade gracefully: render `text`/`items` if present,
else skip. Never crash on an unrecognized block.

## State & data flow

- Local cache of cards for **offline reading** (cached cards readable with no network).
- Shares made offline are **queued locally** and synced when the backend returns.
- While a card is `queued`/`processing`, the reader polls `GET /cards/{id}`;
  fire-and-forget relies on push/badge instead.
- Checked items and collection/tag edits are optimistic-local then PATCHed.

## Visual system (see 07)

The renderer is where content-visuals (keyframes, maps, charts) and
design-visuals (color, motion, depth) meet. Discipline: where a content-visual is
present, the surrounding chrome stays calm so the visual carries attention.
