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
    ActionItem,
    ActionItems,
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
        action_items: ActionItems | None = None,
        depth: str = "shallow",
        degraded: bool = False,
        degraded_reason: str = "",
    ):
        self.base = base
        self.blocks = blocks  # list of plain dicts (validated), ready for JSON column
        self.primary_action = primary_action
        self.artifacts = artifacts or []  # referenced things for the catalog (docs/12)
        # Gate for the 2nd pass (docs/14): "deep" => run insight analysis;
        # "shallow" => simple card, no extra LLM call. The model judges; the worker
        # acts. Never block the card on this — default shallow.
        self.depth = depth if depth in ("shallow", "deep") else "shallow"
        # Concrete to-dos the video tells the viewer to do (docs/13). Inert
        # (followed=False) at ingestion; the user opts a card into the hub later.
        self.action_items = action_items or ActionItems()
        # True when no LLM produced a usable structured card and we fell back to a
        # plain paragraph — a degraded result the worker surfaces as a warning.
        self.degraded = degraded
        self.degraded_reason = degraded_reason


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
- table          { "type":"table", "headers": [str, ...], "rows": [ [str, ...], ... ] }

Choose the block type that fits the data's SHAPE, not just its topic:
- table       -> a list where each entry has a name AND a description/attribute
                 (e.g. apps + what they do, tools + purpose). PREFER table over
                 bullet_list whenever every item carries a second column of info.
- step_list   -> ordered, sequential instructions to perform (rendered numbered).
- key_value   -> a few attribute/value facts about ONE thing (time, serves, price).
- checklist   -> things to tick off (ingredients, packing, requirements).
- bullet_list -> short, label-only items with NO per-item description.

Formatting rules:
- For a LONG list split across categories, emit a `heading` (level 2) for EACH
  category followed by that category's `table`. Do NOT cram everything into one
  giant table with a repeated category column.
- The app auto-numbers table rows. Do NOT add your own "#"/number/index column.
- You may use inline markdown inside any text field: **bold** for key terms and
  *italic* for emphasis. Use it sparingly. No other markdown (no #, no links).
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
  ],
  "action_items": [          // concrete things the viewer should DO (may be empty)
    str                      // one short imperative task, e.g. "Batch emails into two daily windows"
  ],
  "depth": "shallow|deep"    // does this content warrant deep analysis? (see below)
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
- Inline references: when you mention one of your `artifacts` inside a text field
  (paragraph/bullet/step/callout — NOT table cells), wrap its name in double
  brackets where you introduce it, e.g. "I loved [[Atomic Habits]]." Wrap only
  names that are in your artifacts list, and wrap each name at most once.
- action_items: the concrete, doable tasks the video is telling the viewer to take
  away and DO (e.g. "Drink water before each meal", "Try the Notion template").
  Short imperative phrases, max ~8. These are the takeaways to act on, NOT a
  restatement of every step in a recipe/tutorial. Return an empty list if the
  video is purely informational with nothing to act on.
- depth: judge whether this content rewards DEEPER analysis (claims to fact-check,
  unstated assumptions, open questions, a web of related concepts). Answer "deep"
  ONLY for idea-rich, knowledge-heavy, or argumentative content (e.g. a science
  explainer, an investing thesis, a psychology breakdown, a contested take).
  Answer "shallow" for practical/procedural or lightweight content with nothing
  to interrogate (a recipe, a workout, a product list, a quick how-to, a meme).
  When unsure, answer "shallow". Most videos are shallow.

{vocab}

