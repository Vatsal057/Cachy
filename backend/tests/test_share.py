"""Public card sharing: link lifecycle, public page/JSON, save-a-copy."""

import pytest

from app.auth import get_owner
from app.main import app
from app.models.card import CardState
from app.store import db


async def _ready_card(database, owner="uid-a", url="https://example.com/reel1"):
    async with database.session() as s:
        row = db.CardRow(
            owner_id=owner,
            source_url=url,
            state=CardState.READY.value,
            one_liner="Test card one-liner",
            tldr="The takeaway",
            blocks=[{"id": "b1", "type": "paragraph", "text": "Hello <world>"}],
            tags=["test"],
            platform="instagram",
            creator="someone",
        )
        s.add(row)
        await s.commit()
        await s.refresh(row)
        return row.id


def _as(uid):
    app.dependency_overrides[get_owner] = lambda: uid


async def test_share_create_idempotent(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    r1 = await client.post(f"/cards/{card_id}/share")
    assert r1.status_code == 200, r1.text
    assert "/s/" in r1.json()["url"]
    r2 = await client.post(f"/cards/{card_id}/share")
    assert r2.json()["token"] == r1.json()["token"]
    got = await client.get(f"/cards/{card_id}/share")
    assert got.json()["token"] == r1.json()["token"]


async def test_share_requires_ready(client, database) -> None:
    _as("uid-a")
    async with database.session() as s:
        row = db.CardRow(
            owner_id="uid-a",
            source_url="https://example.com/queued",
            state=CardState.QUEUED.value,
        )
        s.add(row)
        await s.commit()
        await s.refresh(row)
        qid = row.id
    resp = await client.post(f"/cards/{qid}/share")
    assert resp.status_code == 409


async def test_share_other_owners_card_404(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database, owner="uid-a")
    _as("uid-b")
    assert (await client.post(f"/cards/{card_id}/share")).status_code == 404
    assert (await client.get(f"/cards/{card_id}/share")).status_code == 404


async def test_public_page_renders_and_escapes(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    page = await client.get(f"/s/{token}")
    assert page.status_code == 200
    assert "text/html" in page.headers["content-type"]
    body = page.text
    assert "Test card one-liner" in body
    assert "Hello &lt;world&gt;" in body  # escaped, not raw HTML
    assert "og:title" in body
    assert "noindex" in body
    assert "cachy://s/" in body  # save deep link
    assert (await client.get("/s/badtoken")).status_code == 404


async def test_share_json_is_safe_subset(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    resp = await client.get(f"/share/{token}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["one_liner"] == "Test card one-liner"
    assert data["blocks"][0]["text"] == "Hello <world>"  # raw in JSON is fine
    assert "owner_id" not in data
    assert "raw_bundle" not in data
    assert (await client.get("/share/nope")).status_code == 404


async def test_save_copy_flow(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    _as("uid-b")
    saved = await client.post(f"/share/{token}/save")
    assert saved.status_code == 200, saved.text
    new_id = saved.json()["card_id"]
    assert new_id != card_id
    assert saved.json()["already_saved"] is False
    async with database.session() as s:
        copy = await db.get_card_row(s, new_id, owner_id="uid-b")
        assert copy is not None
        assert copy.one_liner == "Test card one-liner"
        assert copy.state == CardState.READY.value
        assert copy.blocks[0]["text"] == "Hello <world>"
        assert copy.owner_id == "uid-b"
        # original untouched
        orig = await db.get_card_row(s, card_id, owner_id="uid-a")
        assert orig is not None
    # saving again dedupes to the first copy
    again = await client.post(f"/share/{token}/save")
    assert again.json() == {"card_id": new_id, "already_saved": True}


async def test_save_own_card_409(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    resp = await client.post(f"/share/{token}/save")
    assert resp.status_code == 409


async def test_save_bad_token_404(client, database) -> None:
    _as("uid-b")
    assert (await client.post("/share/nope/save")).status_code == 404


async def test_revoke_kills_link(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    assert (await client.delete(f"/cards/{card_id}/share")).status_code == 200
    assert (await client.get(f"/s/{token}")).status_code == 404
    assert (await client.get(f"/share/{token}")).status_code == 404
    # re-sharing after revoke mints a fresh token
    token2 = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    assert token2 != token
    assert (await client.get(f"/s/{token2}")).status_code == 200


async def test_delete_card_kills_link(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    assert (await client.delete(f"/cards/{card_id}")).status_code == 200
    assert (await client.get(f"/s/{token}")).status_code == 404


async def test_assetlinks_empty_by_default(client) -> None:
    resp = await client.get("/.well-known/assetlinks.json")
    assert resp.status_code == 200
    assert resp.json() == []
