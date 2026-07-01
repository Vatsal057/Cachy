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
    assert r.json()["schema_version"] == "1.5"


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

    # action_items (docs/13): follow toggle + per-item done round-trips via PATCH.
    actions = {
        "followed": True,
        "items": [{"id": "a1", "text": "Drink water", "done": True}],
    }
    pa = await client.patch(f"/cards/{card_id}", json={"action_items": actions})
    assert pa.status_code == 200
    body = pa.json()["action_items"]
    assert body["followed"] is True
    assert body["items"][0]["done"] is True
    # default card is unfollowed with an empty list
    fresh = await client.post(
        "/cards", json={"url": "https://instagram.com/reel/actions-default"}
    )
    fid = fresh.json()["card_id"]
    fa = (await client.get(f"/cards/{fid}")).json()["action_items"]
    assert fa == {"followed": False, "items": []}

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
            creator="James Clear", year=2018, thumbnail="http://x/a.jpg", saved=True,
        )
        await database.upsert_artifact(
            s, card_id="c2", type_="book", title="atomic   habits",
            creator=None, year=None, thumbnail=None, saved=True,
        )
        await database.upsert_artifact(
            s, card_id="c3", type_="movie", title="Inception",
            creator="Nolan", year=2010, thumbnail=None, saved=True,
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


# ---------------------------------------------------------------------------
# Persisted, owner-scoped AI conversations (docs/14)
# ---------------------------------------------------------------------------

async def test_chat_persists_and_restores_per_owner(client, database, monkeypatch):
    """A chat turn is saved for the owner that made it, restorable via GET, and
    invisible to a different owner."""
    card_id = await _make_ready_card(database)
    monkeypatch.setattr(
        "app.api.cards.llm_chat.answer", lambda card, history: "Use 1 cup."
    )

    post = await client.post(
        f"/cards/{card_id}/chat",
        headers={"x-owner-id": "alice"},
        json={"messages": [{"role": "user", "content": "how much flour?"}]},
    )
    assert post.status_code == 200

    # Alice restores the full turn (her question + the reply).
    restored = await client.get(
        f"/cards/{card_id}/chat", headers={"x-owner-id": "alice"}
    )
    msgs = restored.json()["messages"]
    assert [m["content"] for m in msgs] == ["how much flour?", "Use 1 cup."]

    # Bob sees nothing — isolation by owner.
    other = await client.get(
        f"/cards/{card_id}/chat", headers={"x-owner-id": "bob"}
    )
    assert other.json()["messages"] == []


async def test_rabbithole_persists_trail_and_restores(client, database, monkeypatch):
    """Successive dives build a persisted trail keyed by the root topic, and a
    branch taken after jumping back replaces the abandoned deeper steps."""
    card_id = await _make_ready_card(database)

    async def fake_explore(card, topic, trail):
        return {"explanation": f"About {topic}.", "threads": [f"{topic} deeper"]}

    monkeypatch.setattr(
        "app.api.cards.llm_rabbithole.explore_async", fake_explore
    )

    # Dive root → A (trail empty, root defaults to topic).
    r1 = await client.post(
        f"/cards/{card_id}/rabbithole",
        headers={"x-owner-id": "alice"},
        json={"topic": "roots", "trail": [], "root": "roots"},
    )
    assert r1.status_code == 200

    # Dive one deeper (trail carries the root).
    await client.post(
        f"/cards/{card_id}/rabbithole",
        headers={"x-owner-id": "alice"},
        json={"topic": "branch-a", "trail": ["roots"], "root": "roots"},
    )

    restored = await client.get(
        f"/cards/{card_id}/rabbithole",
        headers={"x-owner-id": "alice"},
        params={"root": "roots"},
    )
    steps = restored.json()["steps"]
    assert [s["topic"] for s in steps] == ["roots", "branch-a"]
    assert steps[0]["explanation"] == "About roots."

    # Jump back to depth 1 and branch differently → deeper tail is replaced.
    await client.post(
        f"/cards/{card_id}/rabbithole",
        headers={"x-owner-id": "alice"},
        json={"topic": "branch-b", "trail": ["roots"], "root": "roots"},
    )
    restored2 = await client.get(
        f"/cards/{card_id}/rabbithole",
        headers={"x-owner-id": "alice"},
        params={"root": "roots"},
    )
    assert [s["topic"] for s in restored2.json()["steps"]] == ["roots", "branch-b"]

    # A different owner has no trail for the same card + root.
    other = await client.get(
        f"/cards/{card_id}/rabbithole",
        headers={"x-owner-id": "bob"},
        params={"root": "roots"},
    )
    assert other.json()["steps"] == []


async def test_library_chat_persists_and_restores_per_owner(client, monkeypatch):
    async def fake_answer(history):
        return ("You saved 2 recipes.", [])

    monkeypatch.setattr(
        "app.api.library_chat.llm_library_chat.answer", fake_answer
    )

    await client.post(
        "/library/chat",
        headers={"x-owner-id": "alice"},
        json={"messages": [{"role": "user", "content": "what did I save?"}]},
    )

    restored = await client.get("/library/chat", headers={"x-owner-id": "alice"})
    assert [m["content"] for m in restored.json()["messages"]] == [
        "what did I save?",
        "You saved 2 recipes.",
    ]

    other = await client.get("/library/chat", headers={"x-owner-id": "bob"})
    assert other.json()["messages"] == []


async def test_catalog_detail_and_delete(client, database):
    async with database.session() as s:
        row = await database.upsert_artifact(
            s, card_id="c1", type_="podcast", title="Lex Fridman",
            creator=None, year=None, thumbnail=None, saved=True,
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


async def test_delete_card_cascades_cleanup(client, database):
    from sqlalchemy import select
    async with database.session() as s:
        c1 = database.CardRow(id="del-1", source_url="http://x/1", state="ready")
        c2 = database.CardRow(id="del-2", source_url="http://x/2", state="ready")
        s.add_all([c1, c2])
        await s.commit()

        col = await database.create_custom_collection(s, name="My Folder", owner_id=None)
        await database.move_card_to_collection(s, "del-1", col.id)

        await database.upsert_concept(s, name="Idea Solo", card_id="del-1")
        await database.upsert_concept(s, name="Idea Shared", card_id="del-1")
        await database.upsert_concept(s, name="Idea Shared", card_id="del-2")

        await database.upsert_artifact(s, card_id="del-1", type_="book", title="Book Solo", creator=None, year=None, thumbnail=None, saved=True)
        await database.upsert_artifact(s, card_id="del-1", type_="book", title="Book Shared", creator=None, year=None, thumbnail=None, saved=True)
        await database.upsert_artifact(s, card_id="del-2", type_="book", title="Book Shared", creator=None, year=None, thumbnail=None, saved=True)

    res = await client.delete("/cards/del-1")
    assert res.status_code == 200

    async with database.session() as s:
        col_row = await s.get(database.CollectionRow, col.id)
        assert col_row is None

        solo_c = (await s.execute(select(database.ConceptRow).where(database.ConceptRow.name == "Idea Solo"))).scalar_one_or_none()
        assert solo_c is None

        shared_c = (await s.execute(select(database.ConceptRow).where(database.ConceptRow.name == "Idea Shared"))).scalar_one()
        assert shared_c.source_card_ids == ["del-2"]

        solo_a = (await s.execute(select(database.ArtifactRow).where(database.ArtifactRow.title == "Book Solo"))).scalar_one_or_none()
        assert solo_a is None

        shared_a = (await s.execute(select(database.ArtifactRow).where(database.ArtifactRow.title == "Book Shared"))).scalar_one()
        assert shared_a.source_card_ids == ["del-2"]


@pytest.mark.asyncio
async def test_concepts_filtering_multi_reel(client):
    from app.store import db as database
    async with database.session() as s:
        c1 = database.CardRow(id="f-1", source_url="http://f/1", state="ready")
        c2 = database.CardRow(id="f-2", source_url="http://f/2", state="ready")
        s.add_all([c1, c2])
        await s.commit()

        await database.upsert_concept(s, name="Single Reel Concept", card_id="f-1")
        await database.upsert_concept(s, name="Multi Reel Concept", card_id="f-1")
        await database.upsert_concept(s, name="Multi Reel Concept", card_id="f-2")

    res = await client.get("/concepts")
    assert res.status_code == 200
    data = res.json()
    names = [item["name"] for item in data]
    assert "Multi Reel Concept" in names
    assert "Single Reel Concept" not in names

    res_card = await client.get("/concepts?card_id=f-1")
    assert res_card.status_code == 200
    card_names = [item["name"] for item in res_card.json()]
    assert "Single Reel Concept" in card_names
    assert "Multi Reel Concept" in card_names


@pytest.mark.asyncio
async def test_similar_concept_merging(client):
    from app.store import db as database
    async with database.session() as s:
        c1 = database.CardRow(id="sim-1", source_url="http://sim/1", state="ready")
        c2 = database.CardRow(id="sim-2", source_url="http://sim/2", state="ready")
        s.add_all([c1, c2])
        await s.commit()

        row1 = await database.upsert_concept(s, name="Spaced Repetition", card_id="sim-1")
        row2 = await database.upsert_concept(s, name="Spaced Repetition System", card_id="sim-2")
        assert row1.id == row2.id
        assert set(row2.source_card_ids) == {"sim-1", "sim-2"}

