"""Structuring (docs/04): a single text-only LLM call returns a JSON card;
this module then ALWAYS validates it before persisting. The guarantee — a card
always renders something sane — comes from validation + paragraph fallback, never
from trusting the model.

The LLM backend is selectable (config.llm_backend): HuggingFace Inference Providers
(default, Qwen2.5-72B-Instruct) or Groq. No key? Bad JSON? Empty output?
-> deterministic paragraph fallback."""

from __future__ import annotations

import json
import logging
import re

from app.config import get_settings
from app.models.artifact import Artifact, ArtifactType
from app.models.card import (
    Base,
    Block,
    ContentType,
    PrimaryAction,
    PrimaryActionKind,
    _new_id,
    VOCAB,
)
from pydantic import TypeAdapter, ValidationError

log = logging.getLogger("pipeline.structuring")

_block_adapter: TypeAdapter[Block] = TypeAdapter(Block)

# Required fields per block type — a block missing these is dropped (docs/04).
_REQUIRED: dict[str, list[str]] = {
    "heading": ["text"],
    "paragraph": ["text"],
    "bullet_list": ["items"],
    "step_list": ["steps"],
    "key_value": ["pairs"],
    "checklist": ["items"],
    "callout": ["text"],
    "link": ["url"],
    "map": ["places"],
    "table": ["headers", "rows"],
}

# content_type -> primary action (docs/04)
_ACTION_FOR_TYPE: dict[ContentType, tuple[PrimaryActionKind, str]] = {
    ContentType.RECIPE: (PrimaryActionKind.SHOPPING_LIST, "Add to shopping list"),
    ContentType.WORKOUT: (PrimaryActionKind.SCHEDULE, "Schedule a session"),
    ContentType.TRAVEL: (PrimaryActionKind.SAVE_PLACE, "Save place"),
    ContentType.TUTORIAL: (PrimaryActionKind.REMINDER, "Set a reminder"),
    ContentType.TIP: (PrimaryActionKind.REMINDER, "Set a reminder"),
    ContentType.PRODUCT_LIST: (PrimaryActionKind.EXPORT, "Export list"),
    ContentType.NEWS_EXPLAINER: (PrimaryActionKind.NONE, ""),
    ContentType.OTHER: (PrimaryActionKind.NONE, ""),
}


class StructuredCard:
    """Validated structuring output: base + blocks + primary_action + artifacts."""

    def __init__(
        self,
        base: Base,
        blocks: list[dict],
        primary_action: PrimaryAction,
        artifacts: list[Artifact] | None = None,
    ):
        self.base = base
        self.blocks = blocks  # list of plain dicts (validated), ready for JSON column
        self.primary_action = primary_action
        self.artifacts = artifacts or []  # referenced things for the catalog (docs/12)


# --------------------------------------------------------------------------- #
# Prompt
# --------------------------------------------------------------------------- #

_VOCAB_SPEC = """
Allowed block types (use ONLY these; never invent a type):
- heading        { "type":"heading", "text": str, "level": 1-3 }
- paragraph      { "type":"paragraph", "text": str }
- bullet_list    { "type":"bullet_list", "items": [str, ...] }
- step_list      { "type":"step_list", "steps": [ {"text": str, "checkable": true} ] }
- key_value      { "type":"key_value", "pairs": [ {"key": str, "value": str} ] }
- checklist      { "type":"checklist", "items": [ {"text": str, "checked": false} ] }
- callout        { "type":"callout", "variant":"info|warning|caveat|source", "text": str,
                   "confidence":"high|medium|low|unverified", "source_url": null }
- link           { "type":"link", "url": str, "label": str }
""".strip()

_PROMPT = """You convert a short-form video's extracted text into a structured knowledge card.

Return ONLY a JSON object (no prose, no markdown fences) with this exact shape:
{{
  "base": {{
    "one_liner": str,        // what the video GIVES the viewer, not what it's about
    "tldr": str,             // a standalone summary understandable without the video
    "content_type": "recipe|workout|tutorial|tip|product_list|travel|news_explainer|other",
    "type_confidence": 0.0-1.0,
    "tags": [str]            // 3-6 short lowercase topical tags (e.g. "fitness", "budgeting")
  }},
  "blocks": [ ... ],         // ordered list using ONLY the allowed block types
  "artifacts": [             // real, named things the video REFERENCES (may be empty)
    {{ "type": "book|movie|tv_show|podcast|music|product|place|app|other",
       "title": str,         // the proper name of the thing
       "creator": str|null,  // author / director / artist / host / brand
       "year": int|null }}
  ]
}}

Rules:
- base.one_liner and base.tldr MUST always be non-empty.
- base.tags: 3-6 short, lowercase, topical keywords for browsing/grouping the card.
- Choose content_type, then arrange blocks to fit it (e.g. recipe -> heading,
  key_value(time/serves), checklist(ingredients), step_list(steps)).
- Use ONLY the allowed block types below. Output strict JSON.
- artifacts: include ONLY concrete, named, real-world things the video names
  (e.g. a specific book, movie, podcast, product, or place). Do NOT invent any;
  if the video names none, return an empty list. Use the most specific type.

{vocab}

Extracted text bundle:
---
{bundle}
---
"""


