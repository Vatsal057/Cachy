# 13 — Actions & Chat

How a card becomes *useful*, not just readable. Two surfaces: a **content-aware
action layer** and **grounded chat (Ask)**. Both are additive — no block-schema
change (docs/04 is unchanged); everything is derived from a card's existing
content.

## Action layer

The backend still derives one dominant `primary_action` per card (docs/04). The
client now goes further: it inspects the card's **blocks** and offers every
action that fits, plus a common set on every card. All payloads are built
client-side from blocks, so the wire `payload` stays empty.

| Action | Shown when | Handler (free, on-device) |
|---|---|---|
| Ask | always | opens grounded chat (below) |
| Copy | always | card → markdown → clipboard |
| Share | always | card → markdown → OS share sheet (`share_plus`) |
| Add to calendar | always | native add-event sheet (`add_2_calendar`) |
| Open original | has source url | launches the reel (`url_launcher`) |
| Open in Maps | has a `map`/place block | Maps search/coords (`url_launcher`) |
| Shopping list | has `checklist`/`bullet_list` | items → checkable list → share |
| Open links | has a `link` block | launches the first link |

The dominant `primary_action` is rendered as the big button; the rest live
behind a "more" menu. The reader shows the bar whenever the card is READY (Ask
is available even when there is no primary action).

Frontend: `ui/features/reader/services/card_actions.dart` (`available()`,
`primaryType()`, `perform()`), surfaced by `views/primary_action_bar.dart`.

### Android config

- `url_launcher` https + `add_2_calendar` insert intents are declared in
  `android/app/src/main/AndroidManifest.xml` `<queries>` (Android 11+ package
  visibility).

## Chat (Ask)

Grounded Q&A over a single card. The model answers using **only that card's
structured content** as context; if the answer isn't there, it says so.

```
POST /cards/{card_id}/chat
  body: { "messages": [ { "role": "user|assistant", "content": str }, ... ] }
  → 200 { "reply": str }
  → 409 card is not READY
  → 422 last message is not from the user
  → 503 no LLM backend configured
```

**Stateless.** Nothing is persisted server-side: the client holds the
conversation and replays the full history each turn (capped to the last
`_MAX_TURNS` for cost). Grounding context is the card's `base` (one_liner, tldr)
plus a flattened plain-text view of its blocks.

**Free-first.** Reuses the same selectable backend as structuring
(`llm_backend = huggingface | groq | none`) via `services/llm_chat.py`. With no
key, the endpoint returns 503 and the UI shows an "unavailable" message — the
card still reads and every other action still works.

**Trust.** The chat header carries the standard "AI-generated · may contain
errors" note (docs/09 trust & safety).

Frontend: `ui/features/reader/view_models/chat_view_model.dart` +
`views/chat_screen.dart`, opened from the **Ask** action.
