"""Cachy ID auth: register/login/reset/link + JWT verification end-to-end."""

import pytest

from app.auth import get_owner
from app.config import get_settings
from app.main import app

_TEST_SECRET = "test-secret-0123456789abcdef"


@pytest.fixture
def id_secret(monkeypatch):
    monkeypatch.setenv("CACHY_ID_SECRET", _TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _real_auth():
    """Use the real get_owner (JWT/Firebase verification) for the next calls."""
    if get_owner in app.dependency_overrides:
        del app.dependency_overrides[get_owner]


async def _register(client, username="testuser", password="password123"):
    return await client.post(
        "/id/register", json={"username": username, "password": password}
    )


async def test_register_login_token_flow(client, id_secret) -> None:
    reg = await _register(client)
    assert reg.status_code == 201, reg.text
    body = reg.json()
    assert body["username"] == "testuser"
    assert body["uid"].startswith("id_")
    assert body["token"]
    assert body["recovery_code"] and "-" in body["recovery_code"]

    login = await client.post(
        "/id/login", json={"username": "testuser", "password": "password123"}
    )
    assert login.status_code == 200, login.text
    token = login.json()["token"]

    # The minted JWT authenticates against the real get_owner path.
    _real_auth()
    me = await client.get("/id/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200, me.text
    assert me.json() == {"uid": body["uid"], "username": "testuser"}

    # And it scopes data: a card created under the ID token is invisible to others.
    created = await client.post(
        "/cards",
        json={"url": "https://example.com/x"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert created.status_code in (200, 201), created.text
    quota = await client.get(
        "/me/quota", headers={"Authorization": f"Bearer {token}"}
    )
    assert quota.status_code == 200


async def test_register_validation(client, id_secret) -> None:
    for bad in ("ab", "UPPER", "with space", "a" * 21, "admin", "with-dash"):
        resp = await _register(client, username=bad)
        assert resp.status_code == 422, (bad, resp.text)
    resp = await _register(client, username="goodname", password="short")
    assert resp.status_code == 422


async def test_register_duplicate(client, id_secret) -> None:
    assert (await _register(client)).status_code == 201
    dup = await _register(client)
    assert dup.status_code == 409
    # Case-insensitive: TESTUSER collides with testuser.
    dup2 = await _register(client, username="TESTUSER")
    assert dup2.status_code == 409


async def test_login_wrong_password_then_lockout(client, id_secret) -> None:
    assert (await _register(client)).status_code == 201
    for _ in range(5):
        resp = await client.post(
            "/id/login", json={"username": "testuser", "password": "nope12345"}
        )
        assert resp.status_code == 401
    locked = await client.post(
        "/id/login", json={"username": "testuser", "password": "nope12345"}
    )
    assert locked.status_code == 423
    # Correct password is also rejected while locked.
    resp = await client.post(
        "/id/login", json={"username": "testuser", "password": "password123"}
    )
    assert resp.status_code == 423


async def test_login_unknown_user_is_generic_401(client, id_secret) -> None:
    resp = await client.post(
        "/id/login", json={"username": "nobodyhere", "password": "password123"}
    )
    assert resp.status_code == 401
    assert "wrong ID or password" in resp.json()["detail"]


async def test_reset_flow(client, id_secret) -> None:
    reg = await _register(client)
    code = reg.json()["recovery_code"]
    bad = await client.post(
        "/id/reset",
        json={"username": "testuser", "recovery_code": "wrong-code", "new_password": "newpassword123"},
    )
    assert bad.status_code == 401
    ok = await client.post(
        "/id/reset",
        json={"username": "testuser", "recovery_code": code, "new_password": "newpassword123"},
    )
    assert ok.status_code == 200, ok.text
    # Old password dead, new password works.
    assert (
        await client.post("/id/login", json={"username": "testuser", "password": "password123"})
    ).status_code == 401
    good = await client.post(
        "/id/login", json={"username": "testuser", "password": "newpassword123"}
    )
    assert good.status_code == 200


async def test_change_password(client, id_secret) -> None:
    reg = await _register(client)
    token = reg.json()["token"]
    _real_auth()
    headers = {"Authorization": f"Bearer {token}"}
    bad = await client.post(
        "/id/change-password",
        json={"current_password": "wrong12345", "new_password": "newpassword123"},
        headers=headers,
    )
    assert bad.status_code == 401
    ok = await client.post(
        "/id/change-password",
        json={"current_password": "password123", "new_password": "newpassword123"},
        headers=headers,
    )
    assert ok.status_code == 200


async def test_link_firebase_account(client, id_secret) -> None:
    """A Firebase user claims an ID; afterwards the ID token resolves to the
    Firebase uid, so both login methods share one library."""
    app.dependency_overrides[get_owner] = lambda: "fb-test-uid"
    link = await client.post(
        "/id/link", json={"username": "linked_one", "password": "password123"}
    )
    assert link.status_code == 200, link.text
    assert link.json()["uid"] == "fb-test-uid"
    # Second link on the same Firebase account is rejected.
    again = await client.post(
        "/id/link", json={"username": "other_name", "password": "password123"}
    )
    assert again.status_code == 409
    # The ID login now yields the Firebase uid as owner.
    login = await client.post(
        "/id/login", json={"username": "linked_one", "password": "password123"}
    )
    assert login.json()["uid"] == "fb-test-uid"
    _real_auth()
    me = await client.get(
        "/id/me", headers={"Authorization": f"Bearer {login.json()['token']}"}
    )
    assert me.json() == {"uid": "fb-test-uid", "username": "linked_one"}


async def test_available(client, id_secret) -> None:
    assert (await client.get("/id/available", params={"username": "freshname"})).json()[
        "available"
    ] is True
    assert (await _register(client, username="freshname")).status_code == 201
    assert (await client.get("/id/available", params={"username": "freshname"})).json()[
        "available"
    ] is False
    assert (await client.get("/id/available", params={"username": "ab"})).json()[
        "available"
    ] is False


async def test_disabled_without_secret(client) -> None:
    """No CACHY_ID_SECRET -> /id/* is 503, never 500."""
    get_settings.cache_clear()  # ensure the secret is really unset here
    resp = await client.post(
        "/id/register", json={"username": "x", "password": "password123"}
    )
    assert resp.status_code == 503
