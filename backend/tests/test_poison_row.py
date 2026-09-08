"""Regression: one unserializable stored card must not break the whole library.

`CardRow.to_card()` feeds raw stored JSON into strict Pydantic models (notably
`blocks`, a discriminated union over a fixed type vocabulary). A single row whose
stored data no longer matches the current schema used to raise ValidationError
inside the `list_cards` comprehension, turning GET /cards into a 500 and hiding
every other card the owner has.
"""
from __future__ import annotations

import pytest

from app.store import db


async def _insert(session, **overrides):
    row = db.CardRow(
        source_url=overrides.pop("source_url", "https://example.com/x"),
        owner_id=overrides.pop("owner_id", "test-user"),
        state=overrides.pop("state", "ready"),
        one_liner=overrides.pop("one_liner", "fine"),
        blocks=overrides.pop("blocks", [{"type": "paragraph", "id": "b_1", "text": "ok"}]),
        **overrides,
    )
    session.add(row)
    return row


@pytest.mark.anyio
async def test_unknown_block_type_does_not_break_listing(client, database):
    """A block type outside the schema vocabulary must not 500 the listing."""
    async with database.session() as s:
        await _insert(s, one_liner="good-one")
        # Poison row: `mind_map` is not in the Block union's discriminator vocab.
        await _insert(
            s,
            one_liner="poison-unknown-type",
            blocks=[{"type": "mind_map", "id": "b_2", "nodes": ["a", "b"]}],
        )
        await _insert(s, one_liner="good-two")
        await s.commit()

    resp = await client.get("/cards", params={"limit": 100, "offset": 0})
    assert resp.status_code == 200, resp.text
    liners = {c["base"]["one_liner"] for c in resp.json()}
    assert {"good-one", "good-two"} <= liners


@pytest.mark.anyio
async def test_block_missing_required_field_does_not_break_listing(client, database):
    """A known block type missing a required field must be dropped, not fatal."""
    async with database.session() as s:
        await _insert(s, one_liner="good-one")
        await _insert(
            s,
            one_liner="poison-missing-field",
            blocks=[
                {"type": "heading", "id": "b_3"},  # `text` is required
                {"type": "paragraph", "id": "b_4", "text": "survives"},
            ],
        )
        await s.commit()

    resp = await client.get("/cards", params={"limit": 100, "offset": 0})
    assert resp.status_code == 200, resp.text
    by_liner = {c["base"]["one_liner"]: c for c in resp.json()}
    assert "good-one" in by_liner
    # The bad block is dropped; the valid sibling block is preserved.
    poisoned = by_liner.get("poison-missing-field")
    assert poisoned is not None
    assert [b["type"] for b in poisoned["blocks"]] == ["paragraph"]


@pytest.mark.anyio
async def test_unknown_enum_values_do_not_break_listing(client, database):
    """Unrecognised state / failure_reason strings must degrade, not raise."""
    async with database.session() as s:
        await _insert(s, one_liner="good-one")
        await _insert(s, one_liner="poison-state", state="halfway_done")
        await _insert(
            s, one_liner="poison-reason", state="failed", failure_reason="rate_limited"
        )
        await s.commit()

    resp = await client.get("/cards", params={"limit": 100, "offset": 0})
    assert resp.status_code == 200, resp.text
    assert "good-one" in {c["base"]["one_liner"] for c in resp.json()}


@pytest.mark.anyio
async def test_malformed_insight_does_not_break_listing(client, database):
    """A stored insight blob that no longer matches the model must degrade."""
    async with database.session() as s:
        await _insert(s, one_liner="good-one")
        await _insert(
            s,
            one_liner="poison-insight",
            # `quiz` entries require `question`; `topic_map` requires `center`.
            insight={"quiz": [{"options": ["a", "b"]}], "topic_map": {"nodes": ["x"]}},
        )
        await s.commit()

    resp = await client.get("/cards", params={"limit": 100, "offset": 0})
    assert resp.status_code == 200, resp.text
    assert "good-one" in {c["base"]["one_liner"] for c in resp.json()}


@pytest.mark.anyio
async def test_malformed_nested_dicts_do_not_break_listing(client, database):
    """primary_action / action_items / extraction blobs must degrade safely."""
    async with database.session() as s:
        await _insert(s, one_liner="good-one")
        await _insert(
            s,
            one_liner="poison-nested",
            primary_action={"kind": "teleport", "label": "Go"},
            action_items={"followed": "yes", "items": [{"done": False}]},
            extraction={"transcript": "maybe"},
        )
        await s.commit()

    resp = await client.get("/cards", params={"limit": 100, "offset": 0})
    assert resp.status_code == 200, resp.text
    assert "good-one" in {c["base"]["one_liner"] for c in resp.json()}
