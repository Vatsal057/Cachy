"""Card endpoints (docs/05). POST returns immediately and enqueues a job; the
client then connects to the SSE stream to watch the transparent pipeline."""

from __future__ import annotations

import asyncio
import json
import logging

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import delete, select

from app import quota
from app.auth import OwnerDep
from app.api.graph import invalidate_graph_cache
from app.models.card import Card, CardState
from app.models.job import JobState
from app.pipeline.ingestion.source import platform_for_url
from app.services import cache, events, llm_chat, llm_rabbithole
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
    quota_degraded: bool = False  # past daily AI budget -> paragraph fallback card


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


class ChatHistoryResponse(BaseModel):
    # Restored conversation, oldest → newest.
    messages: list[ChatMessage]


class RabbitHoleRequest(BaseModel):
    # The thread the reader just tapped (a question / topic / concept).
    topic: str
    # Ordered breadcrumb of threads already explored this session (topic excluded).
    trail: list[str] = []
    # The root topic that started this exploration (persistence key). Defaults to
    # `topic` on the first hop.
    root: str | None = None


class RabbitHoleResponse(BaseModel):
    # A concise explanation of the topic, free to draw on general knowledge.
    explanation: str
    # Fresh follow-on threads that branch from the explanation.
    threads: list[str]


class RabbitHoleStep(BaseModel):
    topic: str
    explanation: str
    threads: list[str]


class RabbitHoleHistoryResponse(BaseModel):
    # Restored trail, oldest → deepest.
    steps: list[RabbitHoleStep]


def _platform_for(url: str) -> str | None:
    return platform_for_url(url)


# --------------------------------------------------------------------------- #
# Endpoints
# --------------------------------------------------------------------------- #

@router.post("", response_model=CreateCardResponse)
async def create_card(
    req: CreateCardRequest,
    owner_id: OwnerDep,
    request: Request,
) -> CreateCardResponse:
    url = req.url.strip()
    if not url:
        raise HTTPException(status_code=422, detail="url is required")

    async with db.session() as session:
        # Dedup: re-sharing the same reel returns the existing card (docs/02).
        existing = await cache.existing_card_for_url(session, url, owner_id=owner_id)
        if existing is not None:
            return CreateCardResponse(
                card_id=existing.id, state=CardState(existing.state), cached=True
            )

        within = await quota.card_budget(owner_id, request)
        card = db.CardRow(
            source_url=url,
            platform=_platform_for(url),
            state=CardState.QUEUED.value,
            blocks=[],
            owner_id=owner_id,
        )
        session.add(card)
        await session.flush()  # assign card.id
        job = db.JobRow(card_id=card.id, state=JobState.QUEUED.value, degraded=not within)
        session.add(job)
        await session.commit()
        return CreateCardResponse(
            card_id=card.id, state=CardState.QUEUED, quota_degraded=not within
        )


