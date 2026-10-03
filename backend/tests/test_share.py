"""Public card sharing: link lifecycle, public page/JSON, save-a-copy."""

import pytest

from app.auth import get_optional_owner, get_owner
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
    if uid is None:
        app.dependency_overrides.pop(get_owner, None)
        app.dependency_overrides.pop(get_optional_owner, None)
    else:
        app.dependency_overrides[get_owner] = lambda: uid
        app.dependency_overrides[get_optional_owner] = lambda: uid


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
    _as(None)  # unauthenticated / public caller
    resp = await client.get(f"/share/{token}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["one_liner"] == "Test card one-liner"
    assert data["blocks"][0]["text"] == "Hello <world>"  # raw in JSON is fine
    assert "owner_id" not in data
    assert "raw_bundle" not in data
    assert data["is_owner"] is False
    assert "card_id" not in data
    assert (await client.get("/share/nope")).status_code == 404

    # Now verify owner calling GET /share/{token} gets is_owner=True and card_id
    _as("uid-a")
    owner_resp = await client.get(f"/share/{token}")
    assert owner_resp.status_code == 200
    owner_data = owner_resp.json()
    assert owner_data["is_owner"] is True
    assert owner_data["card_id"] == card_id


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


async def test_save_own_card_returns_existing(client, database) -> None:
    _as("uid-a")
    card_id = await _ready_card(database)
    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]
    resp = await client.post(f"/share/{token}/save")
    assert resp.status_code == 200
    assert resp.json() == {"card_id": card_id, "already_saved": True, "is_owner": True}


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


async def test_share_page_and_save_with_rich_sections(client, database) -> None:
    _as("uid-a")
    async with database.session() as s:
        card = db.CardRow(
            owner_id="uid-a",
            source_url="https://example.com/reel-rich",
            state=CardState.READY.value,
            one_liner="Rich card with all sections",
            tldr="Core takeaway summary",
            blocks=[
                {"type": "heading", "text": "Faking Personality", "level": 2},
                {"type": "paragraph", "text": "Adapt gracefully in conversations."},
                {
                    "type": "step_list",
                    "steps": [
                        {"text": "Step one"},
                        {"text": "Step two"},
                        {"text": "Step three"},
                    ],
                },
            ],
            action_items={
                "followed": False,
                "items": [
                    {"id": "a1", "text": "Do small talk", "done": False},
                ],
            },
            insight={
                "rabbit_hole": {
                    "questions": ["How does social dynamics work?"],
                    "adjacent_topics": ["Sociology"],
                },
                "quiz": {
                    "questions": [
                        {
                            "question": "What to do?",
                            "options": ["A", "B"],
                            "answer_index": 0,
                        }
                    ]
                },
            },
            tags=["psychology", "career"],
            platform="instagram",
            creator="vatxzz",
        )
        s.add(card)
        await s.commit()
        await s.refresh(card)
        card_id = card.id

        art = db.ArtifactRow(
            type="movie",
            title="Pelé",
            title_norm="pele",
            source_card_ids=[card_id],
        )
        conc = db.ConceptRow(
            name="Impression Management",
            name_norm="impression management",
            source_card_ids=[card_id],
        )
        s.add_all([art, conc])
        await s.commit()

    token = (await client.post(f"/cards/{card_id}/share")).json()["token"]

    # Verify JSON payload has all rich structures
    resp = await client.get(f"/share/{token}")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["artifacts"]) == 1
    assert data["artifacts"][0]["title"] == "Pelé"
    assert len(data["concepts"]) == 1
    assert data["concepts"][0]["name"] == "Impression Management"
    assert len(data["action_items"]["items"]) == 1
    assert data["read_minutes"] >= 1

    # Verify HTML page renders the sections
    page = await client.get(f"/s/{token}")
    assert page.status_code == 200
    html_text = page.text
    assert "section-card" in html_text
    assert "ACTIONS" in html_text
    assert "Do small talk" in html_text
    assert "Track in Actions" in html_text
    assert "GOING DEEPER" in html_text
    assert "step-strip" in html_text
    assert "REFERENCES" in html_text
    assert "Pelé" in html_text
    assert "CONCEPTS" in html_text
    assert "Impression Management" in html_text
    assert "Fraunces" in html_text
    assert "data-theme" in html_text

    # Verify Save clones the card and links artifacts & concepts
    _as("uid-b")
    save_resp = await client.post(f"/share/{token}/save")
    assert save_resp.status_code == 200
    new_id = save_resp.json()["card_id"]
    assert new_id != card_id

    async with database.session() as s:
        cloned_card = await db.get_card_row(s, new_id, owner_id="uid-b")
        assert cloned_card is not None
        assert cloned_card.action_items["items"][0]["text"] == "Do small talk"
        assert cloned_card.action_items["items"][0]["done"] is False

        art_row = (await s.execute(db.select(db.ArtifactRow).where(db.ArtifactRow.title == "Pelé"))).scalar_one()
        assert new_id in art_row.source_card_ids
        assert card_id in art_row.source_card_ids

        conc_row = (await s.execute(db.select(db.ConceptRow).where(db.ConceptRow.name == "Impression Management"))).scalar_one()
        assert new_id in conc_row.source_card_ids
        assert card_id in conc_row.source_card_ids

