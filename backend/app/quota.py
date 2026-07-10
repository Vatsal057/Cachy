"""Per-user daily quotas. Chat-style routes raise 429; card creation degrades
instead (see cards.py) so a save never hard-fails."""

from __future__ import annotations

from datetime import datetime, time, timedelta, timezone

from fastapi import Depends, HTTPException, Request

from app.auth import get_owner
from app.config import get_settings
from app.store import db


def _resets_at() -> str:
    """ISO timestamp of the next UTC midnight (quota reset)."""
    now = datetime.now(timezone.utc)
    tomorrow = datetime.combine(now.date() + timedelta(days=1), time.min, tzinfo=timezone.utc)
    return tomorrow.isoformat()


def spend(kind: str, limit_attr: str):
    """Dependency factory: spend one unit of `kind` or raise 429."""

    async def _dep(owner_id: str = Depends(get_owner)) -> str:
        limit = getattr(get_settings(), limit_attr)
        async with db.session() as s:
            allowed, used = await db.spend_usage(
                s, owner_id=owner_id, kind=kind, limit=limit
            )
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail={
                    "error": "quota", "kind": kind,
                    "used": used, "limit": limit, "resets_at": _resets_at(),
                },
            )
        return owner_id

    return _dep


async def card_budget(owner_id: str, request: Request) -> bool:
    """Card-creation budget. Enforces the per-IP cap (429) and returns whether
    the owner still has AI budget today (False -> degrade, never fail)."""
    settings = get_settings()
    ip = request.client.host if request.client else "unknown"
    async with db.session() as s:
        ip_ok, _ = await db.spend_usage(
            s, owner_id=f"ip:{ip}", kind="cards", limit=settings.quota_ip_cards_per_day
        )
        if not ip_ok:
            raise HTTPException(status_code=429, detail={
                "error": "quota", "kind": "ip", "limit": settings.quota_ip_cards_per_day,
                "used": settings.quota_ip_cards_per_day, "resets_at": _resets_at(),
            })
        allowed, _ = await db.spend_usage(
            s, owner_id=owner_id, kind="cards", limit=settings.quota_cards_per_day
        )
    return allowed
