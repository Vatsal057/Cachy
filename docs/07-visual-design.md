# 07 — Visual Design

The app is heavily graphical on every axis — but visual richness is organized so
it stays **rich, not busy**. The whole system rests on one rule: two tiers of
visuals that must not compete.

## The two tiers

### Content-visuals (the star)
Sourced from the video's own substance. These raise information-per-second, which
is what actually fights boredom — they deliver meaning faster than text could.

- **Keyframe / thumbnail** — every card has a real face pulled from the video.
  The library is a grid of these, not text rows.
- **Result frames** — the finished dish, the setup shot, etc., inline.
- **Maps** — travel/place content as an actual map with pins (P2).
- **Charts** — comparisons and numbers as real charts (P2).
- **Product thumbnails** — product-list items with real images (P2).
- **Visual step strips** — a frame per step where useful (P2).

### Design-visuals (the frame)
The styled UI around the content. Stays **calmer wherever a content-visual is
carrying meaning.**

- **Color system** — coherent palette; optional per-content-type accent (recipe /
  workout / travel) so types are recognizable at a glance without an icon zoo.
- **Motion with meaning** — progressive top-down render as the card builds; smooth
  expand/collapse between skim and depth layers; shared-element transition from
  library thumbnail into the reader.
- **Depth & layering** — cards, elevation, spacing for a tactile, browsable feel.
- **Iconography** — restrained, consistent, tied to block types and actions.
  Never one-icon-per-line clutter.
- **Theming** — light/dark, respects system.

## The discipline (so "maximally visual" stays rich)

- Where a content-visual is present, design-chrome dials down. A keyframe or map
  carries attention — not a gradient behind it.
- One primary action is visually dominant per card; everything else is secondary.
- Animation is fast and purposeful. Nothing the user waits through. No decorative
  loops, no confetti-for-its-own-sake.

## Why not "just add graphics"

Boredom isn't a visual problem — a reel is engaging because it's fast and gives
the point in seconds, not because it's colorful. Heavy decoration (gradients on
everything, an icon per block, animated backgrounds) reads fresh for a week and
becomes noise forever, and it competes with the content that is the actual value.
The richness that lasts is **functional and content-sourced**, not applied on top.

## Motion tokens (starting point)

- Card build-in: fast top-down stagger as blocks arrive.
- Expand/collapse: quick ease, no bounce.
- Library → reader: shared-element on the thumbnail.
- Save/checked: subtle, immediate, reversible — no celebration animation.
