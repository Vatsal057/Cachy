"""Temporary migration endpoint (delete ~1 month after auth ships)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.auth import OwnerDep, _verify
from app.store import db

router = APIRouter(prefix="/auth", tags=["auth"])


class ClaimRequest(BaseModel):
    name: str


class MergeRequest(BaseModel):
    guest_token: str


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


@router.post("/merge")
async def merge(req: MergeRequest, owner_id: OwnerDep) -> dict:
    """Fold a guest (anonymous) account's data into the caller's account.

    The caller's Bearer token is the destination. `guest_token` is the guest's
    own ID token, captured client-side just before it signed into an existing
    Google identity — it proves ownership of the source account. Source must be
    anonymous so this can't be used to siphon a real account's data."""
    token = req.guest_token.strip()
    if not token:
        raise HTTPException(status_code=422, detail="guest_token required")
    try:
        decoded = _verify(token)
    except Exception:
        raise HTTPException(status_code=401, detail="invalid guest token")
    if decoded.get("firebase", {}).get("sign_in_provider") != "anonymous":
        raise HTTPException(status_code=403, detail="source must be a guest account")
    from_uid = str(decoded["uid"])
    async with db.session() as s:
        moved = await db.merge_owner(s, from_uid=from_uid, to_uid=owner_id)
    return {"merged": moved}
