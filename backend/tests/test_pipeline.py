"""End-to-end pipeline with ingestion + extraction stubbed (no network, no ffmpeg,
no keys). A job must still reach READY with a sane card (docs/01, docs/04)."""

import os

import pytest

from app.models.card import CardState
from app.models.job import JobState
from app.pipeline import worker
from app.pipeline.extraction import ExtractionResult
from app.pipeline.ingestion.downloader import DownloadError, DownloadResult
from app.store import db


async def _make_card_and_job(url: str) -> tuple[str, str]:
    async with db.session() as s:
        card = db.CardRow(source_url=url, platform="instagram",
                          state=CardState.QUEUED.value, blocks=[])
        s.add(card)
        await s.flush()
        job = db.JobRow(card_id=card.id, state=JobState.QUEUED.value)
        s.add(job)
        await s.commit()
        return card.id, job.id


@pytest.fixture
def stub_pipeline(monkeypatch):
    # Frames land under work_dir (a media_root subdir), mirroring real extraction —
    # so to_card() maps them to served /media URLs (docs/05).
    async def fake_download(url, config=None):
        return DownloadResult("video", "/tmp/fake.mp4", "A nice caption", "yt-dlp")

    async def fake_extract(download, work_dir, source_line=""):
        frame = os.path.join(work_dir, "frame_001.jpg")
        return ExtractionResult(
            aggregated_text="CAPTION: A nice caption\nTRANSCRIPT: Do the thing.",
            transcript="Do the thing.",
            ocr_text="",
            thumbnail=frame,
            keyframes=[frame],
            had_transcript=True,
            had_ocr=False,
        )

    monkeypatch.setattr(worker, "download_content_async", fake_download)
    monkeypatch.setattr(worker, "extract_async", fake_extract)
    # don't actually delete /tmp/fake.mp4
    monkeypatch.setattr(worker.media, "remove_path", lambda *a, **k: None)


async def test_job_reaches_ready_with_sane_card(database, stub_pipeline):
    card_id, _ = await _make_card_and_job("https://instagram.com/reel/abc")
    async with db.session() as s:
        job = await s.get(db.JobRow, (await _first_job_id(s, card_id)))
        await worker._run_job(s, job)

    async with db.session() as s:
        row = await db.get_card_row(s, card_id)
        card = row.to_card()

    assert card.state == CardState.READY
    assert card.base.one_liner  # always present
    assert card.base.tldr
    assert card.blocks  # fallback paragraph at minimum
    assert card.media.thumbnail == f"/media/card_{card_id}/frame_001.jpg"
    assert card.source.resolver == "yt-dlp"
    assert card.meta.extraction.transcript is True


async def test_article_job_reaches_ready(database, monkeypatch):
    """A non-video source runs through the article path: no media, real
    extraction branch + structuring (offline -> paragraph fallback), READY."""
    async def fake_download(url, config=None):
        return DownloadResult(
            media_type="article", data="", caption="Sleep Guide",
            resolver="article", text="Sleep early. Avoid screens. " * 20,
            title="Sleep Guide", author="Jane Doe",
            image_url="https://img/cover.jpg",
        )

    monkeypatch.setattr(worker, "download_content_async", fake_download)
    card_id, _ = await _make_card_and_job("https://en.wikipedia.org/wiki/Sleep")

    async with db.session() as s:
        jid = await _first_job_id(s, card_id)
        job = await s.get(db.JobRow, jid)
        await worker._run_job(s, job)

    async with db.session() as s:
        row = await db.get_card_row(s, card_id)
        card = row.to_card()

    assert card.state == CardState.READY
    assert card.base.one_liner and card.base.tldr
    assert card.blocks  # paragraph fallback at minimum
    assert card.media.thumbnail == "https://img/cover.jpg"  # remote passthrough
    assert card.source.resolver == "article"
    assert card.source.creator == "Jane Doe"  # byline persisted


async def test_ingestion_failure_dead_letters_after_retries(database, monkeypatch):
    async def boom(url, config=None):
        raise DownloadError("all resolvers failed")

    monkeypatch.setattr(worker, "download_content_async", boom)
    card_id, _ = await _make_card_and_job("https://instagram.com/reel/dead")

    # MAX_ATTEMPTS=2 in tests -> two failed attempts then DEAD/FAILED.
    for _ in range(2):
        async with db.session() as s:
            jid = await _first_job_id(s, card_id)
            job = await s.get(db.JobRow, jid)
            await worker._run_job(s, job)

    async with db.session() as s:
        row = await db.get_card_row(s, card_id)
    assert row.state == CardState.FAILED.value
    assert row.failure_reason == "unavailable"


async def _first_job_id(session, card_id: str) -> str:
    from sqlalchemy import select
    res = await session.execute(select(db.JobRow.id).where(db.JobRow.card_id == card_id))
    return res.scalar_one()
