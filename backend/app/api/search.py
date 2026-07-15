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
from typing import Annotated

from fastapi import APIRouter, Query
from sqlalchemy import or_, select

from app.auth import OwnerDep
from app.models.card import Card, CardState
from app.services import embeddings
from app.store import db

router = APIRouter(prefix="/search", tags=["search"])


@router.get("", response_model=list[Card])
async def search(
    owner_id: OwnerDep,
    q: str = Query(..., min_length=1),
    limit: int = Query(30, ge=1, le=100),
    mode: str = Query("auto", pattern="^(auto|semantic|text)$"),
) -> list[Card]:
    want_semantic = mode == "semantic" or (mode == "auto" and embeddings.embeddings_enabled())
    if want_semantic:
        results = await _semantic(q, limit, owner_id)
        if results is not None:
            return results
        if mode == "semantic":
            pass
    return await _full_text(q, limit, owner_id)


async def _semantic(q: str, limit: int, owner_id: str | None) -> list[Card] | None:
    """Cosine rank over stored embeddings. None if semantic can't run (caller
    falls back to full-text)."""
    import asyncio

    # embed() is a network call; keep it off the event loop (B6).
    query_vec = await asyncio.to_thread(embeddings.embed, q)
    if not query_vec:
        return None
    async with db.session() as session:
        stmt = select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
        stmt = stmt.where(db.CardRow.owner_id == owner_id)
        rows = (await session.execute(stmt)).scalars().all()

    def _rank() -> list[db.CardRow]:
        # Pure-Python cosine over every card row — run in a thread (B6).
        scored: list[tuple[float, db.CardRow]] = []
        for r in rows:
            vec = r.embedding
            if not vec:
                continue
            score = embeddings.cosine(query_vec, vec)
            if score > 0.0:
                scored.append((score, r))
        scored.sort(key=lambda s: s[0], reverse=True)
        return [r for _, r in scored[:limit]]

    top = await asyncio.to_thread(_rank)
    if not top:
        return None
    return [r.to_card() for r in top]


async def _full_text(q: str, limit: int, owner_id: str | None) -> list[Card]:
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
            .limit(limit * 3)
        )
        stmt = stmt.where(db.CardRow.owner_id == owner_id)
        rows = (await session.execute(stmt)).scalars().all()

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
