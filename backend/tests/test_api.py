"""API surface (docs/05). The worker is NOT started here (no lifespan), so cards
stay QUEUED — we assert the HTTP contract, dedup, and CRUD, not pipeline output."""

import httpx
import pytest
from httpx import ASGITransport

from app.main import app


@pytest.fixture
async def client(database):
    transport = ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json()["schema_version"] == "1.0"


async def test_create_returns_id_and_queued(client):
    r = await client.post("/cards", json={"url": "https://instagram.com/reel/aaa"})
    assert r.status_code == 200
    body = r.json()
    assert body["card_id"]
    assert body["state"] == "queued"
    assert body["cached"] is False


async def test_dedup_returns_same_card(client):
    url = "https://instagram.com/reel/dup"
    r1 = await client.post("/cards", json={"url": url})
    r2 = await client.post("/cards", json={"url": url})
    assert r1.json()["card_id"] == r2.json()["card_id"]
    assert r2.json()["cached"] is True


async def test_get_list_patch_delete(client):
    r = await client.post("/cards", json={"url": "https://instagram.com/reel/crud"})
    card_id = r.json()["card_id"]

    g = await client.get(f"/cards/{card_id}")
    assert g.status_code == 200
    assert g.json()["card_id"] == card_id

    lst = await client.get("/cards")
    assert any(c["card_id"] == card_id for c in lst.json())

    blocks = [{"type": "checklist", "id": "b1",
               "items": [{"text": "milk", "checked": True}]}]
    p = await client.patch(f"/cards/{card_id}", json={"blocks": blocks})
    assert p.status_code == 200
    assert p.json()["blocks"][0]["items"][0]["checked"] is True

    d = await client.delete(f"/cards/{card_id}")
    assert d.status_code == 200
    assert (await client.get(f"/cards/{card_id}")).status_code == 404


async def test_get_missing_card_404(client):
    r = await client.get("/cards/does-not-exist")
    assert r.status_code == 404
