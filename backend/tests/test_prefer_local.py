"""Dev toggle: prefer_local forces on-device structuring by degrading the job
(skip server LLM, keep the bundle for the phone) even when within quota."""

from sqlalchemy import select

from app.store import db


async def test_prefer_local_degrades_job_within_quota(client) -> None:
    r = await client.post(
        "/cards", json={"url": "https://example.com/local", "prefer_local": True}
    )
    assert r.status_code == 200
    assert r.json()["quota_degraded"] is True

    async with db.session() as s:
        jobs = (await s.execute(select(db.JobRow))).scalars().all()
    assert len(jobs) == 1 and jobs[0].degraded is True


async def test_default_uses_server_llm(client) -> None:
    r = await client.post("/cards", json={"url": "https://example.com/server"})
    assert r.status_code == 200
    assert r.json()["quota_degraded"] is False

    async with db.session() as s:
        jobs = (await s.execute(select(db.JobRow))).scalars().all()
    assert len(jobs) == 1 and jobs[0].degraded is False
