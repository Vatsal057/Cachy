"""The block schema — the backend↔frontend contract (docs/04).

This module is the source of truth in code. Any block-shape change must update
docs/04-structuring-and-schema.md and bump SCHEMA_VERSION.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Annotated, Any, Literal, Optional, Union

from pydantic import BaseModel, Field, TypeAdapter, ValidationError, field_validator

SCHEMA_VERSION = "1.8"  # 1.1: artifacts list (docs/12); 1.2: base.tags (docs/09); 1.3: action_items (docs/13); 1.4: insight layer (docs/14); 1.5: collections; 1.6: insight quiz (topic_map dropped); 1.7: web enrichment layer (SerpApi sources); 1.8: verdict timeline (per-window claim verdicts)


# --------------------------------------------------------------------------- #
# Enums
# --------------------------------------------------------------------------- #

class CardState(str, Enum):
    QUEUED = "queued"
    PROCESSING = "processing"
    READY = "ready"
    FAILED = "failed"


class FailureReason(str, Enum):
    UNAVAILABLE = "unavailable"
    NO_CONTENT = "no_content"
    UNSUPPORTED = "unsupported"
    TIMEOUT = "timeout"


class ContentType(str, Enum):
    RECIPE = "recipe"
    WORKOUT = "workout"
    TUTORIAL = "tutorial"
    TIP = "tip"
    PRODUCT_LIST = "product_list"
    TRAVEL = "travel"
    NEWS_EXPLAINER = "news_explainer"
    OTHER = "other"


class PrimaryActionKind(str, Enum):
    SHOPPING_LIST = "shopping_list"
    SCHEDULE = "schedule"
    SAVE_PLACE = "save_place"
    REMINDER = "reminder"
    EXPORT = "export"
    NONE = "none"


# --------------------------------------------------------------------------- #
# Block vocabulary (docs/04). Each block has `type` + `id` + type-specific fields.
# --------------------------------------------------------------------------- #

def _new_id() -> str:
    return "b_" + uuid.uuid4().hex[:8]


class _BlockBase(BaseModel):
    id: str = Field(default_factory=_new_id)


class HeadingBlock(_BlockBase):
    type: Literal["heading"] = "heading"
    text: str
    level: int = 2


class ParagraphBlock(_BlockBase):
    type: Literal["paragraph"] = "paragraph"
    text: str


class BulletListBlock(_BlockBase):
    type: Literal["bullet_list"] = "bullet_list"
    items: list[str]


class Step(BaseModel):
    text: str
    checkable: bool = True


class StepListBlock(_BlockBase):
    type: Literal["step_list"] = "step_list"
    steps: list[Step]


class KeyValuePair(BaseModel):
    key: str
    value: str


class KeyValueBlock(_BlockBase):
    type: Literal["key_value"] = "key_value"
    pairs: list[KeyValuePair]


class ChecklistItem(BaseModel):
    text: str
    checked: bool = False


class ChecklistBlock(_BlockBase):
    type: Literal["checklist"] = "checklist"
    items: list[ChecklistItem]


class CalloutBlock(_BlockBase):
    type: Literal["callout"] = "callout"
    variant: Literal["info", "warning", "caveat", "source"] = "info"
    text: str
    confidence: Literal["high", "medium", "low", "unverified"] = "unverified"
    source_url: Optional[str] = None


class LinkBlock(_BlockBase):
    type: Literal["link"] = "link"
    url: str
    label: Optional[str] = None


# Phase 2 blocks — modelled so the schema is forward-stable; renderer may skip.
class Place(BaseModel):
    name: str
    lat: Optional[float] = None
    lng: Optional[float] = None
    note: str = ""


class MapBlock(_BlockBase):
    type: Literal["map"] = "map"
    places: list[Place]


class TableBlock(_BlockBase):
    type: Literal["table"] = "table"
    headers: list[str]
    rows: list[list[str]]


Block = Annotated[
    Union[
        HeadingBlock,
        ParagraphBlock,
        BulletListBlock,
        StepListBlock,
        KeyValueBlock,
        ChecklistBlock,
        CalloutBlock,
        LinkBlock,
        MapBlock,
        TableBlock,
    ],
    Field(discriminator="type"),
]

_BLOCK_ADAPTER: TypeAdapter = TypeAdapter(Block)


def sanitize_blocks(raw: object) -> tuple[list[dict], list[str]]:
    """Split stored block JSON into blocks the current schema accepts, plus a
    reason for each one it rejects.

    Blocks are LLM-authored and rows written by earlier schema versions live in
    the database forever, so any given row can legitimately hold a block this
    build no longer understands. `Card.blocks` is a discriminated union, so
    feeding it such a block raises ValidationError. Dropping only the offending
    block keeps the rest of the card readable; letting the error escape takes
    down every card sharing the response.
    """
    if raw is None:
        return [], []
    if not isinstance(raw, list):
        return [], [f"blocks was {type(raw).__name__}, expected a list"]
    kept: list[dict] = []
    dropped: list[str] = []
    for index, block in enumerate(raw):
        if not isinstance(block, dict):
            dropped.append(f"[{index}] {type(block).__name__}, expected an object")
            continue
        try:
            _BLOCK_ADAPTER.validate_python(block)
        except ValidationError as exc:
            dropped.append(
                f"[{index}] type={block.get('type', '<missing>')!r}: "
                f"{exc.error_count()} validation error(s)"
            )
            continue
        kept.append(block)
    return kept, dropped


# The renderable vocabulary, used by validation to drop unknown block types.
VOCAB: set[str] = {
    "heading",
    "paragraph",
    "bullet_list",
    "step_list",
    "key_value",
    "checklist",
    "link",
    "map",
    "table",
}


# --------------------------------------------------------------------------- #
# Card object (docs/04)
# --------------------------------------------------------------------------- #

class Source(BaseModel):
    url: str
    platform: Optional[str] = None  # instagram | youtube
    creator: Optional[str] = None
    caption: str = ""
    duration_seconds: Optional[int] = None
    resolver: Optional[str] = None


class Base(BaseModel):
    one_liner: str = ""
    tldr: str = ""
    content_type: ContentType = ContentType.OTHER
    type_confidence: float = 0.0
    tags: list[str] = Field(default_factory=list)  # auto-tags for browse/filter (docs/09)


class PrimaryAction(BaseModel):
    kind: PrimaryActionKind = PrimaryActionKind.NONE
    label: str = ""
    payload: dict = Field(default_factory=dict)


class ActionItem(BaseModel):
    """One concrete thing the video tells the viewer to do (docs/13)."""
    id: str = Field(default_factory=lambda: "a_" + uuid.uuid4().hex[:8])
    text: str
    done: bool = False


class ActionItems(BaseModel):
    """Per-card action list (docs/13). Generated inert at ingestion; `followed`
    flips to True only when the user opts the card into the Actions hub."""
    followed: bool = False
    items: list[ActionItem] = Field(default_factory=list)


# --------------------------------------------------------------------------- #
# Insight layer (docs/14) — the optional "deep" analysis. Populated by a SECOND,
# gated LLM pass ONLY for knowledge-rich cards; a simple reel (recipe, a quick
# tip) carries `insight = None` and renders none of this. Within a deep card each
# sub-section is independently optional — emit only what the content warrants.
#
# Everything here is ACTIONABLE, never a passive list: rabbit-hole threads are
# tappable doorways into the rabbit-hole explorer, the quiz turns the card into
# active recall, and the research prompt is paste-ready. (The old topic map was
# read-only orientation with nothing to do — dropped in schema 1.6.)
# --------------------------------------------------------------------------- #

class RabbitHole(BaseModel):
    """Threads to pull on to go deeper. Each becomes a tappable prompt in the UI
    (opens grounded chat). Each list is independently optional."""
    questions: list[str] = Field(default_factory=list)
    adjacent_topics: list[str] = Field(default_factory=list)
    advanced_concepts: list[str] = Field(default_factory=list)

    def is_empty(self) -> bool:
        return not (self.questions or self.adjacent_topics or self.advanced_concepts)


class TopicMap(BaseModel):
    """Deprecated (schema 1.6): retained only so old stored cards still
    deserialize. No longer generated or rendered."""
    center: str
    nodes: list[str] = Field(default_factory=list)  # satellite labels


class QuizQuestion(BaseModel):
    """One multiple-choice question for active recall (docs/14). `options` holds
    the choices; `answer_index` points at the correct one; `explanation` is the
    one-line 'why' revealed after answering."""
    question: str
    options: list[str] = Field(default_factory=list)
    answer_index: int = 0
    explanation: str = ""

    def is_valid(self) -> bool:
        return bool(
            self.question.strip()
            and 2 <= len(self.options) <= 4
            and 0 <= self.answer_index < len(self.options)
        )


class Insight(BaseModel):
    rabbit_hole: RabbitHole = Field(default_factory=RabbitHole)
    # A short "test yourself" set generated from the card — active recall. Serialized
    # as a plain list of questions (the client + feed consume a bare list).
    quiz: list[QuizQuestion] = Field(default_factory=list)
    # Deprecated (schema 1.6): kept for backward-compatible deserialization only.
    topic_map: Optional[TopicMap] = None
    # A ready-to-paste deep-research prompt for an external LLM (docs/14).
    deep_research_prompt: Optional[str] = None

    @field_validator("quiz", mode="before")
    @classmethod
    def _coerce_quiz(cls, value):
        """Tolerate the legacy wrapped shape ({"questions": [...]}) that older
        rows may have stored, normalising it to a plain list."""
        if isinstance(value, dict):
            return value.get("questions", [])
        return value

    def has_content(self) -> bool:
        """True when at least one sub-section is non-empty — the gate the worker
        and clients use to decide whether to attach/render the layer at all."""
        return bool(
            not self.rabbit_hole.is_empty()
            or self.quiz
            or self.deep_research_prompt
        )


class EnrichmentSource(BaseModel):
    """One live web source on the card's topic (SerpApi Google engine)."""
    title: str
    link: str
    snippet: str = ""
    source: str = ""


