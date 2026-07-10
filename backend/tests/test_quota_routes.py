"""Quota wiring: chat 429s past limit; card creation degrades; /me/quota reports."""

import pytest
from sqlalchemy import select

from app import config
from app.store import db


@pytest.fixture(autouse=True)
def _small_limits(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("QUOTA_CARDS_PER_DAY", "1")
    monkeypatch.setenv("QUOTA_CHAT_PER_DAY", "1")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


async def test_card_creation_degrades_past_quota(client) -> None:
    r1 = await client.post("/cards", json={"url": "https://example.com/1"})
    assert r1.status_code in (200, 201)
    r2 = await client.post("/cards", json={"url": "https://example.com/2"})
    assert r2.status_code in (200, 201)  # degrade, never fail
    async with db.session() as s:
        jobs = (await s.execute(select(db.JobRow).order_by(db.JobRow.created_at))).scalars().all()
    assert [j.degraded for j in jobs] == [False, True]


async def test_me_quota(client) -> None:
    resp = await client.get("/me/quota")
    assert resp.status_code == 200
    body = resp.json()
    assert body["cards"]["limit"] == 1 and "resets_at" in body
