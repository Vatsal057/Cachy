"""Temporary migration endpoint (delete ~1 month after auth ships)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.auth import OwnerDep
from app.store import db

router = APIRouter(prefix="/auth", tags=["auth"])


class ClaimRequest(BaseModel):
    name: str


@router.post("/claim")
async def claim(req: ClaimRequest, owner_id: OwnerDep) -> dict:
    """Adopt legacy rows keyed by the pre-auth display name. First claim wins."""
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="name required")
    async with db.session() as s:
        claimed = await db.claim_owner(s, name=name, uid=owner_id)
    if claimed is None:
        raise HTTPException(status_code=409, detail="name already claimed")
    return {"claimed": claimed}