class Enrichment(BaseModel):
    """The web-enrichment layer: the query the card's topic became, plus the
    top live sources. None on the card when the step had no key or found
    nothing — genuinely optional, like insight."""
    query: str = ""
    sources: list[EnrichmentSource] = Field(default_factory=list)

    def has_content(self) -> bool:
        return bool(self.sources)


# --------------------------------------------------------------------------- #
# Verdict Timeline layer (schema 1.8) — per-window factual-claim verification.
# The verdict agent checks each 30-second transcript window's claims against
# live, date-bounded SerpApi evidence. Verdicts are deterministic (LLM proposes
# stances, code disposes): green = 2+ distinct corroborating domains,
# red = dated contradiction, amber = single corroboration, grey = insufficient
# evidence. The timeline persists on the card: the note remembers what the web
# confirmed ("checks and remembers").
# --------------------------------------------------------------------------- #

class VerdictEvidence(BaseModel):
    """One dated web source behind a verdict, with its stance toward the claim."""
    title: str
    link: str
    snippet: str = ""
    source: str = ""
    date: str = ""
    stance: str = "supports"  # supports | contradicts


class ClaimVerdict(BaseModel):
    """One checked claim: where in the video, what was claimed, the verdict,
    and the dated evidence behind it."""
    window_index: int
    window_start: float = 0.0
    window_end: float = 0.0
    claim: str
    verdict: str = "grey"  # green | amber | red | grey
    note: str = ""
    evidence: list[VerdictEvidence] = Field(default_factory=list)
    query: str = ""
    trace: dict[str, Any] = Field(default_factory=dict)


