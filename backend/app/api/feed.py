"""Knowledge Feed endpoint: a shuffled, reel-style stream of "moments" built from
the owner's saved cards (see services/feed.py). Owner-scoped via X-Owner-Id.

Cheap by design: every moment except `connection` comes from data already stored
on the card; connections reuse the cached serendipity links and top up a small,
bounded number per load."""

from __future__ import annotations

import logging
from typing import Annotated, Optional

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.auth import OwnerDep
from app.models.card import CardState
from app.services import feed as feed_service
from app.store import db

log = logging.getLogger("api.feed")
router = APIRouter(prefix="/feed", tags=["feed"])


class FeedCardRef(BaseModel):
    card_id: str
    title: str
    content_type: str
    thumbnail: Optional[str] = None


class FeedItem(BaseModel):
    id: str
    kind: str  # insight | highlight | quiz | thread | connection
    card: FeedCardRef
    text: str = ""
    # quiz-specific
    question: str = ""
    options: list[str] = []
    answer_index: int = 0
    explanation: str = ""
    # connection-specific (the second card in the pair)
    card_b: Optional[FeedCardRef] = None


class FeedResponse(BaseModel):
    items: list[FeedItem]


@router.get("", response_model=FeedResponse)
async def get_feed(
    owner_id: OwnerDep,
    limit: int = Query(40, ge=1, le=100),
) -> FeedResponse:
    """Assemble the owner's knowledge feed from their READY cards."""
    async with db.session() as session:
        stmt = select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
        stmt = stmt.where(db.CardRow.owner_id == owner_id)
        rows = list((await session.execute(stmt)).scalars().all())
        items = await feed_service.build_feed(
            session, owner_id=owner_id, cards=rows, limit=limit
        )
    return FeedResponse(items=[FeedItem(**it) for it in items])
