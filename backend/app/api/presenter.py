"""Presenter endpoint: powers the in-app "Present" mode (browser-native).

The Flutter web app runs a self-driving guided tour that *operates* the app —
speaking via the browser's Web Speech API while navigating, creating cards,
searching, scrolling the feed, and driving the knowledge graph. When the
audience asks a question or hands the agent a task, the app posts it here; we
answer with Groq/Cerebras/Gemini server-side (the API key never leaves the
server) and return an ordered list of "beats" — each an optional line to *say*
and an optional *action* to perform — so the agent answers by doing, not just
describing.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel

from app.pipeline.structuring import complete

log = logging.getLogger("api.presenter")
router = APIRouter(prefix="/presenter", tags=["presenter"])

# Views the browser knows how to navigate to (mirrors the app's nav targets).
_VIEWS = {
    "library", "feed", "graph", "search",
    "collections", "actions", "profile", "catalog", "concepts",
}

# Action verbs the Flutter agent knows how to execute (mirrors AgentAction).
_ACTIONS = {
    "navigate", "create_card", "search", "open_card",
    "graph_focus", "graph_open", "graph_wander", "graph_reset",
    "feed_next", "feed_prev", "wait",
}

# Compact, accurate project brief so answers stay grounded without shipping the
# full CACHY_OVERVIEW.md into the Docker image.
_BRIEF = """Cachy turns short-form video (Reels/TikToks/Shorts) and web articles into
structured knowledge cards: each card has a one-liner, a TL;DR, and typed blocks
(steps, key-value facts, checklists, callouts, tables, maps).

Backend: FastAPI + an in-process async worker (no Redis). Pipeline per job:
ingest the URL (yt-dlp/instaloader, or trafilatura for articles) -> extract
keyframes + OCR + transcription -> AI structuring -> persist, streaming progress
over SSE. Storage is SQLite (aiosqlite). The knowledge graph links cards/artifacts
by semantic similarity (embeddings) + shared tags, clustered with pure-Python
label propagation and laid out client-side with a force-directed physics sim.
The Feed replays saved cards reel-style (insights/highlights/quizzes/connections),
mostly zero extra AI cost. Serendipity finds surprising cross-card links.

Free-first design: every AI dependency is optional with a fallback chain
(Gemini 2.5 Flash -> Cerebras llama-3.3-70b -> Groq -> local Whisper / paragraph
fallback), so nothing hard-fails when a key is missing or rate-limited.

Frontend: Flutter (web + mobile), MVVM with provider, talking to the backend over
REST + SSE."""

_SYSTEM = f"""You are a live presenting agent for the Cachy project, speaking to a
classroom through a web app that you can NAVIGATE and OPERATE. When the audience
asks a question or hands you a task, don't just describe things — DEMONSTRATE
them by driving the app, then narrate what's happening.

You reply with an ordered list of "beats". Each beat has:
  - "say": one short sentence to speak aloud (no markdown, spell out acronyms
    like "U R L"), or null to just perform the action silently.
  - "action": one thing to do, or null to just talk.

An action is an object with a "do" field and optional args:
  - {{"do":"navigate","view":"<view>"}}  — view is one of: library, feed, graph,
    search, collections, actions, profile, catalog, concepts.
  - {{"do":"search","query":"<text>"}}   — open search and run a query.
  - {{"do":"open_card","query":"<text>"}} — open the best-matching saved card.
  - {{"do":"graph_focus","query":"<text>"}} — on the graph, zoom into the node
    best matching the text and show its neighborhood. Use "" to auto-pick a hub.
  - {{"do":"graph_open","query":"<text>"}}  — open a graph node's card/concept.
  - {{"do":"graph_wander"}}  — bring the graph physics alive.
  - {{"do":"graph_reset"}}   — recenter the graph.
  - {{"do":"feed_next"}} / {{"do":"feed_prev"}} — move through the feed.
  - {{"do":"create_card","url":"<url>"}} — ONLY if the audience gave a real URL.
  - {{"do":"wait","ms":<n>}} — pause briefly.

Guidance: keep it to 1-3 beats. Prefer performing the relevant feature over
talking about it (e.g. a question about the graph -> navigate to graph then
graph_focus). Never invent a URL for create_card. If the question is purely
conceptual, a single beat with just "say" is fine.

Reply with ONLY a JSON object, no other text:
{{"steps":[{{"say":"...","action":{{"do":"..."}}}},{{"say":"...","action":null}}]}}

Project reference:
{_BRIEF}"""


class AskRequest(BaseModel):
    question: str


class Step(BaseModel):
    say: str | None = None
    action: dict[str, Any] | None = None


class AskResponse(BaseModel):
    steps: list[Step]


def _clean_action(raw: Any) -> dict[str, Any] | None:
    """Validate one action object; drop anything the frontend can't run."""
    if not isinstance(raw, dict):
        return None
    verb = str(raw.get("do", "")).strip()
    if verb not in _ACTIONS:
        return None
    action: dict[str, Any] = {"do": verb}
    if verb == "navigate":
        view = str(raw.get("view", "")).strip().lower()
        if view not in _VIEWS:
            return None
        action["view"] = view
    if verb in {"search", "open_card", "graph_focus", "graph_open"}:
        action["query"] = str(raw.get("query", "")).strip()
    if verb == "create_card":
        url = str(raw.get("url", "")).strip()
        if not url.startswith("http"):
            return None
        action["url"] = url
    if verb == "wait":
        try:
            action["ms"] = int(raw.get("ms", 800))
        except (TypeError, ValueError):
            action["ms"] = 800
    return action


def _parse(raw: str | None) -> AskResponse:
    """Pull the beat list out of the model's reply, tolerating code fences and a
    plain-text answer (fallback: speak the raw text as one beat)."""
    fallback = AskResponse(
        steps=[Step(say="Sorry, I couldn't come up with an answer for that.")]
    )
    if not raw:
        return fallback
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("```", 2)[1] if text.count("```") >= 2 else text.strip("`")
        text = text.removeprefix("json").strip()
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        # Model ignored the JSON contract — still usable as a spoken line.
        return AskResponse(steps=[Step(say=raw.strip())])

    raw_steps = data.get("steps") if isinstance(data, dict) else None
    if not isinstance(raw_steps, list) or not raw_steps:
        return AskResponse(steps=[Step(say=raw.strip())])

    steps: list[Step] = []
    for item in raw_steps:
        if not isinstance(item, dict):
            continue
        say = item.get("say")
        say = str(say).strip() if say else None
        action = _clean_action(item.get("action"))
        if say or action:
            steps.append(Step(say=say, action=action))
    return AskResponse(steps=steps) if steps else fallback


@router.post("/ask", response_model=AskResponse)
async def ask(req: AskRequest) -> AskResponse:
    """Answer one audience question/task as an ordered list of speak+do beats."""
    question = req.question.strip()
    if not question:
        return AskResponse(
            steps=[Step(say="Ask me anything about the Cachy project, or hand me a task.")]
        )
    raw = await asyncio.to_thread(
        complete, question, system=_SYSTEM, temperature=0.3, max_tokens=512
    )
    return _parse(raw)
