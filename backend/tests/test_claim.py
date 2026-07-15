"""First-claim-wins migration of legacy name-keyed rows.

/auth/claim is off by default (M11 — it's a trust-on-first-use land grab); these
tests exercise its mechanics with the migration window explicitly opened.
"""

from app.auth import get_owner
from app.config import get_settings
from app.main import app
from app.store import db


async def _seed_legacy_card(name: str) -> None:
    async with db.session() as s:
        s.add(db.CardRow(owner_id=name, source_url=f"https://example.com/{name}", state="ready"))
        await s.commit()


async def test_claim_repoints_rows(client, monkeypatch) -> None:
    monkeypatch.setattr(get_settings(), "legacy_claim_enabled", True)
    await _seed_legacy_card("Vatsal")
    app.dependency_overrides[get_owner] = lambda: "uid-new"
    resp = await client.post("/auth/claim", json={"name": "Vatsal"})
    assert resp.status_code == 200 and resp.json()["claimed"] >= 1

    again = await client.post("/auth/claim", json={"name": "Vatsal"})
    assert again.status_code == 200  # same uid re-claiming is a no-op success

    app.dependency_overrides[get_owner] = lambda: "uid-thief"
    stolen = await client.post("/auth/claim", json={"name": "Vatsal"})
    assert stolen.status_code == 409

    # rows actually re-pointed
    from sqlalchemy import select

    async with db.session() as s:
        cards = (await s.execute(select(db.CardRow))).scalars().all()
    assert cards and all(c.owner_id == "uid-new" for c in cards)
