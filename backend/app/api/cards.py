"""Card endpoints (docs/05). POST returns immediately and enqueues a job; the
client then connects to the SSE stream to watch the transparent pipeline."""

from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import delete, select

from app.models.card import Card, CardState
from app.models.job import JobState
from app.services import cache, events
from app.store import db, media

log = logging.getLogger("api.cards")
router = APIRouter(prefix="/cards", tags=["cards"])


# --------------------------------------------------------------------------- #
# Request/response models
# --------------------------------------------------------------------------- #

class CreateCardRequest(BaseModel):
    url: str


class CreateCardResponse(BaseModel):
    card_id: str
    state: CardState
    cached: bool = False


class PatchCardRequest(BaseModel):
    # Phase-1 user-mutable state lives inside blocks JSON (e.g. checked items).
    blocks: list | None = None
    state: None = None  # state is server-controlled; ignored if sent


def _platform_for(url: str) -> str | None:
    u = url.lower()
    if "instagram.com" in u:
        return "instagram"
    if "tiktok.com" in u:
        return "tiktok"
    if "youtube.com" in u or "youtu.be" in u:
        return "youtube"
    return None


# --------------------------------------------------------------------------- #
# Endpoints
# --------------------------------------------------------------------------- #

@router.post("", response_model=CreateCardResponse)
async def create_card(req: CreateCardRequest) -> CreateCardResponse:
    url = req.url.strip()
    if not url:
        raise HTTPException(status_code=422, detail="url is required")

    async with db.session() as session:
        # Dedup: re-sharing the same reel returns the existing card (docs/02).
        existing = await cache.existing_card_for_url(session, url)
        if existing is not None:
            return CreateCardResponse(
                card_id=existing.id, state=CardState(existing.state), cached=True
            )

        card = db.CardRow(
            source_url=url,
            platform=_platform_for(url),
            state=CardState.QUEUED.value,
            blocks=[],
        )
        session.add(card)
        await session.flush()  # assign card.id
        job = db.JobRow(card_id=card.id, state=JobState.QUEUED.value)
        session.add(job)
        await session.commit()
        return CreateCardResponse(card_id=card.id, state=CardState.QUEUED)


@router.get("/{card_id}/stream")
async def stream_card(card_id: str) -> StreamingResponse:
    """SSE stream of pipeline stage updates until the card is READY or FAILED."""
    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        initial_state = row.state

    async def event_gen():
        queue = events.subscribe(card_id)
        try:
            # Replay current state immediately so a late subscriber isn't blank.
            yield _sse({"card_id": card_id, "stage": "snapshot", "state": initial_state})
            if initial_state in (CardState.READY.value, CardState.FAILED.value):
                yield _sse({"card_id": card_id, "stage": "done", "state": initial_state})
                return
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=20.0)
                except asyncio.TimeoutError:
                    yield ": keep-alive\n\n"  # comment frame to hold the connection
                    continue
                yield _sse(event.to_dict())
                if event.state in (CardState.READY.value, CardState.FAILED.value):
                    return
        finally:
            events.unsubscribe(card_id, queue)

    return StreamingResponse(event_gen(), media_type="text/event-stream")


@router.get("/{card_id}", response_model=Card)
async def get_card(card_id: str) -> Card:
    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        return row.to_card()


@router.get("", response_model=list[Card])
async def list_cards(
    state: CardState | None = None,
    content_type: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[Card]:
    async with db.session() as session:
        stmt = select(db.CardRow).order_by(db.CardRow.created_at.desc())
        if state is not None:
            stmt = stmt.where(db.CardRow.state == state.value)
        if content_type is not None:
            stmt = stmt.where(db.CardRow.content_type == content_type)
        stmt = stmt.limit(limit).offset(offset)
        rows = (await session.execute(stmt)).scalars().all()
        return [r.to_card() for r in rows]


@router.patch("/{card_id}", response_model=Card)
async def patch_card(card_id: str, req: PatchCardRequest) -> Card:
    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        if req.blocks is not None:
            row.blocks = req.blocks  # e.g. updated checked flags (optimistic client)
        await session.commit()
        await session.refresh(row)
        return row.to_card()


@router.delete("/{card_id}")
async def delete_card(card_id: str) -> dict:
    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        thumb = row.thumbnail
        keyframes = list(row.keyframes or [])
        await session.execute(delete(db.JobRow).where(db.JobRow.card_id == card_id))
        await session.execute(delete(db.CardRow).where(db.CardRow.id == card_id))
        await session.commit()
    media.remove_card_media(card_id, [thumb, *keyframes])
    return {"deleted": card_id}


def _sse(data: dict) -> str:
    return f"data: {json.dumps(data)}\n\n"
