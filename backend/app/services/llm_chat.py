"""Chat Q&A over a single card (docs/13).

A grounded question-answering helper: the user asks about a card, the model
answers using ONLY that card's structured content as context. Reuses the same

Stateless by design — the client holds the conversation and replays it on each
turn; nothing is persisted server-side.
"""

from __future__ import annotations

import logging

from app.config import get_settings
from app.models.card import Card

log = logging.getLogger("services.llm_chat")

_MAX_TURNS = 12  # cap replayed history so context stays small + cheap
_MAX_TOKENS = 600

_SYSTEM = """You are Cachy, answering questions about ONE saved knowledge card.
Use ONLY the card content below as your source of truth. If the answer is not in
the card, say so plainly — do not invent facts. Be concise and direct.
You may use inline markdown: **bold** for key terms and *italic* for emphasis.
Use it sparingly. No other markdown (no headers, no links).

--- CARD ---
{context}
--- END CARD ---"""


def card_context(card: Card) -> str:
    """Flatten a card's base + blocks into plain text the model can reason over."""
    lines: list[str] = []
    if card.base.one_liner:
        lines.append(card.base.one_liner)
    if card.base.tldr:
        lines.append(card.base.tldr)
    for block in card.blocks:
        # blocks are pydantic Block objects; normalise to a plain dict view.
        raw = block.model_dump() if hasattr(block, "model_dump") else block
        lines.append(_block_text(raw))
    return "\n".join(l for l in lines if l and l.strip())


def _block_text(block: dict) -> str:
    """Best-effort text view of any block dict (tolerant of unknown shapes)."""
    if not isinstance(block, dict):
        return ""
    btype = block.get("type")
    if btype == "heading":
        return f"# {block.get('text', '')}"
    if btype in ("paragraph", "callout"):
        return block.get("text", "")
    if btype == "bullet_list":
        return "\n".join(f"- {i}" for i in block.get("items", []))
    if btype == "step_list":
        steps = block.get("steps", [])
        return "\n".join(
            f"{n}. {s.get('text', '')}" for n, s in enumerate(steps, 1)
            if isinstance(s, dict)
        )
    if btype == "key_value":
        pairs = block.get("pairs", [])
        return "\n".join(
            f"{p.get('key', '')}: {p.get('value', '')}" for p in pairs
            if isinstance(p, dict)
        )
    if btype == "checklist":
        items = block.get("items", [])
        return "\n".join(
            f"- {i.get('text', '')}" for i in items if isinstance(i, dict)
        )
    if btype == "link":
        return block.get("label") or block.get("url", "")
    if btype == "map":
        places = block.get("places", [])
        return "\n".join(p.get("name", "") for p in places if isinstance(p, dict))
    if btype == "table":
        rows = block.get("rows", [])
        return "\n".join(
            " | ".join(str(c) for c in r) for r in rows if isinstance(r, list)
        )
    # unknown / forward-compat
    return block.get("text", "") if isinstance(block.get("text"), str) else ""


def _messages(context: str, history: list[dict]) -> list[dict]:
    recent = [m for m in history if m.get("role") in ("user", "assistant")][-_MAX_TURNS:]
    return [{"role": "system", "content": _SYSTEM.format(context=context)}, *recent]


def answer(card: Card, history: list[dict]) -> str | None:
    """Return the assistant's reply, or None if no backend is configured / it fails."""
    context = card_context(card)
    messages = _messages(context, history)
    settings = get_settings()
    if settings.hf_enabled:
        return _call_hf(messages)
    if settings.groq_llm_enabled:
        return _call_groq(messages)
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
        log.warning("chat call (huggingface) failed: %s", e)
        return None


def _call_groq(messages: list[dict]) -> str | None:
    settings = get_settings()
    try:
        from groq import Groq

        client = Groq(api_key=settings.groq_api_key)
        resp = client.chat.completions.create(
            model="llama-3.1-70b-versatile",  # free tier, matches structuring
            messages=messages,
            temperature=0.3,
            max_tokens=_MAX_TOKENS,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip() or None
    except Exception as e:  # noqa: BLE001
        log.warning("chat call (groq) failed: %s", e)
        return None
