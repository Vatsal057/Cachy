"""Admin/debug gated; 500s never leak tracebacks."""

import pytest

from app import config


@pytest.fixture(autouse=True)
def _reset_settings():
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


async def test_admin_requires_token(client, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ADMIN_TOKEN", "s3cret")
    config.get_settings.cache_clear()
    assert (await client.get("/admin/stats")).status_code == 401
    assert (await client.get("/debug/jobs")).status_code == 401
    ok = await client.get("/admin/stats", headers={"x-admin-token": "s3cret"})
    assert ok.status_code == 200


async def test_admin_disabled_when_unset(client, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ADMIN_TOKEN", raising=False)
    config.get_settings.cache_clear()
    assert (await client.get("/debug/jobs")).status_code == 401
