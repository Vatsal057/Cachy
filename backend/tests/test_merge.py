"""Guest (anonymous) account data folding into an existing account."""

from sqlalchemy import select

from app import auth
from app.auth import get_owner
from app.main import app
from app.store import db


async def _seed_card(owner_id: str) -> None:
    async with db.session() as s:
        s.add(db.CardRow(owner_id=owner_id, source_url=f"https://x/{owner_id}", state="ready"))
        await s.commit()


async def test_merge_folds_guest_rows_into_account(client, monkeypatch) -> None:
    await _seed_card("guest-uid")

    # Caller (Bearer) is the destination Google account.
    app.dependency_overrides[get_owner] = lambda: "google-uid"
    # guest_token verifies to an anonymous guest uid.
    # verify_async wraps auth._verify via to_thread; patch the underlying fn.
    monkeypatch.setattr(
        auth,
        "_verify",
        lambda _t: {"uid": "guest-uid", "firebase": {"sign_in_provider": "anonymous"}},
    )

    resp = await client.post("/auth/merge", json={"guest_token": "guest-jwt"})
    assert resp.status_code == 200 and resp.json()["merged"] >= 1

    async with db.session() as s:
        cards = (await s.execute(select(db.CardRow))).scalars().all()
    assert cards and all(c.owner_id == "google-uid" for c in cards)


async def test_merge_rejects_non_anonymous_source(client, monkeypatch) -> None:
    app.dependency_overrides[get_owner] = lambda: "google-uid"
    monkeypatch.setattr(
        auth,
        "_verify",
        lambda _t: {"uid": "other-real-uid", "firebase": {"sign_in_provider": "google.com"}},
    )
    resp = await client.post("/auth/merge", json={"guest_token": "real-jwt"})
    assert resp.status_code == 403
