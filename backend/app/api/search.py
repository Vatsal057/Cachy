"""Search over the library (docs/09).

Two modes share one endpoint:
- `text`     — SQLite LIKE over one_liner + tldr + caption + block text (the P1
               full-text path; always available).
- `semantic` — embed the query (HF feature-extraction) and rank cards by cosine
               over their stored embeddings (docs/09 P2).
- `auto`     — semantic when embeddings are configured AND the query embeds,
               otherwise falls back to text. The default.

Everything degrades gracefully: no HF key, an un-embeddable query, or a corpus
with no embeddings all fall back to full-text, so search never returns 5xx."""

from __future__ import annotations

import json

from fastapi import APIRouter, Query
from sqlalchemy import or_, select

from app.models.card import Card, CardState
from app.services import embeddings
from app.store import db

router = APIRouter(prefix="/search", tags=["search"])


@router.get("", response_model=list[Card])
async def search(
    q: str = Query(..., min_length=1),
    limit: int = Query(30, ge=1, le=100),
    mode: str = Query("auto", pattern="^(auto|semantic|text)$"),
) -> list[Card]:
    want_semantic = mode == "semantic" or (mode == "auto" and embeddings.embeddings_enabled())
    if want_semantic:
        results = await _semantic(q, limit)
        if results is not None:
            return results
        if mode == "semantic":
            # Explicit semantic request but it couldn't run — fall back rather
            # than return nothing, keeping search useful without a key.
            pass
    return await _full_text(q, limit)


async def _semantic(q: str, limit: int) -> list[Card] | None:
    """Cosine rank over stored embeddings. None if semantic can't run (caller
    falls back to full-text)."""
    query_vec = embeddings.embed(q)
    if not query_vec:
        return None
    async with db.session() as session:
        stmt = select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
        rows = (await session.execute(stmt)).scalars().all()

    scored: list[tuple[float, db.CardRow]] = []
    for r in rows:
        vec = r.embedding
        if not vec:
            continue
        score = embeddings.cosine(query_vec, vec)
        if score > 0.0:
            scored.append((score, r))
    if not scored:
        return None
    scored.sort(key=lambda s: s[0], reverse=True)
    return [r.to_card() for _, r in scored[:limit]]


async def _full_text(q: str, limit: int) -> list[Card]:
    needle = f"%{q.lower()}%"
    async with db.session() as session:
        stmt = (
            select(db.CardRow)
            .where(db.CardRow.state == CardState.READY.value)
            .where(
                or_(
                    db.CardRow.one_liner.ilike(needle),
                    db.CardRow.tldr.ilike(needle),
                    db.CardRow.caption.ilike(needle),
                )
            )
            .order_by(db.CardRow.created_at.desc())
            .limit(limit * 3)  # over-fetch, then refine by block text below
        )
        rows = (await session.execute(stmt)).scalars().all()

    # Lightweight block-text match on top of the column match.
    ql = q.lower()
    results = []
    for r in rows:
        if (
            ql in (r.one_liner or "").lower()
            or ql in (r.tldr or "").lower()
            or ql in (r.caption or "").lower()
            or ql in json.dumps(r.blocks or []).lower()
        ):
            results.append(r.to_card())
        if len(results) >= limit:
            break
    return results
