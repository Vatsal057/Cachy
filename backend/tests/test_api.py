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
    assert r.json()["schema_version"] == "1.2"


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


async def test_catalog_empty_initially(client):
    r = await client.get("/catalog")
    assert r.status_code == 200
    assert r.json() == []


async def test_catalog_upsert_dedupes_and_lists(client, database):
    async with database.session() as s:
        await database.upsert_artifact(
            s, card_id="c1", type_="book", title="Atomic Habits",
            creator="James Clear", year=2018, thumbnail="http://x/a.jpg",
        )
        await database.upsert_artifact(
            s, card_id="c2", type_="book", title="atomic   habits",
            creator=None, year=None, thumbnail=None,
        )
        await database.upsert_artifact(
            s, card_id="c3", type_="movie", title="Inception",
            creator="Nolan", year=2010, thumbnail=None,
        )

    r = await client.get("/catalog")
    entries = r.json()
    assert len(entries) == 2  # the two books deduped into one
    book = next(e for e in entries if e["type"] == "book")
    assert sorted(book["source_card_ids"]) == ["c1", "c2"]
    assert book["thumbnail"] == "http://x/a.jpg"  # backfilled-keep

    # type filter
    r2 = await client.get("/catalog", params={"type": "movie"})
    assert [e["title"] for e in r2.json()] == ["Inception"]


async def _make_ready_card(database) -> str:
    async with database.session() as s:
        row = database.CardRow(
            source_url="https://instagram.com/reel/chat",
            state="ready",
            content_type="recipe",
            one_liner="Easy pancakes",
            tldr="Mix, pour, flip.",
            blocks=[
                {"type": "checklist", "id": "b1",
                 "items": [{"text": "flour", "checked": False}]},
            ],
        )
        s.add(row)
        await s.commit()
        return row.id


async def test_chat_rejects_non_user_last_message(client):
    r = await client.post(
        "/cards/whatever/chat",
        json={"messages": [{"role": "assistant", "content": "hi"}]},
    )
    assert r.status_code == 422


async def test_chat_409_when_card_not_ready(client):
    created = await client.post("/cards", json={"url": "https://instagram.com/reel/q"})
    card_id = created.json()["card_id"]  # stays QUEUED (no worker in tests)
    r = await client.post(
        f"/cards/{card_id}/chat",
        json={"messages": [{"role": "user", "content": "what is this?"}]},
    )
    assert r.status_code == 409


async def test_chat_503_without_llm_backend(client, database):
    card_id = await _make_ready_card(database)
    r = await client.post(
        f"/cards/{card_id}/chat",
        json={"messages": [{"role": "user", "content": "how much flour?"}]},
    )
    assert r.status_code == 503  # LLM_BACKEND=none in the test env


async def test_chat_returns_reply_when_backend_answers(client, database, monkeypatch):
    card_id = await _make_ready_card(database)

    captured = {}

    def fake_answer(card, history):
        captured["title"] = card.base.one_liner
        captured["history"] = history
        return "You need flour."

    monkeypatch.setattr("app.api.cards.llm_chat.answer", fake_answer)

    r = await client.post(
        f"/cards/{card_id}/chat",
        json={"messages": [{"role": "user", "content": "ingredients?"}]},
    )
    assert r.status_code == 200
    assert r.json()["reply"] == "You need flour."
    assert captured["title"] == "Easy pancakes"
    assert captured["history"][-1]["content"] == "ingredients?"


async def test_catalog_detail_and_delete(client, database):
    async with database.session() as s:
        row = await database.upsert_artifact(
            s, card_id="c1", type_="podcast", title="Lex Fridman",
            creator=None, year=None, thumbnail=None,
        )
        artifact_id = row.id

    g = await client.get(f"/catalog/{artifact_id}")
    assert g.status_code == 200
    assert g.json()["entry"]["title"] == "Lex Fridman"
    assert g.json()["source_card_ids"] == ["c1"]

    d = await client.delete(f"/catalog/{artifact_id}")
    assert d.status_code == 200
    assert (await client.get(f"/catalog/{artifact_id}")).status_code == 404


# ---------------------------------------------------------------------------
# Collections CRUD
# ---------------------------------------------------------------------------

async def test_collections_create_and_list(client):
    r = await client.post("/collections", json={"name": "My reads"})
    assert r.status_code == 200
    col = r.json()
    assert col["name"] == "My reads"
    assert col["card_ids"] == []

    lst = await client.get("/collections")
    assert any(c["id"] == col["id"] for c in lst.json())


