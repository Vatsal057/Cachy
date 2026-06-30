"""End-to-end pipeline with ingestion + extraction stubbed (no network, no ffmpeg,
no keys). A job must still reach READY with a sane card (docs/01, docs/04)."""

import os

import pytest

from app.models.artifact import Artifact, ArtifactType
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

    def fake_upload(local_path, card_id):
        return f"https://huggingface.co/datasets/test/resolve/main/media/{card_id}/{os.path.basename(local_path)}"

    monkeypatch.setattr(worker, "download_content_async", fake_download)
    monkeypatch.setattr(worker, "extract_async", fake_extract)
    monkeypatch.setattr(worker.media, "upload_file", fake_upload)
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
    assert card.media.thumbnail == f"https://huggingface.co/datasets/test/resolve/main/media/{card_id}/frame_001.jpg"
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


async def test_reset_orphaned_processing_jobs(database):
    card_id, job_id = await _make_card_and_job("https://instagram.com/reel/orphaned")
    async with db.session() as s:
        job = await s.get(db.JobRow, job_id)
        job.state = JobState.PROCESSING.value
        await s.commit()

    async with db.session() as s:
        count = await db.reset_orphaned_processing_jobs(s)
        assert count == 1
        job = await s.get(db.JobRow, job_id)
        assert job.state == JobState.QUEUED.value


async def test_preserve_custom_collection(database, stub_pipeline):
    card_id, _ = await _make_card_and_job("https://instagram.com/reel/custom_col")
    async with db.session() as s:
        custom_col = await db.create_custom_collection(s, name="My Custom Folder", owner_id=None)
        row = await db.get_card_row(s, card_id)
        row.collection_id = custom_col.id
        await s.commit()

    async with db.session() as s:
        jid = await _first_job_id(s, card_id)
        job = await s.get(db.JobRow, jid)
        await worker._run_job(s, job)

    async with db.session() as s:
        row = await db.get_card_row(s, card_id)
        assert row.collection_id is not None
        col = await s.get(db.CollectionRow, row.collection_id)
        assert col.name == "My Custom Folder"


async def test_persist_artifacts_sequential_and_rollback(database, monkeypatch):
    """Verify that multiple artifacts resolve thumbnails in parallel but upsert
    sequentially, and any individual failure triggers session rollback so the
    session remains valid for subsequent operations."""
    card_id, _ = await _make_card_and_job("https://instagram.com/reel/artifacts_test")
    artifacts = [
        Artifact(type=ArtifactType.BOOK, title=f"Book {i}") for i in range(5)
    ]

    def fake_thumb(art):
        return f"https://img/{art.title}.jpg"

    monkeypatch.setattr(worker.artifact_images, "resolve_thumbnail", fake_thumb)

    orig_upsert = db.upsert_artifact

    async def flaky_upsert(session, **kwargs):
        if kwargs["title"] == "Book 2":
            raise RuntimeError("simulated DB constraint failure")
        return await orig_upsert(session, **kwargs)

    monkeypatch.setattr(db, "upsert_artifact", flaky_upsert)

    async with db.session() as s:
        await worker._persist_artifacts(s, card_id, artifacts)
        # Session must still be usable (not in PendingRollbackError state)
        row = await db.get_card_row(s, card_id)
        assert row is not None

    async with db.session() as s:
        from sqlalchemy import select
        res = await s.execute(select(db.ArtifactRow).order_by(db.ArtifactRow.title))
        rows = res.scalars().all()
        titles = [r.title for r in rows]
        assert "Book 0" in titles
        assert "Book 1" in titles
        assert "Book 2" not in titles
        assert "Book 3" in titles
        assert "Book 4" in titles


