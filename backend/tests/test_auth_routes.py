"""Routes reject anonymous callers and scope rows to the verified uid."""

from app.auth import get_owner
from app.main import app


async def test_cards_requires_auth(client) -> None:
    """Anonymous caller is rejected (401 bad token / 503 auth unconfigured)."""
    del app.dependency_overrides[get_owner]
    resp = await client.get("/cards")
    assert resp.status_code in (401, 503)


async def test_owner_scoping(client) -> None:
    """uid-b never sees uid-a's cards."""
    app.dependency_overrides[get_owner] = lambda: "uid-a"
    created = await client.post("/cards", json={"url": "https://example.com/a"})
    assert created.status_code in (200, 201)
    mine = await client.get("/cards")
    assert mine.status_code == 200
    assert len(mine.json()) == 1

    app.dependency_overrides[get_owner] = lambda: "uid-b"
    theirs = await client.get("/cards")
    assert theirs.status_code == 200
    assert theirs.json() == []  # uid-b sees nothing of uid-a's
