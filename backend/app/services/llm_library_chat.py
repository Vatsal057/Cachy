"""Chat across your whole library (docs/09 P3).

Cross-card Q&A: retrieve the cards most relevant to the user's latest question,
build one combined grounded context, and answer from those cards only — citing
which cards were used. Builds on the single-card grounding (services/llm_chat):

- retrieval  : semantic (embeddings) when available, else full-text keywords.
- grounding  : reuses llm_chat.card_context to flatten each card to plain text.
- generation : reuses the same selectable HF/Groq backend as structuring/chat.

Stateless, like single-card chat — the client replays the conversation each turn.
"""

from __future__ import annotations

import logging

from sqlalchemy import or_, select

from app.config import get_settings
from app.models.card import Card, CardState
from app.services import embeddings, llm_chat
from app.store import db

log = logging.getLogger("services.llm_library_chat")

_TOP_K = 5           # cards pulled into context per question
_PER_CARD_CHARS = 1200  # cap each card's grounding text (cost control)
_MAX_TURNS = 12
_MAX_TOKENS = 700

_SYSTEM = """You are Cachy, answering a question using the user's saved knowledge cards.
Use ONLY the cards below as your source of truth. Synthesise across them when useful.
If the answer is not in the cards, say so plainly — do not invent facts. Be concise,
and when helpful mention which card a fact came from by its title.
You may use inline markdown: **bold** for key terms and *italic* for emphasis.
Use it sparingly. No other markdown (no headers, no links).

--- CARDS ---
{context}
--- END CARDS ---"""


async def retrieve(question: str, limit: int = _TOP_K) -> list[Card]:
    """Top cards for a question: semantic when embeddings are on, else full-text."""
    if embeddings.embeddings_enabled():
        semantic = await _retrieve_semantic(question, limit)
        if semantic:
            return semantic
    return await _retrieve_text(question, limit)


async def _retrieve_semantic(question: str, limit: int) -> list[Card]:
    query_vec = embeddings.embed(question)
    if not query_vec:
        return []
    async with db.session() as session:
        rows = (
            await session.execute(
                select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
            )
        ).scalars().all()
    scored = [
        (embeddings.cosine(query_vec, r.embedding), r)
        for r in rows
        if r.embedding
    ]
    scored = [s for s in scored if s[0] > 0.0]
    scored.sort(key=lambda s: s[0], reverse=True)
    return [r.to_card() for _, r in scored[:limit]]


async def _retrieve_text(question: str, limit: int) -> list[Card]:
    needle = f"%{question.lower()}%"
    async with db.session() as session:
        rows = (
            await session.execute(
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
                .limit(limit)
            )
        ).scalars().all()
    if rows:
        return [r.to_card() for r in rows]
    # No keyword hit — fall back to the most recent cards so the model still has
    # something grounded to reason over rather than answering from nothing.
    async with db.session() as session:
        recent = (
            await session.execute(
                select(db.CardRow)
                .where(db.CardRow.state == CardState.READY.value)
                .order_by(db.CardRow.created_at.desc())
                .limit(limit)
            )
        ).scalars().all()
    return [r.to_card() for r in recent]


def _context(cards: list[Card]) -> str:
    blocks: list[str] = []
    for c in cards:
        title = c.base.one_liner or c.base.tldr or c.card_id
        body = llm_chat.card_context(c)[:_PER_CARD_CHARS]
        blocks.append(f"### {title}\n{body}")
    return "\n\n".join(blocks)


def _messages(context: str, history: list[dict]) -> list[dict]:
    recent = [m for m in history if m.get("role") in ("user", "assistant")][-_MAX_TURNS:]
    return [{"role": "system", "content": _SYSTEM.format(context=context)}, *recent]


def _latest_question(history: list[dict]) -> str:
    for m in reversed(history):
        if m.get("role") == "user":
            return m.get("content", "")
    return ""


async def answer(history: list[dict]) -> tuple[str, list[Card]] | None:
    """Return (reply, source_cards) or None if no LLM backend is configured.
    Retrieval is grounded on the latest user question."""
    cards = await retrieve(_latest_question(history))
    reply = await _generate(_context(cards), history)
    if reply is None:
        return None
    return reply, cards


async def _generate(context: str, history: list[dict]) -> str | None:
    import asyncio

    messages = _messages(context, history)
    settings = get_settings()
    if settings.cerebras_enabled:
        result = await asyncio.to_thread(_call_cerebras, messages)
        if result is not None:
            return result
    if settings.hf_enabled:
        result = await asyncio.to_thread(_call_hf, messages)
        if result is not None:
            return result
    if settings.groq_llm_enabled:
        return await asyncio.to_thread(_call_groq, messages)
    return None


def _call_cerebras(messages: list[dict]) -> str | None:
    settings = get_settings()
    try:
        from cerebras.cloud.sdk import Cerebras

        client = Cerebras(api_key=settings.cerebras_api_key)
        resp = client.chat.completions.create(
            model=settings.cerebras_llm_model,
            messages=messages,
            temperature=0.3,
            max_tokens=_MAX_TOKENS,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip() or None
    except Exception as e:  # noqa: BLE001
        log.warning("library chat call (cerebras) failed: %s", e)
        return None


def _call_hf(messages: list[dict]) -> str | None:
    settings = get_settings()
    try:
        from huggingface_hub import InferenceClient

        client = InferenceClient(api_key=settings.hf_api_key)
        resp = client.chat_completion(
            model=settings.hf_model,
            messages=messages,
            temperature=0.3,
            max_tokens=_MAX_TOKENS,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip() or None
    except Exception as e:  # noqa: BLE001
        log.warning("library chat call (huggingface) failed: %s", e)
        return None


def _call_groq(messages: list[dict]) -> str | None:
    settings = get_settings()
    try:
        from groq import Groq

        client = Groq(api_key=settings.groq_api_key)
        resp = client.chat.completions.create(
            model="llama-3.1-70b-versatile",
            messages=messages,
            temperature=0.3,
            max_tokens=_MAX_TOKENS,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip() or None
    except Exception as e:  # noqa: BLE001
        log.warning("library chat call (groq) failed: %s", e)
        return None
