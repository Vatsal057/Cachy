# Presenter naturalness + widget-anchored spotlight

Date: 2026-07-02. Approved directions (user): hand-rewritten script, widget-anchored spotlight, spotlight visible for the whole beat.

## Problems

1. **Robotic tour.** Beats speak a full line, then act in silence. Lines read like docs; acronyms spelled with spaces ("U R L") show ugly in captions; no breathing room between beats.
2. **Broken spotlight.** `RectTween(begin: rect, end: rect)` never animates; the `_Guidance` subtree unmounts whenever focus clears, so every appearance restarts from scratch; rects are hardcoded screen fractions; spotlight only shows during action execution (a flash), not while narrating.
3. Fallback `_speak` calls inside actions can deadlock once speech and actions overlap (the old `_speakCompleter` is replaced and never completes).

## Design

### Spotlight target registry (AgentBus)
- `AgentBus` gains `registerSpotlight(id, GlobalKey)` / `unregisterSpotlight` / `Rect? spotlightRect(id)` (resolved live from `RenderBox.localToGlobal` — widget geometry *is* available on Flutter web).
- Screens tag their key widget where they already attach agent hooks and unregister in `dispose`:
  - `home_shell`: `nav` (bottom pill / side rail)
  - `search_screen`: `search.field`, `search.filters`
  - `graph_screen`: `graph.canvas`
  - `knowledge_feed_screen`: `feed.page`
  - `reader_screen`: `reader.body`
- Unresolved / unregistered targets fall back to the existing coarse region rects.

### Whole-beat focus (PresenterController)
- Focus is set at the *start* of a beat (target id derived from the action type, optional explicit `focus` on `AgentBeat`) and persists until the next beat replaces it — the spotlight glides target-to-target like a tour guide's pointer. Cleared on idle/questions/done.
- Speech and action overlap: speech starts, action fires ~500 ms in, beat ends when both finish. Barge-in semantics unchanged (generation token).
- In-action fallback `_speak` calls become caption-only updates (deadlock fix).
- ~450 ms breather between beats.

### Spotlight rendering (PresenterSpotlight)
- Stateful; guidance layer stays mounted so `TweenAnimationBuilder<Rect?>` retargets and actually glides between targets. Fade in/out via opacity only.
- Light poll (~150 ms) while focus is active re-resolves the rect, so late-mounting screens get hugged once they lay out.
- Hole hugs the real widget (inflate ~8, radius 16); cursor glides to the target centre; soft glow ring kept.

### Script rewrite (kTour) + backend tone
- All lines rewritten conversationally: contractions, transitions, reactions, no spelled-out acronyms (reworded instead). Same beat/action structure.
- `backend/app/api/presenter.py` system prompt updated: casual spoken tone, short sentences, no letter-spelled acronyms.

## Out of scope
Per-widget spotlight for every element (only the 6 anchors above); LLM-generated narration; mobile-native TTS tuning.

## Testing
`cd app && flutter test`; `cd backend && .venv/bin/pytest`; manual run via `./start.py`.
