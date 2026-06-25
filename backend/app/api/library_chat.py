"""Chat-with-your-library endpoint (docs/09 P3): cross-card grounded Q&A.

Stateless, mirroring single-card chat (/cards/{id}/chat): the client replays the
conversation each turn. The model answers from the cards retrieved for the latest
question and reports which cards it used."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.services import llm_library_chat

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


@router.post("/chat", response_model=LibraryChatResponse)
async def library_chat(req: LibraryChatRequest) -> LibraryChatResponse:
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
    return LibraryChatResponse(reply=reply, sources=sources)
