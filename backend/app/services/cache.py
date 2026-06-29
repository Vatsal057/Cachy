"""Duplicate detection: re-sharing the same reel returns the existing card instead
of re-running the cascade (docs/02, docs/09)."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.store.db import CardRow, find_card_by_url


async def existing_card_for_url(
    db: AsyncSession, url: str, owner_id: str | None = None
) -> CardRow | None:
    return await find_card_by_url(db, url, owner_id=owner_id)
