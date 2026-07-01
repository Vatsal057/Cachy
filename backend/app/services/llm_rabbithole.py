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

log = logging.getLogger("services.llm_rabbithole")

_MAX_THREADS = 4
_MAX_TRAIL = 6  # cap the breadcrumb context so prompts stay small + cheap
_MAX_ANCHOR = 400  # chars of card context — just enough to set topic/level
_MAX_OUTPUT_TOKENS = 512  # 3-4 sentences + a few short threads never needs more

# Terse on purpose: a shorter prompt is cheaper per call and the model already
# knows how to explain. Every line here earns its tokens.
_PROMPT = """Guide a curious reader down a "rabbit hole" that started from this note:
{anchor}
{trail}THREAD THEY TAPPED: "{topic}"

Explain that thread using your general knowledge — go beyond the note, never say
it "isn't covered". Then offer fresh threads to keep exploring.

Return ONLY strict JSON (no fences):
{{"explanation": str, "threads": [str]}}
- explanation: 3-4 sentences, concrete and accurate. Inline **bold**/*italic* ok, sparingly. No lists/headers/links.
- threads: 3-4 short (3-8 words) follow-ups that branch forward, none repeating the trail."""


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


def _anchor(card: Card) -> str:
    """A minimal text anchor — the one-liner + summary set the topic and level.
    We deliberately skip the full block body: the rabbit hole explores OUTWARD,
    so a heavy card dump would waste tokens without improving the explanation."""
    parts = [p for p in (card.base.one_liner, card.base.tldr) if p and p.strip()]
    return " — ".join(parts)[:_MAX_ANCHOR]


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
        anchor=_anchor(card),
        trail=_format_trail(trail),
        topic=topic,
    )
    raw = complete(prompt, max_tokens=_MAX_OUTPUT_TOKENS, temperature=0.5)
    if not raw:
        log.info("rabbithole: no LLM output for topic %r", topic)
        return None
    return _validate(raw, trail)


async def explore_async(card: Card, topic: str, trail: list[str]) -> dict | None:
    import asyncio

    return await asyncio.to_thread(explore, card, topic, trail)
