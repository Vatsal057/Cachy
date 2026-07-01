"""Chat-with-your-library endpoint (docs/09 P3): cross-card grounded Q&A.

The conversation is PERSISTED per owner (docs/14): the client replays the
conversation each turn and the model answers from the cards retrieved for the
latest question, then the full turn is saved so reopening library chat restores
the thread. Isolation is by the X-Owner-Id header."""

from __future__ import annotations

import logging

from typing import Annotated

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from app.services import llm_library_chat
from app.store import db

log = logging.getLogger("api.library_chat")
router = APIRouter(prefix="/library", tags=["library"])


class ChatMessage(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class LibraryChatRequest(BaseModel):
    messages: list[ChatMessage]


class SourceCard(BaseModel):
    card_id: str
    one_liner: str


class LibraryChatResponse(BaseModel):
    reply: str
    sources: list[SourceCard]


class LibraryChatHistoryResponse(BaseModel):
    messages: list[ChatMessage]


@router.post("/chat", response_model=LibraryChatResponse)
async def library_chat(
    req: LibraryChatRequest,
    x_owner_id: Annotated[str | None, Header()] = None,
) -> LibraryChatResponse:
    if not req.messages or req.messages[-1].role != "user":
        raise HTTPException(status_code=422, detail="last message must be from user")

    history = [m.model_dump() for m in req.messages]
    result = await llm_library_chat.answer(history)
    if result is None:
        raise HTTPException(
            status_code=503, detail="chat is unavailable (no LLM backend configured)"
        )
    reply, cards = result
    sources = [
        SourceCard(card_id=c.card_id, one_liner=c.base.one_liner or c.base.tldr)
        for c in cards
    ]
    # Persist the full conversation (history + this reply), owner-scoped.
    async with db.session() as session:
        await db.save_conversation(
            session,
            owner_id=x_owner_id,
            kind="library_chat",
            payload=[*history, {"role": "assistant", "content": reply}],
        )
    return LibraryChatResponse(reply=reply, sources=sources)


@router.get("/chat", response_model=LibraryChatHistoryResponse)
async def get_library_chat_history(
    x_owner_id: Annotated[str | None, Header()] = None,
) -> LibraryChatHistoryResponse:
    """Restore this owner's saved library chat (docs/14). Empty when none."""
    async with db.session() as session:
        row = await db.get_conversation(
            session, owner_id=x_owner_id, kind="library_chat"
        )
        messages = list(row.payload) if row else []
    return LibraryChatHistoryResponse(
        messages=[ChatMessage(**m) for m in messages if isinstance(m, dict)]
    )
