"""Serendipity engine: surprising-but-real links between a user's cards.

Two cards are a good "connection" when they're related enough to share a thread
yet distinct enough to be non-obvious — ideally from different content types
(a ramen recipe and a startup video). We rank candidate pairs by a surprise
score over embedding similarity (mid-band, not near-duplicate) with a cross-type
bonus, then spend ONE cheap LLM call to explain the link in a sentence or two.

Cost discipline (free-first): explanations are cached in the
`connections` table and reused; a caller bounds how many NEW links it will pay
for per request via `max_new`. No embeddings / no backend → graceful empty.
"""

from __future__ import annotations

import logging

from app.services import embeddings
from app.services.llm_chat import card_context
from app.pipeline.structuring import complete
from app.store import db
from app.store import media as media_store

log = logging.getLogger("services.serendipity")

# Similarity band for "surprising": below _MIN is unrelated noise, above _MAX is
# an obvious near-duplicate (already covered by the graph). The sweet spot is the
# middle — a real but non-obvious thread.
_SIM_MIN = 0.26
_SIM_MAX = 0.66
_CROSS_TYPE_BONUS = 0.15

_GENERIC_TAGS = {
    "video", "videos", "reel", "reels", "instagram", "tiktok", "youtube",
    "short", "shorts", "clip", "clips", "post", "posts", "other", "general",
    "article", "content", "media",
}

_PROMPT = """Two short knowledge cards from someone's library are below. Find the
SURPRISING but genuine connection between them — a shared principle, tension, or
idea a thoughtful person wouldn't spot at first glance. Do NOT just say they're
both about X.

Write 1-2 punchy sentences (max ~45 words) naming the link and why it's
interesting. Plain text, no preamble, no markdown.

CARD A — {title_a}:
{ctx_a}

CARD B — {title_b}:
{ctx_b}"""


def _card_ref(row) -> dict:
    return {
        "card_id": row.id,
        "title": (row.one_liner or row.caption or "Untitled").strip()[:120],
        "content_type": row.content_type or "other",
        "thumbnail": media_store.to_media_url(row.thumbnail),
    }


def _candidate_pairs(cards: list) -> list[tuple[int, int, float]]:
    """Rank card index pairs by surprise score, best first. Uses embeddings when
    both cards have them; falls back to a shared-tag signal across different
    content types otherwise."""
    pairs: list[tuple[int, int, float]] = []
    for i in range(len(cards)):
        for j in range(i + 1, len(cards)):
            a, b = cards[i], cards[j]
            cross_type = (a.content_type or "other") != (b.content_type or "other")

            if a.embedding and b.embedding:
                sim = embeddings.cosine(a.embedding, b.embedding)
                if sim < _SIM_MIN or sim > _SIM_MAX:
                    continue
                score = sim + (_CROSS_TYPE_BONUS if cross_type else 0.0)
                pairs.append((i, j, score))
                continue

            # Fallback: meaningful shared tags across different types is a decent
            # surprise signal when embeddings are unavailable.
            tags_a = {t.lower() for t in (a.tags or [])} - _GENERIC_TAGS
            tags_b = {t.lower() for t in (b.tags or [])} - _GENERIC_TAGS
            shared = tags_a & tags_b
            if shared and cross_type:
                pairs.append((i, j, 0.3 + 0.05 * len(shared)))

    pairs.sort(key=lambda p: p[2], reverse=True)
    return pairs


def _explain(row_a, row_b) -> str | None:
    """One cheap LLM call describing the link. None on any failure."""
    prompt = _PROMPT.format(
        title_a=(row_a.one_liner or "Card A")[:120],
        ctx_a=card_context(row_a.to_card())[:700],
        title_b=(row_b.one_liner or "Card B")[:120],
        ctx_b=card_context(row_b.to_card())[:700],
    )
    raw = complete(prompt, max_tokens=160, temperature=0.7)
    if not raw:
        return None
    return " ".join(raw.split()).strip()[:400] or None


async def get_connections(
    session,
    *,
    owner_id: str | None,
    cards: list,
    want: int,
    max_new: int,
) -> list[dict]:
    """Return up to `want` connection dicts for the owner.

    Reuses cached connections whose both cards are still present, and generates
    at most `max_new` fresh ones (each = one LLM call) to top up. Best-effort:
    generation failures are skipped, never raised.
    """
    import asyncio

    by_id = {c.id: c for c in cards}
    if len(by_id) < 2:
        return []

    out: list[dict] = []
    used_pairs: set[tuple[str, str]] = set()

    # 1) Reuse cached connections (both endpoints still valid + owned).
    for row in await db.list_connections(session, owner_id=owner_id, limit=want * 3):
        a, b = by_id.get(row.card_a_id), by_id.get(row.card_b_id)
        if a is None or b is None:
            continue
        key = db._canonical_pair(row.card_a_id, row.card_b_id)
        if key in used_pairs:
            continue
        used_pairs.add(key)
        out.append({"card_a": _card_ref(a), "card_b": _card_ref(b), "blurb": row.blurb})
        if len(out) >= want:
            return out

    # 2) Generate fresh links to top up, bounded by max_new.
    if max_new <= 0:
        return out

    generated = 0
    for i, j, _score in _candidate_pairs(cards):
        if generated >= max_new or len(out) >= want:
            break
        a, b = cards[i], cards[j]
        key = db._canonical_pair(a.id, b.id)
        if key in used_pairs:
            continue
        blurb = await asyncio.to_thread(_explain, a, b)
        if not blurb:
            continue
        used_pairs.add(key)
        await db.save_connection(
            session, owner_id=owner_id, card_a=a.id, card_b=b.id, blurb=blurb
        )
        out.append({"card_a": _card_ref(a), "card_b": _card_ref(b), "blurb": blurb})
        generated += 1

    return out
