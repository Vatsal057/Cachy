"""Collection models (docs/09 library & retrieval).

A *collection* is a user-created group of cards — a manual folder over the
library, distinct from the auto-tags on a card and the global artifact catalog.
Membership is just a list of card ids; the cards themselves are unchanged, so
this needs no block-schema change.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from pydantic import BaseModel, Field


def _new_id() -> str:
    return "c_" + uuid.uuid4().hex[:8]


class Collection(BaseModel):
    """One named group of cards (membership by card id)."""

    id: str = Field(default_factory=_new_id)
    name: str
    card_ids: list[str] = Field(default_factory=list)
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
