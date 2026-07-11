"""Cross-owner isolation: a card/collection/artifact/concept owned by one user
is invisible and immutable to another. Locks the owner-scoping guards on the
by-id routes (get/patch/delete card, collections, catalog, concepts)."""

from app.store import db


async def _card(database, cid: str, owner: str) -> None:
    async with database.session() as s:
        s.add(database.CardRow(
            id=cid, source_url=f"http://iso/{cid}", state="ready", owner_id=owner,
            one_liner="secret", tldr="secret body",
        ))
        await s.commit()


def _h(owner: str) -> dict:
    return {"x-owner-id": owner}


async def test_get_patch_delete_card_denied_to_other_owner(client, database):
    await _card(database, "iso-1", "alice")

    assert (await client.get("/cards/iso-1", headers=_h("bob"))).status_code == 404
    assert (await client.patch(
        "/cards/iso-1", headers=_h("bob"), json={"blocks": []}
    )).status_code == 404
    assert (await client.delete("/cards/iso-1", headers=_h("bob"))).status_code == 404

    # Owner still gets it, and it survived bob's delete attempt.
    assert (await client.get("/cards/iso-1", headers=_h("alice"))).status_code == 200


async def test_collection_mutations_denied_to_other_owner(client, database):
    await _card(database, "iso-2", "alice")
    created = await client.post(
        "/collections", headers=_h("alice"), json={"name": "Alice folder"}
    )
    col_id = created.json()["id"]

    assert (await client.patch(
        f"/collections/{col_id}", headers=_h("bob"), json={"name": "hijack"}
    )).status_code == 404
    assert (await client.delete(
        f"/collections/{col_id}", headers=_h("bob")
    )).status_code == 404
    # Bob can't move alice's card either.
    assert (await client.post(
        "/collections/cards/iso-2/move", headers=_h("bob"),
        json={"collection_id": col_id},
    )).status_code == 404


async def test_catalog_and_concept_by_id_denied_to_other_owner(client, database):
    await _card(database, "iso-3", "alice")
    async with database.session() as s:
        art = await db.upsert_artifact(
            s, card_id="iso-3", type_="book", title="Alice Book",
            creator=None, year=None, thumbnail=None,
        )
        await db.set_artifact_saved(s, art.id, True, "alice")
        con = await db.upsert_concept(s, card_id="iso-3", name="alice concept")
        art_id, con_id = art.id, con.id

    assert (await client.get(
        f"/catalog/{art_id}", headers=_h("bob")
    )).status_code == 404
    assert (await client.delete(
        f"/catalog/{art_id}", headers=_h("bob")
    )).status_code == 404
    assert (await client.post(
        f"/concepts/{con_id}/define", headers=_h("bob")
    )).status_code == 404
    assert (await client.delete(
        f"/concepts/{con_id}", headers=_h("bob")
    )).status_code == 404

    # Owner still reaches the catalog entry.
    assert (await client.get(
        f"/catalog/{art_id}", headers=_h("alice")
    )).status_code == 200


async def test_catalog_saved_state_is_per_owner(client, database):
    """A single shared artifact (referenced by two owners' cards) has independent
    catalog membership per owner — one saving/removing never affects the other."""
    await _card(database, "shared-a", "alice")
    await _card(database, "shared-b", "bob")
    async with database.session() as s:
        # Same title+type from both cards dedupes into ONE shared artifact row.
        await db.upsert_artifact(
            s, card_id="shared-a", type_="book", title="Shared Book",
            creator=None, year=None, thumbnail=None,
        )
        art = await db.upsert_artifact(
            s, card_id="shared-b", type_="book", title="Shared Book",
            creator=None, year=None, thumbnail=None,
        )
        art_id = art.id

    # Alice saves it; her catalog shows it, bob's does not.
    assert (await client.post(
        f"/catalog/{art_id}/save", headers=_h("alice")
    )).status_code == 200
    alice_titles = [e["title"] for e in (
        await client.get("/catalog", headers=_h("alice"))).json()]
    bob_titles = [e["title"] for e in (
        await client.get("/catalog", headers=_h("bob"))).json()]
    assert alice_titles == ["Shared Book"]
    assert bob_titles == []

    # Bob saves it too — independent membership.
    assert (await client.post(
        f"/catalog/{art_id}/save", headers=_h("bob")
    )).status_code == 200

    # Alice removes it; bob's catalog is untouched.
    assert (await client.delete(
        f"/catalog/{art_id}", headers=_h("alice")
    )).status_code == 200
    assert (await client.get("/catalog", headers=_h("alice"))).json() == []
    assert [e["title"] for e in (
        await client.get("/catalog", headers=_h("bob"))).json()] == ["Shared Book"]
