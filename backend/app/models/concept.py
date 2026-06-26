"""Concept node models.

A concept is a source-independent evergreen idea ("compounding", "loss aversion")
mined from every card and deduplicated across the whole library. Mirrors the
artifact/catalog subsystem at every layer.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, Field


def _new_id() -> str:
    return "c_" + uuid.uuid4().hex[:8]


class Concept(BaseModel):
    """One concept name, as emitted by structuring (pre-aggregation)."""

    name: str


class ConceptEntry(BaseModel):
    """An aggregated, deduplicated concept: one idea, many source cards."""

    id: str = Field(default_factory=_new_id)
    name: str
    source_card_ids: list[str] = Field(default_factory=list)
    definition: Optional[str] = None
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