@router.get("/{card_id}/stream")
async def stream_card(card_id: str, owner_id: OwnerDep) -> StreamingResponse:
    """SSE stream of pipeline stage updates until the card is READY or FAILED."""
    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None or row.owner_id != owner_id:
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
    owner_id: OwnerDep,
) -> dict:
    """Restore pre-processed cards from the phone cache after a server wipe.
    Skips URLs already on the server. Assigns new IDs so no PK conflicts."""
    imported = 0
    async with db.session() as session:
        for card in req.cards:
            if card.state != CardState.READY:
                continue
            existing = await cache.existing_card_for_url(
                session, card.source.url, owner_id=owner_id
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
                owner_id=owner_id,
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
    owner_id: OwnerDep,
    state: CardState | None = None,
    content_type: str | None = None,
    collection_id: str | None = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> list[Card]:
    async with db.session() as session:
        stmt = select(db.CardRow).order_by(db.CardRow.created_at.desc())
        stmt = stmt.where(db.CardRow.owner_id == owner_id)
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


@router.post("/{card_id}/chat", response_model=ChatResponse,
             dependencies=[Depends(quota.spend("chat", "quota_chat_per_day"))])
async def chat_card(
    card_id: str,
    req: ChatRequest,
    owner_id: OwnerDep,
) -> ChatResponse:
    """Grounded Q&A over one card (docs/13). The conversation is PERSISTED per
    owner (docs/14): the reply is generated from the card's structured content,
    then the full turn is saved so reopening the card restores the thread."""
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
    # Persist the full conversation (history + this reply), owner-scoped.
    async with db.session() as session:
        await db.save_conversation(
            session,
            owner_id=owner_id,
            kind="chat",
            card_id=card_id,
            payload=[*history, {"role": "assistant", "content": reply}],
        )
    return ChatResponse(reply=reply)


@router.get("/{card_id}/chat", response_model=ChatHistoryResponse)
async def get_chat_history(
    card_id: str,
    owner_id: OwnerDep,
) -> ChatHistoryResponse:
    """Restore this owner's saved chat for a card (docs/14). Empty when none."""
    async with db.session() as session:
        row = await db.get_conversation(
            session, owner_id=owner_id, kind="chat", card_id=card_id
        )
        messages = list(row.payload) if row else []
    return ChatHistoryResponse(
        messages=[ChatMessage(**m) for m in messages if isinstance(m, dict)]
    )


@router.post("/{card_id}/rabbithole", response_model=RabbitHoleResponse,
             dependencies=[Depends(quota.spend("chat", "quota_chat_per_day"))])
async def explore_rabbithole(
    card_id: str,
    req: RabbitHoleRequest,
    owner_id: OwnerDep,
) -> RabbitHoleResponse:
    """Explore one thread of the rabbit hole (docs/14). Unlike card chat, this is
    NOT confined to the card — it uses the card as an anchor but explains the
    tapped topic from general knowledge and returns fresh follow-on threads.

    The exploration is PERSISTED per owner, keyed by the root topic the journey
    started from: the new step is appended to the stored trail (truncated to the
    depth the client is on, so branching back overwrites the abandoned tail)."""
    topic = req.topic.strip()
    if not topic:
        raise HTTPException(status_code=422, detail="topic is required")
    root = (req.root or topic).strip()

    async with db.session() as session:
        row = await db.get_card_row(session, card_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        if row.state != CardState.READY.value:
            raise HTTPException(status_code=409, detail="card is not ready")
        card = row.to_card()

    result = await llm_rabbithole.explore_async(card, topic, req.trail)
    if result is None:
        raise HTTPException(
            status_code=503,
            detail="rabbit hole is unavailable (no LLM backend configured)",
        )

    step = {
        "topic": topic,
        "explanation": result["explanation"],
        "threads": result["threads"],
    }
    # Append to the stored trail, truncated to the client's current depth so a
    # branch taken after jumping back replaces the abandoned deeper steps.
    async with db.session() as session:
        existing = await db.get_conversation(
            session, owner_id=owner_id, kind="rabbit_hole",
            card_id=card_id, thread=root,
        )
        prior = list(existing.payload) if existing else []
        trail_depth = len(req.trail)
        payload = [*prior[:trail_depth], step]
        await db.save_conversation(
            session,
            owner_id=owner_id,
            kind="rabbit_hole",
            card_id=card_id,
            thread=root,
            payload=payload,
        )
    return RabbitHoleResponse(
        explanation=result["explanation"], threads=result["threads"]
    )


@router.get("/{card_id}/rabbithole", response_model=RabbitHoleHistoryResponse)
async def get_rabbithole_history(
    card_id: str,
    root: str,
    owner_id: OwnerDep,
) -> RabbitHoleHistoryResponse:
    """Restore this owner's saved rabbit-hole trail for a card + root topic."""
    async with db.session() as session:
        row = await db.get_conversation(
            session, owner_id=owner_id, kind="rabbit_hole",
            card_id=card_id, thread=root.strip(),
        )
        steps = list(row.payload) if row else []
    return RabbitHoleHistoryResponse(
        steps=[
            RabbitHoleStep(
                topic=str(s.get("topic", "")),
                explanation=str(s.get("explanation", "")),
                threads=[str(t) for t in (s.get("threads") or [])],
            )
            for s in steps
            if isinstance(s, dict)
        ]
    )


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