Extracted text bundle:
---
{bundle}
---
"""


# --------------------------------------------------------------------------- #
# LLM call (selectable backend: huggingface | groq)
# --------------------------------------------------------------------------- #

def complete(prompt: str, *, max_tokens: int = 8192, temperature: float = 0.2) -> str | None:
    """Generic single-prompt completion via the configured backend (HF, with a
    Groq fallback). Shared by the structuring pass and the gated insight pass
    (docs/14). Any failure -> None; callers decide how to degrade."""
    settings = get_settings()
    if settings.hf_enabled:
        out = _call_hf(prompt, max_tokens, temperature)
        if out:
            return out
        # HF's free router 504s on long generations (e.g. big carousels). Rather
        # than drop straight to failure, fall back to Groq when a key exists.
        if settings.groq_api_key.strip():
            log.info("llm: HF backend failed; falling back to Groq")
            return _call_groq(prompt, max_tokens, temperature)
        return None
    if settings.groq_llm_enabled:
        return _call_groq(prompt, max_tokens, temperature)
    return None


def _call_llm(bundle: str) -> str | None:
    """Structuring (pass 1): format the card prompt and complete it."""
    return complete(_PROMPT.format(vocab=_VOCAB_SPEC, bundle=bundle))


def _call_hf(prompt: str, max_tokens: int, temperature: float) -> str | None:
    settings = get_settings()
    try:
        from huggingface_hub import InferenceClient

        client = InferenceClient(api_key=settings.hf_api_key)
        resp = client.chat_completion(
            model=settings.hf_model,  # free Inference Providers, e.g. Qwen2.5-72B-Instruct
            messages=[{"role": "user", "content": prompt}],
            temperature=temperature,
            max_tokens=max_tokens,  # rich carousels (e.g. 140-item lists) overflow a smaller cap
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip()
    except Exception as e:
        log.warning("llm call (huggingface) failed: %s", e)
        return None


def _call_groq(prompt: str, max_tokens: int, temperature: float) -> str | None:
    settings = get_settings()
    try:
        from groq import Groq

        client = Groq(api_key=settings.groq_api_key)
        resp = client.chat.completions.create(
            model=settings.groq_llm_model,  # free tier; default llama-3.3-70b-versatile
            messages=[{"role": "user", "content": prompt}],
            temperature=temperature,
            max_tokens=max_tokens,  # rich carousels (e.g. 140-item lists) overflow a smaller cap
        )
        text = resp.choices[0].message.content if resp.choices else ""
        return (text or "").strip()
    except Exception as e:
        log.warning("llm call (groq) failed: %s", e)
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


def _coerce_action_items(raw_items) -> ActionItems:
    """Validate the to-do list (docs/13): keep non-empty strings, dedupe, cap at 8,
    assign ids, done=False, followed=False (inert until the user opts in). Never
    trust the model — non-list / non-string / empty entries are dropped."""
    out: list[ActionItem] = []
    if not isinstance(raw_items, list):
        return ActionItems()
    seen: set[str] = set()
    for raw in raw_items:
        if not isinstance(raw, str):
            continue
        text = " ".join(raw.split()).strip()
        if not text or len(text) > 200 or text.lower() in seen:
            continue
        seen.add(text.lower())
        out.append(ActionItem(text=text))
        if len(out) >= 8:
            break
    return ActionItems(followed=False, items=out)


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


def _paragraph_fallback(
    bundle: str, transcript: str, caption: str, reason: str = ""
) -> "StructuredCard":
    """Deterministic minimal card. Always renders something sane (docs/04)."""
    base = _synthesize_base(bundle, transcript, caption)
    body = (transcript or caption).strip()
    blocks: list[dict] = []
    if body:
        from app.models.card import ParagraphBlock

        blocks.append(ParagraphBlock(text=body[:2000]).model_dump())
    action = _primary_action_for(base.content_type)
    return StructuredCard(
        base, blocks, action, degraded=True, degraded_reason=reason
    )


def _primary_action_for(content_type: ContentType) -> PrimaryAction:
    kind, label = _ACTION_FOR_TYPE.get(
        content_type, (PrimaryActionKind.NONE, "")
    )
    return PrimaryAction(kind=kind, label=label, payload={})


def _validate(raw_text: str, bundle: str, transcript: str, caption: str) -> "StructuredCard":
    try:
        data = json.loads(_strip_fences(raw_text))
    except (json.JSONDecodeError, TypeError):
        log.warning(
            "structuring: LLM output was not valid JSON (likely truncated) "
            "-> paragraph fallback"
        )
        return _paragraph_fallback(
            bundle, transcript, caption, reason="LLM returned invalid JSON"
        )

    if not isinstance(data, dict):
        log.warning("structuring: LLM output was not a JSON object -> paragraph fallback")
        return _paragraph_fallback(
            bundle, transcript, caption, reason="LLM output not a JSON object"
        )

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
    action_items = _coerce_action_items(data.get("action_items") or [])
    depth = data.get("depth") if data.get("depth") in ("shallow", "deep") else "shallow"

    blocks = _coerce_blocks(data.get("blocks") or [])
    if not blocks:
        # an empty/garbage block list still gets a usable body, but keep any
        # artifacts/action_items the model did surface (neither needs blocks).
        log.warning(
            "structuring: LLM produced no valid blocks -> paragraph fallback"
        )
        fallback = _paragraph_fallback(
            bundle, transcript, caption, reason="no valid blocks in LLM output"
        )
        fallback.artifacts = artifacts
        fallback.action_items = action_items
        return fallback

    return StructuredCard(
        base, blocks, _primary_action_for(base.content_type), artifacts,
        action_items=action_items, depth=depth,
    )


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def structure(bundle: str, transcript: str = "", caption: str = "") -> "StructuredCard":
    """Single text-only LLM call (Groq) + mandatory validation. Always returns a valid
    StructuredCard, degrading to a paragraph fallback when needed."""
    raw = _call_llm(bundle)
    if not raw:
        log.warning(
            "structuring: no LLM backend returned output (no key, or all backends "
            "failed) -> paragraph fallback"
        )
        return _paragraph_fallback(
            bundle, transcript, caption, reason="no LLM output (backend unavailable/failed)"
        )
    return _validate(raw, bundle, transcript, caption)


async def structure_async(
    bundle: str, transcript: str = "", caption: str = ""
) -> "StructuredCard":
    import asyncio

    return await asyncio.to_thread(structure, bundle, transcript, caption)
