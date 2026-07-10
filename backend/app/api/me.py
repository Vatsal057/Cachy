"""The caller's own quota status — powers the profile meter."""

from __future__ import annotations

from fastapi import APIRouter

from app.auth import OwnerDep
from app.config import get_settings
from app.quota import _resets_at
from app.store import db

router = APIRouter(prefix="/me", tags=["me"])


@router.get("/quota")
async def my_quota(owner_id: OwnerDep) -> dict:
    """Today's used/limit per metered kind."""
    settings = get_settings()
    day = db._today()
    out: dict = {"resets_at": _resets_at()}
    async with db.session() as s:
        for kind, limit in (
            ("cards", settings.quota_cards_per_day),
            ("chat", settings.quota_chat_per_day),
        ):
            row = await s.get(db.UsageRow, (owner_id, day, kind))
            out[kind] = {"used": row.count if row else 0, "limit": limit}
    return out
