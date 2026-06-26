"""Insight analysis (docs/14): the GATED second pass. Runs ONLY for cards the
structuring pass judged `depth == "deep"`. One text-only LLM call turns the card's
own summary + body into a reasoning layer — claims, blind spots, rabbit holes, a
small topic map, and a ready-to-paste deep-research prompt.

Same discipline as structuring: never trust the model. Every field is validated
and independently optional; a malformed or empty result yields `None` (no layer),
never a crash. A simple reel never reaches this module.
"""

from __future__ import annotations

import json
import logging

from app.models.card import (
    Insight,
    RabbitHole,
    TopicMap,
)
from app.pipeline.structuring import complete, _strip_fences

log = logging.getLogger("pipeline.insight")

_MAX = {
    "questions": 6,
    "adjacent_topics": 6,
    "advanced_concepts": 5,
    "nodes": 6,
}

_PROMPT = """You are a sharp analyst. You are given a knowledge card distilled from a
short-form video on an idea-rich topic. Produce a DEEP ANALYSIS layer — the
scaffolding a curious person would use to go FURTHER than the video. Everything
must be something the reader can act on, not passive commentary.

Return ONLY a JSON object (no prose, no markdown fences) with this exact shape:
{{
  "rabbit_hole": {{           // threads to go deeper; each becomes a tappable
                              // question the reader can ask an AI. Each list may be empty.
    "questions": [str],            // sharp open questions the content raises
    "adjacent_topics": [str],      // neighbouring subjects worth exploring
    "advanced_concepts": [str]     // next-level ideas for someone who gets the basics
  }},
  "topic_map": {{             // a one-hop concept map, or null if not meaningful
    "center": str,                 // the core idea (1-3 words)
    "nodes": [str]                 // 3-6 connected concepts (1-3 words each)
  }},
  "deep_research_prompt": str // a ready-to-paste prompt for an external LLM (see below)
}}

Rules:
- Ground EVERY item in the card's actual content. Do not invent. If the card is
  thin, return fewer items — an empty list is correct when there is nothing real
  to say. Never pad.
- rabbit_hole: phrase questions/topics so they make sense as a prompt the reader
  taps to ask an AI (e.g. "How does compound interest differ from simple
  interest?", "Behavioural economics of saving"). Concrete, specific, self-contained.
- topic_map: only when the content genuinely connects several concepts. If it is a
  single narrow point, set "topic_map": null.
- deep_research_prompt: a structured, rigorous research brief (research objectives,
  desired output sections, constraints) an expert could paste into a frontier LLM to
  go far beyond this video. Plain text, ~150-350 words, no markdown headers. Omit it
  (use null) only if the topic does not reward independent research.
- Output strict JSON. No commentary.

Card:
---
{card}
---
"""


def _card_digest(one_liner: str, tldr: str, body: str, tags: list[str]) -> str:
    """A compact text view of the card for the analysis prompt."""
    parts = []
    if one_liner:
        parts.append(f"ONE-LINER: {one_liner}")
    if tldr:
        parts.append(f"SUMMARY: {tldr}")
    if tags:
        parts.append("TAGS: " + ", ".join(tags))
    if body:
        parts.append("BODY:\n" + body[:4000])
    return "\n\n".join(parts).strip()


# --------------------------------------------------------------------------- #
# Validation — never trust the model
# --------------------------------------------------------------------------- #

def _clean_str(value, limit: int = 400) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.split()).strip()[:limit]


def _str_list(raw, cap: int) -> list[str]:
    out: list[str] = []
    if not isinstance(raw, list):
        return out
    seen: set[str] = set()
    for item in raw:
        text = _clean_str(item)
        if not text or text.lower() in seen:
            continue
        seen.add(text.lower())
        out.append(text)
        if len(out) >= cap:
            break
    return out


def _validate(raw_text: str) -> Insight | None:
    try:
        data = json.loads(_strip_fences(raw_text))
    except (json.JSONDecodeError, TypeError):
        log.warning("insight: LLM output was not valid JSON -> no insight layer")
        return None
    if not isinstance(data, dict):
        return None

    rh_raw = data.get("rabbit_hole") if isinstance(data.get("rabbit_hole"), dict) else {}
    rabbit_hole = RabbitHole(
        questions=_str_list(rh_raw.get("questions"), _MAX["questions"]),
        adjacent_topics=_str_list(rh_raw.get("adjacent_topics"), _MAX["adjacent_topics"]),
        advanced_concepts=_str_list(
            rh_raw.get("advanced_concepts"), _MAX["advanced_concepts"]
        ),
    )

    topic_map = None
    tm_raw = data.get("topic_map")
    if isinstance(tm_raw, dict):
        center = _clean_str(tm_raw.get("center"), limit=60)
        nodes = _str_list(tm_raw.get("nodes"), _MAX["nodes"])
        if center and len(nodes) >= 2:  # a center with <2 satellites is not a map
            topic_map = TopicMap(center=center, nodes=nodes)

    deep_research_prompt = _clean_str(data.get("deep_research_prompt"), limit=4000) or None

    insight = Insight(
        rabbit_hole=rabbit_hole,
        topic_map=topic_map,
        deep_research_prompt=deep_research_prompt,
    )
    # Drop a layer that came back empty after validation — render nothing rather
    # than an empty shell (docs/14).
    return insight if insight.has_content() else None


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def analyze(one_liner: str, tldr: str, body: str, tags: list[str]) -> Insight | None:
    """Run the gated second pass. Returns a validated Insight, or None when the
    backend is unavailable / the model returns nothing usable. Caller (worker)
    treats None as "no insight layer" — never an error."""
    card = _card_digest(one_liner, tldr, body, tags)
    if not card:
        return None
    raw = complete(_PROMPT.format(card=card), max_tokens=4096)
    if not raw:
        log.info("insight: no LLM output -> skipping insight layer")
        return None
    return _validate(raw)


async def analyze_async(
    one_liner: str, tldr: str, body: str, tags: list[str]
) -> Insight | None:
    import asyncio

    return await asyncio.to_thread(analyze, one_liner, tldr, body, tags)
