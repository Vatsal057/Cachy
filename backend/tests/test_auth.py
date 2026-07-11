"""get_owner: valid token -> uid; garbage/missing -> 401; unconfigured -> 503."""

from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.auth import get_owner
from app.config import get_settings


@pytest.fixture(autouse=True)
def _reset_settings():
    """Each test mutates FIREBASE_PROJECT_ID; clear the settings cache around it."""
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


async def test_missing_header_401(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-project")
    get_settings.cache_clear()
    with pytest.raises(HTTPException) as exc:
        await get_owner(authorization=None)
    assert exc.value.status_code == 401


async def test_valid_token_returns_uid(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-project")
    get_settings.cache_clear()
    with patch("app.auth._verify", return_value={"uid": "user-123"}):
        uid = await get_owner(authorization="Bearer sometoken")
    assert uid == "user-123"


async def test_invalid_token_401(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-project")
    get_settings.cache_clear()
    with patch("app.auth._verify", side_effect=ValueError("bad token")):
        with pytest.raises(HTTPException) as exc:
            await get_owner(authorization="Bearer garbage")
    assert exc.value.status_code == 401


async def test_unconfigured_503(monkeypatch: pytest.MonkeyPatch) -> None:
    # Empty env var, not delenv: an env var overrides the developer's .env,
    # whereas delenv lets a populated .env leak a real project id back in.
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "")
    get_settings.cache_clear()
    with pytest.raises(HTTPException) as exc:
        await get_owner(authorization="Bearer sometoken")
    assert exc.value.status_code == 503