async def test_collections_create_blank_name_422(client):
    r = await client.post("/collections", json={"name": "   "})
    assert r.status_code == 422


async def test_collections_add_remove_card(client):
    col_r = await client.post("/collections", json={"name": "Cooking"})
    col_id = col_r.json()["id"]

    card_r = await client.post("/cards", json={"url": "https://instagram.com/reel/coll1"})
    card_id = card_r.json()["card_id"]

    # add
    add = await client.post(f"/collections/{col_id}/cards", json={"card_id": card_id})
    assert add.status_code == 200
    assert card_id in add.json()["card_ids"]

    # idempotent second add
    add2 = await client.post(f"/collections/{col_id}/cards", json={"card_id": card_id})
    assert add2.json()["card_ids"].count(card_id) == 1

    # detail resolves cards
    detail = await client.get(f"/collections/{col_id}")
    assert detail.status_code == 200
    assert any(c["card_id"] == card_id for c in detail.json()["cards"])

    # remove
    rm = await client.delete(f"/collections/{col_id}/cards/{card_id}")
    assert rm.status_code == 200
    assert card_id not in rm.json()["card_ids"]


async def test_collections_delete(client):
    r = await client.post("/collections", json={"name": "Temp"})
    col_id = r.json()["id"]
    d = await client.delete(f"/collections/{col_id}")
    assert d.status_code == 200
    assert (await client.get(f"/collections/{col_id}")).status_code == 404


async def test_collections_missing_404(client):
    assert (await client.get("/collections/no-such-id")).status_code == 404


# ---------------------------------------------------------------------------
# /catalog?card_id= filter
# ---------------------------------------------------------------------------

async def test_catalog_filter_by_card_id(client, database):
    async with database.session() as s:
        await database.upsert_artifact(
            s, card_id="card-a", type_="book", title="Deep Work",
            creator=None, year=None, thumbnail=None,
        )
        await database.upsert_artifact(
            s, card_id="card-b", type_="movie", title="Interstellar",
            creator=None, year=None, thumbnail=None,
        )

    r = await client.get("/catalog", params={"card_id": "card-a"})
    titles = [e["title"] for e in r.json()]
    assert "Deep Work" in titles
    assert "Interstellar" not in titles

    r2 = await client.get("/catalog", params={"card_id": "card-b"})
    assert [e["title"] for e in r2.json()] == ["Interstellar"]

    # unknown card id returns empty
    r3 = await client.get("/catalog", params={"card_id": "unknown"})
    assert r3.json() == []


# ---------------------------------------------------------------------------
# /library/chat
# ---------------------------------------------------------------------------

async def test_library_chat_422_non_user_last(client):
    r = await client.post(
        "/library/chat",
        json={"messages": [{"role": "assistant", "content": "hello"}]},
    )
    assert r.status_code == 422


async def test_library_chat_422_empty_messages(client):
    r = await client.post("/library/chat", json={"messages": []})
    assert r.status_code == 422


async def test_library_chat_503_without_llm_backend(client):
    # LLM_BACKEND=none in conftest → answer() returns None → 503
    r = await client.post(
        "/library/chat",
        json={"messages": [{"role": "user", "content": "what have I saved?"}]},
    )
    assert r.status_code == 503


async def test_library_chat_returns_reply(client, monkeypatch):
    async def fake_answer(history):
        return ("You saved 3 recipes.", [])

    monkeypatch.setattr("app.api.library_chat.llm_library_chat.answer", fake_answer)

    r = await client.post(
        "/library/chat",
        json={"messages": [{"role": "user", "content": "what recipes?"}]},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["reply"] == "You saved 3 recipes."
    assert body["sources"] == []


# ---------------------------------------------------------------------------
# /search semantic fallback (no HF key in tests → falls back to full-text)
# ---------------------------------------------------------------------------

async def test_search_mode_auto_falls_back_gracefully(client):
    # Create a card with known one_liner so full-text can find it.
    await client.post("/cards", json={"url": "https://instagram.com/reel/srch1"})
    # mode=auto with no HF key should not crash; it returns a list (possibly empty).
    r = await client.get("/search", params={"q": "something", "mode": "auto"})
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_search_mode_semantic_falls_back_gracefully(client):
    r = await client.get("/search", params={"q": "workout tips", "mode": "semantic"})
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_search_mode_text_works(client):
    r = await client.get("/search", params={"q": "anything", "mode": "text"})
    assert r.status_code == 200
    assert isinstance(r.json(), list)
