"""Rabbit-hole exploration: the generative "go deeper" engine (docs/14).

Unlike single-card chat (which is grounded ONLY in the card and refuses to go
beyond it), the rabbit hole is meant to LEAVE the card behind and follow the
reader's curiosity outward. One text-only LLM call turns a tapped thread into a
concise explanation drawing on general knowledge, plus a fresh set of follow-on
threads that branch naturally from it — so the reader can keep pulling.

The card is passed only as an ANCHOR (where the journey started); the trail keeps
the exploration coherent as it drifts further from the source. Same never-trust
discipline as structuring/insight: every field is validated, any failure returns
None, and the caller degrades cleanly.
"""

from __future__ import annotations

import json
import logging

from app.models.card import Card
from app.pipeline.structuring import complete, _strip_fences
from app.services.llm_chat import card_context

log = logging.getLogger("services.llm_rabbithole")

_MAX_THREADS = 5
_MAX_TRAIL = 8  # cap the breadcrumb context so prompts stay small + cheap

_PROMPT = """You are a brilliant, generous explainer guiding someone down a
"rabbit hole" of curiosity. They started from the saved card below and are now
exploring OUTWARD from it — following one idea to the next. Your job is to feed
that curiosity: explain the current thread well, then open new doors.

WHERE THEY STARTED (anchor — for tone/level only, do NOT confine yourself to it):
---
{anchor}
---
{trail}
CURRENT THREAD THEY TAPPED: "{topic}"

Return ONLY a JSON object (no prose, no markdown fences) with this exact shape:
{{
  "explanation": str,   // the payoff: 3-5 sentences that genuinely EXPLAIN this
                        // thread using your broad general knowledge. Teach the
                        // real idea — do NOT restrict yourself to the card, and
                        // do NOT say "the card doesn't cover this". Concrete,
                        // vivid, accurate. You may use inline **bold** for key
                        // terms and *italic* for emphasis, sparingly. No headers,
                        // no lists, no links.
  "threads": [str]      // 3-5 SHORT (3-8 word) follow-on threads that branch
                        // naturally from your explanation — the next places a
                        // curious mind would want to go. Each is a self-contained
                        // topic/question, distinct from the trail already taken.
}}

Rules:
- Be accurate and specific. If the thread is a genuine question, answer it.
- Threads must move FORWARD (deeper or sideways), never repeat the trail.
- Output strict JSON. No commentary outside the JSON.
"""


def _clean_str(value, limit: int = 1200) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.split()).strip()[:limit]


def _thread_list(raw, taken: set[str]) -> list[str]:
    """Validate follow-on threads: dedupe, drop anything already on the trail."""
    out: list[str] = []
    if not isinstance(raw, list):
        return out
    seen: set[str] = set()
    for item in raw:
        text = _clean_str(item, limit=120)
        key = text.lower()
        if not text or key in seen or key in taken:
            continue
        seen.add(key)
        out.append(text)
        if len(out) >= _MAX_THREADS:
            break
    return out


def _format_trail(trail: list[str]) -> str:
    if not trail:
        return ""
    recent = [t for t in trail if isinstance(t, str) and t.strip()][-_MAX_TRAIL:]
    if not recent:
        return ""
    steps = " → ".join(recent)
    return f"THE PATH SO FAR (do not repeat these): {steps}\n"


def _validate(raw_text: str, trail: list[str]) -> dict | None:
    try:
        data = json.loads(_strip_fences(raw_text))
    except (json.JSONDecodeError, TypeError):
        log.warning("rabbithole: LLM output was not valid JSON")
        return None
    if not isinstance(data, dict):
        return None

    explanation = _clean_str(data.get("explanation"))
    if not explanation:
        return None

    taken = {t.lower() for t in trail if isinstance(t, str)}
    threads = _thread_list(data.get("threads"), taken)
    return {"explanation": explanation, "threads": threads}


def explore(card: Card, topic: str, trail: list[str]) -> dict | None:
    """Explore one thread of the rabbit hole.

    Args:
        card: the anchor card the journey started from.
        topic: the thread the reader just tapped.
        trail: ordered breadcrumb of threads already explored (topic excluded).

    Returns:
        {"explanation": str, "threads": [str]} or None when no backend is
        configured / the model returns nothing usable.
    """
    topic = (topic or "").strip()
    if not topic:
        return None
    prompt = _PROMPT.format(
        anchor=card_context(card)[:2000],
        trail=_format_trail(trail),
        topic=topic,
    )
    raw = complete(prompt, max_tokens=1024, temperature=0.5)
    if not raw:
        log.info("rabbithole: no LLM output for topic %r", topic)
        return None
    return _validate(raw, trail)


async def explore_async(card: Card, topic: str, trail: list[str]) -> dict | None:
    import asyncio

    return await asyncio.to_thread(explore, card, topic, trail)
