"""Insight analysis (docs/14): the GATED second pass. Runs ONLY for cards the
structuring pass judged `depth == "deep"`. One text-only LLM call turns the card's
own summary + body into a reasoning layer — rabbit-hole threads to explore, a
short "test yourself" quiz for active recall, and a ready-to-paste deep-research
prompt.

Same discipline as structuring: never trust the model. Every field is validated
and independently optional; a malformed or empty result yields `None` (no layer),
never a crash. A simple reel never reaches this module.
"""

from __future__ import annotations

import json
import logging

from app.models.card import (
    Insight,
    QuizQuestion,
    RabbitHole,
)
from app.pipeline.structuring import complete, _strip_fences

log = logging.getLogger("pipeline.insight")

_MAX = {
    "questions": 3,
    "adjacent_topics": 3,
    "advanced_concepts": 2,
    "quiz": 4,
}

_SYSTEM_PROMPT = """You are a sharp analyst. You are given a knowledge card distilled from a
short-form video on an idea-rich topic. Produce a DEEP ANALYSIS layer — the
scaffolding a curious person would use to go FURTHER than the video, and to test
whether they actually got it. Everything must be something the reader can act on.

Return ONLY a JSON object (no prose, no markdown fences) with this exact shape:
{{
  "rabbit_hole": {{           // threads to go deeper; each becomes a tappable
                              // prompt in an explorer. Each list may be empty.
    "questions": [str],            // sharp open questions the content raises
    "adjacent_topics": [str],      // neighbouring subjects worth exploring
    "advanced_concepts": [str]     // next-level ideas for someone who gets the basics
  }},
  "quiz": [                   // 2-4 multiple-choice questions to test recall, or []
    {{
      "question": str,              // one clear question about the card's ideas
      "options": [str],             // 3-4 plausible choices, exactly one correct
      "answer_index": int,          // 0-based index of the correct option
      "explanation": str            // one short sentence on WHY that answer is right
    }}
  ],
  "deep_research_prompt": str // a ready-to-paste prompt for an external LLM (see below)
}}

Rules:
- Ground EVERY item in the card's actual content. Do not invent. If the card is
  thin, return fewer items — an empty list is correct. Never pad.
- rabbit_hole: keep it TIGHT. Only the sharpest threads (at most 2-3 each), phrased
  so they work as a prompt (e.g. "How does compound interest differ from simple
  interest?"). Concrete, specific, self-contained.
- quiz: test real understanding of the card's ideas, not trivia. Each question has
  3-4 options with exactly one clearly-correct answer and a one-line explanation.
  Return [] if the card is too thin to quiz honestly.
- deep_research_prompt: a structured, rigorous research brief (research objectives,
  desired output sections, constraints) an expert could paste into a frontier LLM to
  go far beyond this video. Plain text, ~150-300 words, no markdown headers. Omit it
  (use null) only if the topic does not reward independent research.
- Output strict JSON. No commentary.
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


def _parse_quiz(raw, cap: int) -> list[QuizQuestion]:
    """Validate the quiz array. Drops any malformed question; keeps at most `cap`
    valid ones. Options are cleaned + deduped and the answer index is bounds-checked."""
    if not isinstance(raw, list):
        return []
    out: list[QuizQuestion] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        question = _clean_str(item.get("question"), limit=200)
        options = _str_list(item.get("options"), cap=4)
        answer_index = item.get("answer_index")
        if not isinstance(answer_index, int):
            continue
        q = QuizQuestion(
            question=question,
            options=options,
            answer_index=answer_index,
            explanation=_clean_str(item.get("explanation"), limit=240),
        )
        if q.is_valid():
            out.append(q)
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

    quiz = _parse_quiz(data.get("quiz"), _MAX["quiz"])

    deep_research_prompt = _clean_str(data.get("deep_research_prompt"), limit=4000) or None

    insight = Insight(
        rabbit_hole=rabbit_hole,
        quiz=quiz,
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
    # Static instructions ride as a cached system prompt; only the per-card digest
    # varies as the user content.
    raw = complete(f"Card:\n---\n{card}\n---", system=_SYSTEM_PROMPT, max_tokens=4096)
    if not raw:
        log.info("insight: no LLM output -> skipping insight layer")
        return None
    return _validate(raw)


async def analyze_async(
    one_liner: str, tldr: str, body: str, tags: list[str]
) -> Insight | None:
    import asyncio

    return await asyncio.to_thread(analyze, one_liner, tldr, body, tags)
