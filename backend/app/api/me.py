"""The caller's own quota status — powers the profile meter."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.auth import OwnerDep
from app.config import get_settings
from app.quota import _resets_at
from app.store import db

from pydantic import BaseModel

router = APIRouter(prefix="/me", tags=["me"])


class LinkInstagramRequest(BaseModel):
    ig_username: str


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


@router.get("/instagram")
async def get_my_instagram(owner_id: OwnerDep) -> dict:
    """Fetch the Instagram handle currently linked to caller's account."""
    async with db.session() as s:
        link = await db.get_instagram_link_by_owner(s, owner_id=owner_id)
    return {"ig_username": link.ig_username if link else None}


@router.post("/instagram")
async def set_my_instagram(req: LinkInstagramRequest, owner_id: OwnerDep) -> dict:
    """Link an Instagram handle to caller's account."""
    username = req.ig_username.strip().lstrip("@")
    if not username:
        raise HTTPException(status_code=422, detail="ig_username is required")
    async with db.session() as s:
        link = await db.link_instagram_account(s, owner_id=owner_id, ig_username=username)
    return {"ig_username": link.ig_username}


@router.delete("/instagram")
async def delete_my_instagram(owner_id: OwnerDep) -> dict:
    """Unlink any Instagram handle linked to caller's account."""
    async with db.session() as s:
        unlinked = await db.unlink_instagram_account(s, owner_id=owner_id)
    return {"unlinked": unlinked}

