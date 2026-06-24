# 00 — Overview

## One-line

Share any short-form video to the app; it extracts everything meaningful inside
it (spoken audio, on-screen text, visual context, caption) and reshapes that into
a **structured card** the user can read, act on, and keep — so watching feels
productive instead of disposable.

## The problem

Short-form video is engaging but disposable. People save reels they'll never
revisit and consume content they gain nothing lasting from. The value inside a
reel — a recipe, a workout, a tip, a place — is locked in a format that's hard
to act on and impossible to search.

## The product

The app ingests a shared video, runs extraction, and produces a card that is:

- **Readable at multiple depths** — a one-liner you grasp in 2 seconds, takeaways
  you skim in 20, full detail when you want it.
- **Never plain text** — its elements *do things* (checkable steps, mappable
  places, schedulable actions) and it's heavily visual (keyframes, maps, charts).
- **Actionable** — every card surfaces the one thing the reel is asking you to do.
- **Retrievable** — searchable, taggable, and queryable as a personal knowledge base.

## Two usage modes (one output)

These share the same card and differ only in *when* attention arrives.

### Transparent Capture
User shares reels while scrolling, which immediately opens the app to show the pipeline process. The user sees exactly what the app is doing (downloading, extracting, structuring) so they aren't left waiting blindly. They can watch the card build in real-time.

### Read-now
User shares, then immediately opens the app to read the card as a faster
replacement for rewatching. Here the card streams top-down: the one-liner and
TL;DR render first while deeper blocks fill in beneath. Perceived speed matters
more than total completion time.

## Design principles (the non-negotiables)

1. **Transparent capture.** The share path opens the app and visually shows the pipeline's progress. No blind waiting.
2. **Hierarchy over completeness.** A faithful full transcript is boring and feels
   like homework. Lead with the point; bury the depth. Readable in 2 seconds and
   in 2 minutes.
3. **Functional richness, not decoration.** "Not plain text" means elements *do
   things*, not that they have emojis and colors.
4. **Visual-first, with a hierarchy.** Heavily graphical, but in two tiers that
   don't compete: **content-visuals** (keyframes, maps, charts — the video's own
   substance) are the star; **design-visuals** (color, motion, icons) are the
   frame and stay calm where a content-visual is carrying meaning. Rich, not busy.
5. **One next action.** Every card makes clear the single thing the reel asks the
   user to do — and lets them do or schedule it.
6. **Constrained vocabulary, flexible arrangement.** A fixed set of renderable
   block types; content type decides which blocks appear and in what order. New
   content types should rarely require new UI code.
7. **Always produce something.** Even when type detection or extraction partially
   fails, a usable base card (one-liner + TL;DR + source) is always rendered.

## What "productive" actually means here

Productivity isn't a feeling the formatting creates — it's the feeling of having
done the thing the reel was asking of you. A workout reel's job is done when
you've worked out, not when you've read a nice card. The structured text is the
*understanding*; the action is the *productivity*. The card carries both.