class VerdictTimeline(BaseModel):
    """The whole timeline for one video. None on the card when the video had
    no transcript, no checkable claims, or no SerpApi key — genuinely optional."""
    video_id: str = ""
    checked_at: str = ""
    published_date: str = ""
    claims: list[ClaimVerdict] = Field(default_factory=list)

    def has_content(self) -> bool:
        return bool(self.claims)


class Media(BaseModel):
    thumbnail: Optional[str] = None
    keyframes: list[str] = Field(default_factory=list)


class ExtractionFlags(BaseModel):
    transcript: bool = False
    ocr: bool = False
    visual: bool = False


class Meta(BaseModel):
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    extraction: ExtractionFlags = Field(default_factory=ExtractionFlags)


class Card(BaseModel):
    schema_version: str = SCHEMA_VERSION
    card_id: str
    state: CardState = CardState.QUEUED
    failure_reason: Optional[FailureReason] = None

    source: Source
    base: Base = Field(default_factory=Base)
    primary_action: PrimaryAction = Field(default_factory=PrimaryAction)
    action_items: ActionItems = Field(default_factory=ActionItems)
    blocks: list[Block] = Field(default_factory=list)
    # Deep analysis (docs/14). None for simple cards; only the gated 2nd pass fills it.
    insight: Optional[Insight] = None
    # Web enrichment (SerpApi). None when the step had no key or found nothing;
    # filled for every card whose topic returned live sources.
    enrichment: Optional[Enrichment] = None
    # Verdict Timeline (SerpApi, schema 1.8). None when the video had no
    # transcript, no checkable claims, or no key; filled per YouTube card.
    verdicts: Optional[VerdictTimeline] = None
    media: Media = Field(default_factory=Media)
    meta: Meta = Field(default_factory=Meta)
    # Collection this card belongs to (auto-assigned by pipeline, user-overridable).
    collection_id: Optional[str] = None
