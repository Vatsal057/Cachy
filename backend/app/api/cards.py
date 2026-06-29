"""Card endpoints (docs/05). POST returns immediately and enqueues a job; the
client then connects to the SSE stream to watch the transparent pipeline."""

from __future__ import annotations

import asyncio
import json
import logging

from typing import Annotated

from fastapi import APIRouter, Header, HTTPException, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import delete, select

from app.api.graph import invalidate_graph_cache
from app.models.card import Card, CardState
from app.models.job import JobState
from app.pipeline.ingestion.source import platform_for_url
from app.services import cache, events, llm_chat
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
    # User-mutable to-do state (docs/13): {followed, items:[{id,text,done}]}.
    action_items: dict | None = None
    # Move card to a different collection (None = remove from collection).
    collection_id: str | None = None
    state: None = None  # state is server-controlled; ignored if sent


class BulkImportRequest(BaseModel):
    cards: list[Card]


class ChatMessage(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage]


class ChatResponse(BaseModel):
    reply: str


def _platform_for(url: str) -> str | None:
    return platform_for_url(url)


# --------------------------------------------------------------------------- #
# Endpoints
# --------------------------------------------------------------------------- #

@router.post("", response_model=CreateCardResponse)
async def create_card(
    req: CreateCardRequest,
    x_owner_id: Annotated[str | None, Header()] = None,
) -> CreateCardResponse:
    url = req.url.strip()
    if not url:
        raise HTTPException(status_code=422, detail="url is required")

    async with db.session() as session:
        # Dedup: re-sharing the same reel returns the existing card (docs/02).
        existing = await cache.existing_card_for_url(session, url, owner_id=x_owner_id)
        if existing is not None:
            return CreateCardResponse(
                card_id=existing.id, state=CardState(existing.state), cached=True
            )

        card = db.CardRow(
            source_url=url,
            platform=_platform_for(url),
            state=CardState.QUEUED.value,
            blocks=[],
            owner_id=x_owner_id,
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


@router.post("/import")
async def import_cards(
    req: BulkImportRequest,
    x_owner_id: Annotated[str | None, Header()] = None,
) -> dict:
    """Restore pre-processed cards from the phone cache after a server wipe.
    Skips URLs already on the server. Assigns new IDs so no PK conflicts."""
    imported = 0
    async with db.session() as session:
        for card in req.cards:
            if card.state != CardState.READY:
                continue
            existing = await cache.existing_card_for_url(
                session, card.source.url, owner_id=x_owner_id
            )
            if existing is not None:
                continue
            row = db.CardRow(
                source_url=card.source.url,
                platform=card.source.platform,
                creator=card.source.creator,
                caption=card.source.caption,
                duration_seconds=card.source.duration_seconds,
                resolver=card.source.resolver,
                state=CardState.READY.value,
                content_type=card.base.content_type,
                type_confidence=card.base.type_confidence,
                one_liner=card.base.one_liner,
                tldr=card.base.tldr,
                tags=list(card.base.tags),
                blocks=[b.model_dump() for b in (card.blocks or [])],
                insight=card.insight.model_dump() if card.insight else None,
                primary_action=card.primary_action.model_dump(),
                action_items=card.action_items.model_dump(),
                thumbnail=card.media.thumbnail,
                keyframes=list(card.media.keyframes),
                collection_id=None,  # collections don't survive server wipe
                owner_id=x_owner_id,
                schema_version=card.schema_version,
            )
            session.add(row)
            imported += 1
        await session.commit()
    invalidate_graph_cache()
    return {"imported": imported}


@router.get("/{card_id}", response_model=Card)
async def get_card(card_id: str) -> Card:
    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        return row.to_card()


@router.get("", response_model=list[Card])
async def list_cards(
    x_owner_id: Annotated[str | None, Header()] = None,
    state: CardState | None = None,
    content_type: str | None = None,
    collection_id: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[Card]:
    async with db.session() as session:
        stmt = select(db.CardRow).order_by(db.CardRow.created_at.desc())
        if x_owner_id is not None:
            stmt = stmt.where(db.CardRow.owner_id == x_owner_id)
        if state is not None:
            stmt = stmt.where(db.CardRow.state == state.value)
        if content_type is not None:
            stmt = stmt.where(db.CardRow.content_type == content_type)
        if collection_id is not None:
            stmt = stmt.where(db.CardRow.collection_id == collection_id)
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
        if req.action_items is not None:
            row.action_items = req.action_items  # follow toggle + per-item done state
        if req.collection_id is not None:
            row.collection_id = req.collection_id
        await session.commit()
        await session.refresh(row)
        invalidate_graph_cache()
        return row.to_card()


@router.post("/{card_id}/chat", response_model=ChatResponse)
async def chat_card(card_id: str, req: ChatRequest) -> ChatResponse:
    """Grounded Q&A over one card (docs/13). Stateless: the client replays the
    conversation each turn; nothing is stored. The model answers from the card's
    structured content only."""
    if not req.messages or req.messages[-1].role != "user":
        raise HTTPException(status_code=422, detail="last message must be from user")

    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        if row.state != CardState.READY.value:
            raise HTTPException(status_code=409, detail="card is not ready")
        card = row.to_card()

    history = [m.model_dump() for m in req.messages]
    reply = await asyncio.to_thread(llm_chat.answer, card, history)
    if reply is None:
        raise HTTPException(
            status_code=503, detail="chat is unavailable (no LLM backend configured)"
        )
    return ChatResponse(reply=reply)


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
        await db.cleanup_after_card_deletion(session, card_id)
        await session.commit()
    media.remove_card_media(card_id, [thumb, *keyframes])
    invalidate_graph_cache()
    return {"deleted": card_id}


def _sse(data: dict) -> str:
    return f"data: {json.dumps(data)}\n\n"
