"""Basic full-text search over one_liner + tldr + block text (docs/08, P1).

SQLite LIKE is enough for the MVP corpus; swap for FTS5 / a vector index in P2/P3."""

from __future__ import annotations

import json

from fastapi import APIRouter, Query
from sqlalchemy import or_, select

from app.models.card import Card, CardState
from app.store import db

router = APIRouter(prefix="/search", tags=["search"])


@router.get("", response_model=list[Card])
async def search(
    q: str = Query(..., min_length=1),
    limit: int = Query(30, ge=1, le=100),
) -> list[Card]:
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
