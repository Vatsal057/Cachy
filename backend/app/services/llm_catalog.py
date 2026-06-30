"""On-demand catalog detail (Fetch info): a single text-only LLM call that
describes a referenced artifact — what it is, what it's about, why it matters.

Groq backend. Best-effort: any failure returns None and the caller leaves the
artifact's description untouched."""

from __future__ import annotations

import logging

from app.config import get_settings
from app.models.artifact import Artifact, ArtifactType

log = logging.getLogger("services.llm_catalog")

_PROMPT = """You are writing a short catalog entry for a referenced {type_label}.

{name_line}

Write a concise, factual overview a reader would find useful:
- what it is and what it's about (2-4 sentences),
- who it's for or why it's notable, if relevant.

Plain prose only — no markdown, no headings, no bullet points, no preamble.
If you are not confident this is a real, identifiable {type_label}, say so briefly
instead of inventing details."""


def _name_line(title: str, creator: str | None, year: int | None) -> str:
    parts = [f'Title: "{title}"']
    if creator:
        parts.append(f"By: {creator}")
    if year:
        parts.append(f"Year: {year}")
    return "\n".join(parts)


def _call_llm(prompt: str) -> str | None:
    """Plain text completion via Groq."""
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
            max_tokens=512,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip()
    except Exception as e:
        log.warning("catalog describe (groq) failed: %s", e)
        return None


def describe(
    title: str,
    type_: ArtifactType = ArtifactType.OTHER,
    creator: str | None = None,
    year: int | None = None,
) -> str | None:
    """Generate a detailed description for an artifact. None on any failure."""
    if not title.strip():
        return None
    prompt = _PROMPT.format(
        type_label=type_.value.replace("_", " "),
        name_line=_name_line(title.strip(), creator, year),
    )
    raw = _call_llm(prompt)
    if not raw:
        log.info("catalog describe: no LLM output for %r", title)
        return None
    text = raw.strip()
    return text or None


async def describe_async(
    title: str,
    type_: ArtifactType = ArtifactType.OTHER,
    creator: str | None = None,
    year: int | None = None,
) -> str | None:
    import asyncio

    return await asyncio.to_thread(describe, title, type_, creator, year)


# Convenience overload for an Artifact dataclass, if a caller has one.
def describe_artifact(art: Artifact) -> str | None:
    return describe(art.title, art.type, art.creator, art.year)
