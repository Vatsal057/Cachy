"""Connections endpoint: the serendipity engine's own surface. Returns cached
surprising links between the owner's cards and, on demand, generates a bounded
number of fresh ones (see services/serendipity.py). Owner-scoped."""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.auth import OwnerDep
from app.api.feed import FeedCardRef
from app.models.card import CardState
from app.services import serendipity
from app.store import db

log = logging.getLogger("api.connections")
router = APIRouter(prefix="/connections", tags=["connections"])


class ConnectionItem(BaseModel):
    card_a: FeedCardRef
    card_b: FeedCardRef
    blurb: str


class ConnectionsResponse(BaseModel):
    connections: list[ConnectionItem]


@router.get("", response_model=ConnectionsResponse)
async def get_connections(
    owner_id: OwnerDep,
    limit: int = Query(12, ge=1, le=30),
    refresh: bool = Query(False),
) -> ConnectionsResponse:
    """List surprising connections for the owner. `refresh=true` spends a little
    more of the LLM budget to surface new links."""
    async with db.session() as session:
        stmt = select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
        stmt = stmt.where(db.CardRow.owner_id == owner_id)
        rows = list((await session.execute(stmt)).scalars().all())
        items = await serendipity.get_connections(
            session,
            owner_id=owner_id,
            cards=rows,
            want=limit,
            max_new=4 if refresh else 2,
        )
    return ConnectionsResponse(connections=[ConnectionItem(**c) for c in items])
