"""Knowledge Feed + Connections (serendipity). Feed moments are built from stored
card data (no LLM); connection generation is exercised with a stubbed explainer so
the suite stays offline."""

from __future__ import annotations

import httpx
import pytest
from httpx import ASGITransport

from app.main import app


async def _ready_card(
    database,
    *,
    owner,
    one_liner,
    tldr="",
    blocks=None,
    insight=None,
    embedding=None,
    content_type="tip",
) -> str:
    async with database.session() as s:
        row = database.CardRow(
            source_url=f"https://x/{one_liner}",
            state="ready",
            content_type=content_type,
            one_liner=one_liner,
            tldr=tldr,
            blocks=blocks or [],
            insight=insight,
            embedding=embedding,
            owner_id=owner,
        )
        s.add(row)
        await s.commit()
        return row.id


# --------------------------------------------------------------------------- #
# Feed
# --------------------------------------------------------------------------- #

async def test_feed_builds_all_moment_kinds_from_a_card(client, database):
    await _ready_card(
        database,
        owner="alice",
        one_liner="Compound interest snowballs",
        tldr="Money earns money over time.",
        blocks=[{"type": "bullet_list", "id": "b1", "items": ["Start early to win big"]}],
        insight={
            "rabbit_hole": {"questions": ["Why does starting early matter so much?"]},
            "quiz": [
                {
                    "question": "What makes compound interest powerful?",
                    "options": ["Time", "Luck"],
                    "answer_index": 0,
                    "explanation": "Interest compounds over time.",
                }
            ],
        },
    )

    r = await client.get("/feed", headers={"x-owner-id": "alice"})
    assert r.status_code == 200
    items = r.json()["items"]
    kinds = {it["kind"] for it in items}
    assert {"insight", "highlight", "quiz", "thread"} <= kinds
    # Every non-connection moment points at the owner's card.
    assert all(it["card"]["title"] for it in items)
    quiz = next(it for it in items if it["kind"] == "quiz")
    assert quiz["options"] == ["Time", "Luck"]
    assert quiz["answer_index"] == 0


async def test_feed_is_owner_scoped(client, database):
    await _ready_card(database, owner="alice", one_liner="Alice card", tldr="hers")
    r = await client.get("/feed", headers={"x-owner-id": "bob"})
    assert r.status_code == 200
    assert r.json()["items"] == []


async def test_feed_respects_limit(client, database):
    for i in range(6):
        await _ready_card(
            database, owner="alice", one_liner=f"Card {i}", tldr=f"Summary {i}"
        )
    r = await client.get("/feed", headers={"x-owner-id": "alice"}, params={"limit": 3})
    assert len(r.json()["items"]) == 3


# --------------------------------------------------------------------------- #
# Connections (serendipity)
# --------------------------------------------------------------------------- #

async def test_connections_generate_cache_and_isolate(client, database, monkeypatch):
    # Two mid-similar cards of DIFFERENT types → one surprising pair.
    await _ready_card(
        database, owner="alice", one_liner="Ramen broth depth",
        tldr="Slow simmering builds umami.", content_type="recipe",
        embedding=[1.0, 0.0],
    )
    await _ready_card(
        database, owner="alice", one_liner="Startup compounding",
        tldr="Small daily gains stack up.", content_type="tip",
        embedding=[0.5, 0.87],  # cosine ~0.5 with the first → in the surprise band
    )

    calls = {"n": 0}

    def fake_explain(a, b):
        calls["n"] += 1
        return "Both reward patience: slow inputs compound into something rich."

    monkeypatch.setattr("app.services.serendipity._explain", fake_explain)

    first = await client.get(
        "/connections", headers={"x-owner-id": "alice"}, params={"refresh": True}
    )
    assert first.status_code == 200
    conns = first.json()["connections"]
    assert len(conns) == 1
    assert "patience" in conns[0]["blurb"]
    assert {conns[0]["card_a"]["content_type"], conns[0]["card_b"]["content_type"]} == {
        "recipe",
        "tip",
    }
    assert calls["n"] == 1

    # Second call reuses the cached link — no new LLM call.
    second = await client.get("/connections", headers={"x-owner-id": "alice"})
    assert len(second.json()["connections"]) == 1
    assert calls["n"] == 1

    # A different owner sees nothing.
    other = await client.get("/connections", headers={"x-owner-id": "bob"})
    assert other.json()["connections"] == []


async def test_connections_empty_with_single_card(client, database):
    # Unique owner → exactly one card, so no pair can exist.
    await _ready_card(database, owner="hermit", one_liner="Lonely card", tldr="solo")
    r = await client.get(
        "/connections", headers={"x-owner-id": "hermit"}, params={"refresh": True}
    )
    assert r.json()["connections"] == []
