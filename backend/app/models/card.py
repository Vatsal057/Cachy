"""The block schema — the backend↔frontend contract (docs/04).

This module is the source of truth in code. Any block-shape change must update
docs/04-structuring-and-schema.md and bump SCHEMA_VERSION.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Annotated, Literal, Optional, Union

from pydantic import BaseModel, Field

SCHEMA_VERSION = "1.0"


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

# The renderable vocabulary, used by validation to drop unknown block types.
VOCAB: set[str] = {
    "heading",
    "paragraph",
    "bullet_list",
    "step_list",
    "key_value",
    "checklist",
    "callout",
    "link",
    "map",
    "table",
}


# --------------------------------------------------------------------------- #
# Card object (docs/04)
# --------------------------------------------------------------------------- #

class Source(BaseModel):
    url: str
    platform: Optional[str] = None  # instagram | tiktok | youtube
    creator: Optional[str] = None
    caption: str = ""
    duration_seconds: Optional[int] = None
    resolver: Optional[str] = None


class Base(BaseModel):
    one_liner: str = ""
    tldr: str = ""
    content_type: ContentType = ContentType.OTHER
    type_confidence: float = 0.0


class PrimaryAction(BaseModel):
    kind: PrimaryActionKind = PrimaryActionKind.NONE
    label: str = ""
    payload: dict = Field(default_factory=dict)


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
    blocks: list[Block] = Field(default_factory=list)
    media: Media = Field(default_factory=Media)
    meta: Meta = Field(default_factory=Meta)
