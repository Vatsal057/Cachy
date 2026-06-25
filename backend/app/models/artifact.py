"""Artifact catalog models (docs/12).

An *artifact* is a real-world thing a video references — a book, movie, podcast,
product, place, etc. — as opposed to the structured how-to content of the card
itself. Artifacts are extracted by the same single structuring LLM call (docs/04),
then aggregated across all cards into a global, deduplicated catalog.

This is a parallel surface to the block schema, NOT a new block type. The block
vocabulary is unchanged; the structuring output simply grows an `artifacts` list.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class ArtifactType(str, Enum):
    BOOK = "book"
    MOVIE = "movie"
    TV_SHOW = "tv_show"
    PODCAST = "podcast"
    MUSIC = "music"
    PRODUCT = "product"
    PLACE = "place"
    APP = "app"
    OTHER = "other"


def _new_id() -> str:
    return "a_" + uuid.uuid4().hex[:8]


class Artifact(BaseModel):
    """One referenced thing, as emitted by structuring (pre-aggregation)."""

    type: ArtifactType = ArtifactType.OTHER
    title: str
    creator: Optional[str] = None  # author / director / artist / host
    year: Optional[int] = None
    thumbnail: Optional[str] = None  # resolved from a free image API (docs/12)


class CatalogEntry(BaseModel):
    """An aggregated, deduplicated catalog item: one artifact, many source cards."""

    id: str = Field(default_factory=_new_id)
    type: ArtifactType = ArtifactType.OTHER
    title: str
    creator: Optional[str] = None
    year: Optional[int] = None
    thumbnail: Optional[str] = None
    source_card_ids: list[str] = Field(default_factory=list)
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    # User must explicitly save a referenced artifact into the catalog (long-press);
    # unsaved rows still exist as per-card references but stay out of the catalog tab.
    saved: bool = False
    # Optional LLM-generated "what is this" detail, filled on-demand via Fetch info.
    description: Optional[str] = None
