"""Quota accounting: daily counters, limits, per-owner/per-kind isolation."""

from app.store import db


async def test_spend_usage_counts_and_caps(database) -> None:
    async with db.session() as s:
        for i in range(3):
            allowed, used = await db.spend_usage(s, owner_id="u1", kind="chat", limit=3)
            assert allowed and used == i + 1
        allowed, used = await db.spend_usage(s, owner_id="u1", kind="chat", limit=3)
        assert not allowed and used == 3


async def test_usage_is_per_owner_and_per_kind(database) -> None:
    async with db.session() as s:
        await db.spend_usage(s, owner_id="u1", kind="chat", limit=3)
        allowed, used = await db.spend_usage(s, owner_id="u2", kind="chat", limit=3)
        assert allowed and used == 1
        allowed, used = await db.spend_usage(s, owner_id="u1", kind="cards", limit=3)
        assert allowed and used == 1
