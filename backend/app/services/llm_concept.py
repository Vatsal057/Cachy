"""On-demand concept definition: a single text-only LLM call that explains
what an evergreen idea is — in plain prose, grounded in general knowledge.

Groq backend. Best-effort: any failure returns None."""

from __future__ import annotations

import logging

from app.config import get_settings

log = logging.getLogger("services.llm_concept")

_PROMPT = """Define the concept "{name}" in 2-3 concise sentences.

Write a plain prose overview a curious person would find useful:
- what the idea means,
- why it matters or where it appears.

Plain prose only — no markdown, no headings, no bullet points, no preamble."""


def _call_llm(prompt: str) -> str | None:
    settings = get_settings()
    if settings.groq_llm_enabled:
        return _call_groq(prompt)
    return None


def _call_groq(prompt: str) -> str | None:
    settings = get_settings()
    try:
        from groq import Groq

        client = Groq(api_key=settings.groq_api_key)
        resp = client.chat.completions.create(
            model=settings.groq_llm_model,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3,
            max_tokens=160,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip()
    except Exception as e:
        log.warning("concept define (groq) failed: %s", e)
        return None


def define(name: str) -> str | None:
    """Generate a 2-3 sentence definition for a concept. None on any failure."""
    if not name.strip():
        return None
    prompt = _PROMPT.format(name=name.strip())
    raw = _call_llm(prompt)
    if not raw:
        log.info("concept define: no LLM output for %r", name)
        return None
    return raw.strip() or None


async def define_async(name: str) -> str | None:
    import asyncio

    return await asyncio.to_thread(define, name)
