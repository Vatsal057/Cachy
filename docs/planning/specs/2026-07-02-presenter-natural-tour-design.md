# Presenter: natural, click-driven guided tour

Date: 2026-07-02. Target: **web (Chrome via `start.py`)**. Supersedes the naturalness/spotlight direction in `2026-07-02-presenter-naturalness-spotlight-design.md` (the spotlight-only approach it describes is the source of the "magic screen" feel and is replaced here).

## Problem

The Present-mode agent changes screens by `setState`-swapping `_presenterScreen` / switching the tab index (`home_shell._goToView`) and drives widgets through backdoor hooks (`onOpenCard`, `reader.toggleCheck`, `search.run`). A spotlight/cursor glides toward a *guessed* region, but the real state change fires instantly through a side door. Result: screens pop into existence with no visible tap ("magic"), the spotlight snaps/flickers, and some steps stall or crash. The existing `kTour` is a "tour of every room," not the guided narrative the user wants.

User-reported failures: wrong/magic navigation, broken spotlight, crashes/stalls.

## Design

### 1. Every action is a visible gesture

No effect fires until the cursor is on the **real** widget and has pulsed. One choreography for every beat that touches the UI:

```
point(targetId) → cursor glides to the real widget rect (from its GlobalKey) ~450ms, wait for arrival
tap()           → ripple pulse at the cursor / on the widget ~180ms
effect()        → THEN the nav / hook / repo call runs
```

- Reuse the existing `AgentBus` id→`GlobalKey` registry and `spotlightRect(id)`.
- `PresenterController` gains a cursor model: current target rect + a phase (`pointing` → `tapping` → effect). The overlay renders the gliding cursor and the tap ripple. The dim scrim is kept only for genuinely small targets (nav item, a button), not full-screen stages.
- **Navigation is pulled inside the choreography.** `_goToView`, `onOpenCard`, screen hooks, and repo calls are invoked by `effect()` *after* the pulse — so the tapped nav item / card / button is visibly what triggers the change. The controller exposes a single helper (e.g. `_gesture(targetId, effect)`) that all action handlers route through.

### 2. Bugs fixed

- **Spotlight snap.** The ~150 ms poll calls `setState` with `RectTween(begin == end == rect)` each tick, resetting the tween mid-glide. Fix: the poll updates only the *target rect*; the glide is driven by target changes, so a re-resolve of the same target does not restart the animation. Late-mounting screens still get hugged.
- **Speak / barge-in deadlock.** Nested `_speak` inside actions could orphan a completer. Audit every action path so a superseded utterance's completer always completes; in-action fallback narration is caption-only (no second utterance).
- **Stalls.** `_waitFor` targets screens that mount via index-swap; make hook registration + timeouts consistent so a screen/hook that never mounts no-ops (logged) instead of hanging the beat.

### 3. Target registry coverage

Screens register a `GlobalKey` per target in `initState`/`didChangeDependencies` and unregister in `dispose`.

- **Nav:** each tab individually — `nav.home`, `nav.folders`, `nav.todo`, `nav.feed`, `nav.you` (not one `nav` blob).
- **Top icons:** `top.graph`, `top.chat`.
- **Home:** `home.plus` (add button), `card.first` (first card tile).
- **Reader:** `reader.blocks`, `reader.insight` (going-deeper), `reader.references`, `reader.ask`, `reader.primary` (content action), `reader.more` (three-dots).
- **Catalog:** `catalog.item` (first item).
- **Folders:** `folders.create`.
- **To-do:** `todo.item` (first, expandable).
- **Feed:** `feed.page` (already anchored).

Unresolved/unregistered ids fall back to the existing coarse region rects.

### 4. Script (`kTour`) — narrative order

1. **Home.** Greet, then scroll to the end and back, narrating that every shared reel/short/article becomes a stored card.
2. **First card.** Tap `card.first` open → scroll through `reader.blocks` (structured notes from any source) → point at `reader.insight` ("going deeper") → open the **Rabbit hole** ("dive deeper") → point at `reader.references`, explain long-press saves a reference to the catalog → bottom strip: point at **Ask**, the **primary action**, then open the **three-dots** menu (copy / share / shopping-list, etc.).
3. **Concepts.** Open the concepts screen, brief on how concepts are mined and one is defined on demand.
4. **Catalog.** Open catalog → explain items come from saved references → tap `catalog.item` → AI generates its info.
5. **Nav bar, one by one.** Home (already covered) → **Folders** (`nav.folders`): cards auto-categorize into folders; create one live via `folders.create`. → **To-do** (`nav.todo`): items appear when a card is "tracked in actions"; tap `todo.item` to expand a note's items; mention they keep notifying until done. → **Feed** (`nav.feed`): reel-style one-liners of saved knowledge; scroll a few naturally. → **You** (`nav.you`): settings, brief.
6. **Top icons.** **Graph** (`top.graph`): show linked nodes, focus one, interactively. → **Chat** (`top.chat`): talk to the whole library.
7. **Add to Cachy.** Tap `home.plus` → link dialog → paste a link → watch the pipeline stream → the finished note appears. Wrap up.

Lines are written to be spoken: contractions, transitions, no letter-spelled acronyms. Speech leads; the gesture fires ~500 ms in; ~450 ms breather between beats. Barge-in (tap the glyph, ask) interrupts, is performed, then the tour resumes — unchanged from today.

### 5. Deliberate scope calls

- **No "reminder button."** The real `PrimaryActionBar` is Ask + a content-derived primary action + a three-dots More menu. The script narrates exactly that; reminders are mentioned only in the To-do screen where notifications actually happen.
- **Long-press-to-save** is narrated while the save actually fires on the pointed reference (web can't render a finger-hold; the pulse + narration sells it).
- Backend `/presenter/ask` prompt/tone is left as-is.
- Not adding per-widget spotlights beyond the anchors in §3; anything unregistered degrades to a region rect.

## Testing

`cd app && flutter test`; `cd backend && .venv/bin/pytest`; manual run via `./start.py` — tap Present, watch that each screen change is preceded by a visible cursor landing + pulse on the real control, and that the tour follows the §4 order without stalling.
