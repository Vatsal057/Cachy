"""On-device AI round-trip: bundle persisted for degraded jobs, owner-scoped
bundle fetch, and server-validated structure upload."""

import json

from app.store import db

VALID_STRUCTURE = {
    "base": {
        "one_liner": "Quick pasta technique",
        "tldr": "Salt the water, finish in the pan.",
        "content_type": "recipe",
        "type_confidence": 0.9,
        "tags": ["cooking"],
    },
    "blocks": [
        {"type": "checklist", "items": [{"text": "salt water", "checked": False}]},
    ],
    "artifacts": [],
    "action_items": [],
    "concepts": [],
    "depth": "shallow",
}


async def _seed_degraded_card(owner: str = "test-user") -> str:
    """READY paragraph-fallback card with a stored raw bundle."""
    async with db.session() as s:
        card = db.CardRow(
            owner_id=owner,
            source_url=f"https://example.com/{owner}-degraded",
            state="ready",
            one_liner="Saved video",
            tldr="transcript text",
            blocks=[{"type": "paragraph", "id": "b1", "text": "transcript text"}],
            raw_bundle=json.dumps(
                {"bundle": "SOURCE: x\nTRANSCRIPT: transcript text",
                 "transcript": "transcript text", "caption": "cap"}
            ),
        )
        s.add(card)
        await s.commit()
        return card.id


# --- A1: persistence helper ------------------------------------------------


async def test_store_raw_bundle_sets_column(database) -> None:
    async with db.session() as s:
        card = db.CardRow(source_url="https://x/1", state="processing", owner_id="u")
        s.add(card)
        await s.commit()
        cid = card.id
    async with db.session() as s:
        await db.store_raw_bundle(
            s, card_id=cid, bundle="B", transcript="T", caption="C"
        )
    async with db.session() as s:
        row = await s.get(db.CardRow, cid)
        stored = json.loads(row.raw_bundle)
    assert stored == {"bundle": "B", "transcript": "T", "caption": "C"}


async def test_raw_bundle_defaults_null(database) -> None:
    async with db.session() as s:
        card = db.CardRow(source_url="https://x/2", state="ready", owner_id="u")
        s.add(card)
        await s.commit()
        assert card.raw_bundle is None


# --- A2: GET /cards/{id}/bundle ---------------------------------------------


async def test_bundle_returned_to_owner(client) -> None:
    cid = await _seed_degraded_card()
    r = await client.get(f"/cards/{cid}/bundle")
    assert r.status_code == 200
    body = r.json()
    assert body["transcript"] == "transcript text" and body["caption"] == "cap"
    assert "TRANSCRIPT" in body["bundle"]


async def test_bundle_404_for_other_owner(client) -> None:
    cid = await _seed_degraded_card()
    r = await client.get(f"/cards/{cid}/bundle", headers={"x-owner-id": "someone-else"})
    assert r.status_code == 404


async def test_bundle_404_when_not_stored(client) -> None:
    created = await client.post("/cards", json={"url": "https://example.com/nb"})
    cid = created.json()["card_id"]
    r = await client.get(f"/cards/{cid}/bundle")
    assert r.status_code == 404


# --- A3: POST /cards/{id}/structure ------------------------------------------


async def test_structure_upgrades_card_and_clears_bundle(client) -> None:
    cid = await _seed_degraded_card()
    r = await client.post(f"/cards/{cid}/structure", json=VALID_STRUCTURE)
    assert r.status_code == 200

    card = (await client.get(f"/cards/{cid}")).json()
    assert card["base"]["one_liner"] == "Quick pasta technique"
    assert card["blocks"][0]["type"] == "checklist"

    async with db.session() as s:
        row = await s.get(db.CardRow, cid)
        assert row.raw_bundle is None  # spent


async def test_structure_rejects_garbage_422(client) -> None:
    cid = await _seed_degraded_card()
    r = await client.post(f"/cards/{cid}/structure", json={"blocks": "not-a-list"})
    assert r.status_code == 422
    # paragraph card untouched
    card = (await client.get(f"/cards/{cid}")).json()
    assert card["base"]["one_liner"] == "Saved video"


async def test_structure_404_for_other_owner(client) -> None:
    cid = await _seed_degraded_card()
    r = await client.post(
        f"/cards/{cid}/structure", json=VALID_STRUCTURE,
        headers={"x-owner-id": "someone-else"},
    )
    assert r.status_code == 404


async def test_structure_404_without_stored_bundle(client) -> None:
    created = await client.post("/cards", json={"url": "https://example.com/ns"})
    cid = created.json()["card_id"]
    r = await client.post(f"/cards/{cid}/structure", json=VALID_STRUCTURE)
    assert r.status_code == 404
