"""Knowledge Feed assembly: turn the user's saved cards into a shuffled stream of
bite-sized "moments" — the reel format, but for their own knowledge.

Moment kinds:
  - insight     : the card's one-liner / TL;DR (the core takeaway)
  - highlight   : a punchy line pulled from the card body
  - quiz        : a single stored quiz question (interactive)
  - thread      : a rabbit-hole thread the reader can fall into
  - connection  : a serendipitous link between two cards (see serendipity.py)

Everything except `connection` is built from data ALREADY stored on the card —
zero LLM cost. Connections reuse the cached serendipity links (and top up a small,
bounded number). Moments are interleaved so consecutive items rarely share a card.
"""

from __future__ import annotations

import logging
import random
from collections import deque

from app.services import serendipity
from app.store import media as media_store

log = logging.getLogger("services.feed")

_MAX_THREADS_PER_CARD = 2
_MAX_QUIZ_PER_CARD = 2
_CONNECTIONS_WANT = 4
_CONNECTIONS_MAX_NEW = 2  # bound the LLM cost of a feed load


def _card_ref(row) -> dict:
    return {
        "card_id": row.id,
        "title": (row.one_liner or row.caption or "Untitled").strip()[:120],
        "content_type": row.content_type or "other",
        "thumbnail": media_store.to_media_url(row.thumbnail),
    }


def _clean(text: str, limit: int = 220) -> str:
    return " ".join((text or "").split()).strip()[:limit]


def _best_highlight(blocks: list) -> str | None:
    """Pull one punchy line from the card body — a callout, else a bullet, else a
    paragraph. Returns None when there's nothing quotable."""
    callout = bullet = paragraph = None
    for b in blocks or []:
        if not isinstance(b, dict):
            continue
        btype = b.get("type")
        if btype == "callout" and callout is None and b.get("text"):
            callout = _clean(b["text"])
        elif btype == "bullet_list" and bullet is None:
            items = [i for i in (b.get("items") or []) if isinstance(i, str) and i.strip()]
            if items:
                bullet = _clean(items[0])
        elif btype == "paragraph" and paragraph is None and b.get("text"):
            paragraph = _clean(b["text"])
    return callout or bullet or paragraph


def _moments_for_card(row) -> list[dict]:
    ref = _card_ref(row)
    cid = row.id
    out: list[dict] = []

    tldr = _clean(row.tldr or row.one_liner, limit=280)
    if tldr:
        out.append({"id": f"{cid}:insight", "kind": "insight", "card": ref, "text": tldr})

    highlight = _best_highlight(row.blocks)
    # Skip a highlight that just echoes the insight text.
    if highlight and highlight.lower() != tldr.lower():
        out.append({"id": f"{cid}:highlight", "kind": "highlight", "card": ref, "text": highlight})

    insight = row.insight if isinstance(row.insight, dict) else {}

    quiz = insight.get("quiz") if isinstance(insight.get("quiz"), list) else []
    for k, q in enumerate(quiz[:_MAX_QUIZ_PER_CARD]):
        if not isinstance(q, dict):
            continue
        options = [str(o) for o in (q.get("options") or [])]
        idx = q.get("answer_index")
        question = _clean(q.get("question", ""), limit=200)
        if question and 2 <= len(options) <= 4 and isinstance(idx, int) and 0 <= idx < len(options):
            out.append({
                "id": f"{cid}:quiz:{k}",
                "kind": "quiz",
                "card": ref,
                "question": question,
                "options": options,
                "answer_index": idx,
                "explanation": _clean(q.get("explanation", ""), limit=240),
            })

    rh = insight.get("rabbit_hole") if isinstance(insight.get("rabbit_hole"), dict) else {}
    threads: list[str] = []
    for key in ("questions", "adjacent_topics", "advanced_concepts"):
        for t in (rh.get(key) or []):
            if isinstance(t, str) and t.strip():
                threads.append(t.strip())
    for k, t in enumerate(threads[:_MAX_THREADS_PER_CARD]):
        out.append({"id": f"{cid}:thread:{k}", "kind": "thread", "card": ref, "text": _clean(t, limit=160)})

    return out


def _interleave(moments: list[dict]) -> list[dict]:
    """Round-robin across per-card buckets so consecutive moments rarely share a
    card. Connections each get their own bucket, so they scatter naturally."""
    buckets: dict[str, deque] = {}
    for m in moments:
        key = m["id"] if m["kind"] == "connection" else m["card"]["card_id"]
        buckets.setdefault(key, deque()).append(m)
    queues = list(buckets.values())
    random.shuffle(queues)
    out: list[dict] = []
    while queues:
        for q in queues:
            if q:
                out.append(q.popleft())
        queues = [q for q in queues if q]
    return out


async def build_feed(
    session, *, owner_id: str | None, cards: list, limit: int
) -> list[dict]:
    """Assemble the owner's feed. `cards` are READY CardRows (owner-scoped)."""
    moments: list[dict] = []
    for row in cards:
        moments.extend(_moments_for_card(row))

    # Weave in serendipitous connections (cheap: cached + a couple fresh).
    try:
        conns = await serendipity.get_connections(
            session,
            owner_id=owner_id,
            cards=cards,
            want=_CONNECTIONS_WANT,
            max_new=_CONNECTIONS_MAX_NEW,
        )
    except Exception as e:  # noqa: BLE001 — connections are a bonus, never fatal
        log.warning("feed: connection generation failed: %s", e)
        conns = []
    for c in conns:
        moments.append({
            "id": f"conn:{c['card_a']['card_id']}:{c['card_b']['card_id']}",
            "kind": "connection",
            "card": c["card_a"],
            "card_b": c["card_b"],
            "text": c["blurb"],
        })

    random.shuffle(moments)
    return _interleave(moments)[:limit]