# --------------------------------------------------------------------------- #
# LLM call (selectable backend: huggingface | groq)
# --------------------------------------------------------------------------- #

def _call_llm(bundle: str) -> str | None:
    """Dispatch to the configured structuring backend. Any failure -> None,
    which the caller turns into a paragraph fallback."""
    settings = get_settings()
    if settings.hf_enabled:
        return _call_hf(bundle)
    if settings.groq_llm_enabled:
        return _call_groq(bundle)
    return None


def _call_hf(bundle: str) -> str | None:
    settings = get_settings()
    try:
        from huggingface_hub import InferenceClient

        client = InferenceClient(api_key=settings.hf_api_key)
        prompt = _PROMPT.format(vocab=_VOCAB_SPEC, bundle=bundle)
        resp = client.chat_completion(
            model=settings.hf_model,  # free Inference Providers, e.g. Qwen2.5-72B-Instruct
            messages=[{"role": "user", "content": prompt}],
            temperature=0.2,
            max_tokens=2048,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip()
    except Exception as e:
        log.warning("structuring call (huggingface) failed: %s", e)
        return None


def _call_groq(bundle: str) -> str | None:
    settings = get_settings()
    try:
        from groq import Groq

        client = Groq(api_key=settings.groq_api_key)
        prompt = _PROMPT.format(vocab=_VOCAB_SPEC, bundle=bundle)
        resp = client.chat.completions.create(
            model="llama-3.1-70b-versatile",  # free tier, active
            messages=[{"role": "user", "content": prompt}],
            temperature=0.2,
            max_tokens=2048,
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip()
    except Exception as e:
        log.warning("structuring call (groq) failed: %s", e)
        return None


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #

def _strip_fences(text: str) -> str:
    text = text.strip()
    # ```json ... ``` or ``` ... ```
    fence = re.match(r"^```[a-zA-Z]*\s*(.*?)\s*```$", text, re.DOTALL)
    if fence:
        return fence.group(1).strip()
    return text


def _coerce_blocks(raw_blocks: list) -> list[dict]:
    """Drop unknown types and blocks missing required fields; validate the rest
    through the Pydantic union; assign ids. Out-of-vocab -> dropped (docs/04)."""
    out: list[dict] = []
    if not isinstance(raw_blocks, list):
        return out
    for raw in raw_blocks:
        if not isinstance(raw, dict):
            continue
        btype = raw.get("type")
        if btype not in VOCAB:
            continue
        required = _REQUIRED.get(btype, [])
        if any(raw.get(f) in (None, "", [], {}) for f in required):
            continue
        raw.setdefault("id", _new_id())
        try:
            block = _block_adapter.validate_python(raw)
        except ValidationError:
            continue
        out.append(block.model_dump())
    return out


def _coerce_artifacts(raw_artifacts: list) -> list[Artifact]:
    """Validate referenced things; drop anything without a usable title or with a
    bad shape. Never trust the model — a malformed entry is silently skipped."""
    out: list[Artifact] = []
    if not isinstance(raw_artifacts, list):
        return out
    seen: set[tuple[str, str]] = set()
    for raw in raw_artifacts:
        if not isinstance(raw, dict):
            continue
        title = (raw.get("title") or "").strip()
        if not title:
            continue
        try:
            atype = ArtifactType(raw.get("type", "other"))
        except ValueError:
            atype = ArtifactType.OTHER
        key = (atype.value, title.lower())
        if key in seen:
            continue
        seen.add(key)
        creator = (raw.get("creator") or None)
        if isinstance(creator, str):
            creator = creator.strip() or None
        year = raw.get("year")
        year = int(year) if isinstance(year, (int, float)) else None
        out.append(Artifact(type=atype, title=title, creator=creator, year=year))
    return out


def _coerce_tags(raw_tags) -> list[str]:
    """Validate auto-tags: keep short lowercase strings, dedupe, cap at 6 (docs/09).
    Never trust the model — non-list / non-string / empty entries are dropped."""
    out: list[str] = []
    if not isinstance(raw_tags, list):
        return out
    seen: set[str] = set()
    for raw in raw_tags:
        if not isinstance(raw, str):
            continue
        tag = " ".join(raw.lower().split()).strip()
        if not tag or len(tag) > 40 or tag in seen:
            continue
        seen.add(tag)
        out.append(tag)
        if len(out) >= 6:
            break
    return out


def _synthesize_base(bundle: str, transcript: str, caption: str) -> Base:
    """When the model omits one_liner/tldr, build something usable from raw text."""
    source = (transcript or caption or "").strip()
    if not source:
        # last resort: pull from the bundle text
        source = re.sub(r"^(CAPTION|TRANSCRIPT|ON-SCREEN TEXT|SOURCE):", "",
                        bundle, flags=re.MULTILINE).strip()
    first = (source.split(".")[0] or source)[:120].strip() or "Saved video"
    tldr = source[:400].strip() or first
    return Base(one_liner=first, tldr=tldr, content_type=ContentType.OTHER)


def _paragraph_fallback(bundle: str, transcript: str, caption: str) -> "StructuredCard":
    """Deterministic minimal card. Always renders something sane (docs/04)."""
    base = _synthesize_base(bundle, transcript, caption)
    body = (transcript or caption).strip()
    blocks: list[dict] = []
    if body:
        from app.models.card import ParagraphBlock

        blocks.append(ParagraphBlock(text=body[:2000]).model_dump())
    action = _primary_action_for(base.content_type)
    return StructuredCard(base, blocks, action)


def _primary_action_for(content_type: ContentType) -> PrimaryAction:
    kind, label = _ACTION_FOR_TYPE.get(
        content_type, (PrimaryActionKind.NONE, "")
    )
    return PrimaryAction(kind=kind, label=label, payload={})


def _validate(raw_text: str, bundle: str, transcript: str, caption: str) -> "StructuredCard":
    try:
        data = json.loads(_strip_fences(raw_text))
    except (json.JSONDecodeError, TypeError):
        log.info("structuring: JSON parse failed -> paragraph fallback")
        return _paragraph_fallback(bundle, transcript, caption)

    if not isinstance(data, dict):
        return _paragraph_fallback(bundle, transcript, caption)

    raw_base = data.get("base") or {}
    try:
        ctype = ContentType(raw_base.get("content_type", "other"))
    except ValueError:
        ctype = ContentType.OTHER

    base = Base(
        one_liner=(raw_base.get("one_liner") or "").strip(),
        tldr=(raw_base.get("tldr") or "").strip(),
        content_type=ctype,
        type_confidence=float(raw_base.get("type_confidence") or 0.0),
        tags=_coerce_tags(raw_base.get("tags")),
    )
    # one_liner / tldr must be non-empty (docs/04)
    if not base.one_liner or not base.tldr:
        synth = _synthesize_base(bundle, transcript, caption)
        base.one_liner = base.one_liner or synth.one_liner
        base.tldr = base.tldr or synth.tldr

    artifacts = _coerce_artifacts(data.get("artifacts") or [])

    blocks = _coerce_blocks(data.get("blocks") or [])
    if not blocks:
        # an empty/garbage block list still gets a usable body, but keep any
        # artifacts the model did surface (the catalog doesn't need blocks).
        fallback = _paragraph_fallback(bundle, transcript, caption)
        fallback.artifacts = artifacts
        return fallback

    return StructuredCard(
        base, blocks, _primary_action_for(base.content_type), artifacts
    )


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def structure(bundle: str, transcript: str = "", caption: str = "") -> "StructuredCard":
    """Single text-only LLM call (Groq) + mandatory validation. Always returns a valid
    StructuredCard, degrading to a paragraph fallback when needed."""
    raw = _call_llm(bundle)
    if not raw:
        return _paragraph_fallback(bundle, transcript, caption)
    return _validate(raw, bundle, transcript, caption)


async def structure_async(
    bundle: str, transcript: str = "", caption: str = ""
) -> "StructuredCard":
    import asyncio

    return await asyncio.to_thread(structure, bundle, transcript, caption)
