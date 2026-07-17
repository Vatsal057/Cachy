"""Regression: duplicate system collections must not break get_or_create_collection.

Two workers against one shared database (HF Space + local dev on the same Neon
URL) could both miss the SELECT and both INSERT, leaving two system collections
for the same owner+type. scalar_one_or_none() then raised MultipleResultsFound
on every later call, killing every job of that content type for that owner.
"""

from datetime import datetime, timedelta, timezone

from app.store import db


async def _collection(
    database, cid: str, owner: str, system_type: str, created: datetime
) -> None:
    async with database.session() as s:
        s.add(
            database.CollectionRow(
                id=cid,
                name=system_type.capitalize(),
                system_type=system_type,
                is_custom=False,
                owner_id=owner,
                created_at=created,
            )
        )
        await s.commit()


async def test_duplicate_system_collections_resolve_to_oldest(database):
    """The canonical row is the oldest — it's the one holding the cards."""
    old = datetime(2026, 6, 29, tzinfo=timezone.utc)
    new = old + timedelta(days=12)
    await _collection(database, "col-old", "alice", "tip", old)
    await _collection(database, "col-new", "alice", "tip", new)

    async with database.session() as s:
        row = await db.get_or_create_collection(s, owner_id="alice", system_type="tip")

    assert row.id == "col-old"


async def test_creates_when_absent(database):
    async with database.session() as s:
        row = await db.get_or_create_collection(s, owner_id="alice", system_type="tip")
    assert row.system_type == "tip"
    assert row.owner_id == "alice"
    assert row.is_custom is False


async def test_reuses_existing_single_collection(database):
    created = datetime(2026, 6, 29, tzinfo=timezone.utc)
    await _collection(database, "col-1", "alice", "tip", created)

    async with database.session() as s:
        row = await db.get_or_create_collection(s, owner_id="alice", system_type="tip")

    assert row.id == "col-1"


async def test_does_not_cross_owners(database):
    created = datetime(2026, 6, 29, tzinfo=timezone.utc)
    await _collection(database, "col-alice", "alice", "tip", created)

    async with database.session() as s:
        row = await db.get_or_create_collection(s, owner_id="bob", system_type="tip")

    assert row.id != "col-alice"
    assert row.owner_id == "bob"


async def test_ignores_custom_collections(database):
    """A user's custom collection must never be returned as the system one."""
    async with database.session() as s:
        s.add(
            database.CollectionRow(
                id="col-custom",
                name="My tips",
                system_type="tip",
                is_custom=True,
                owner_id="alice",
                created_at=datetime(2026, 6, 1, tzinfo=timezone.utc),
            )
        )
        await s.commit()

    async with database.session() as s:
        row = await db.get_or_create_collection(s, owner_id="alice", system_type="tip")

    assert row.id != "col-custom"
    assert row.is_custom is False
