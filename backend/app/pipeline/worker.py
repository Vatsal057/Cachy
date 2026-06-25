"""Job runner (docs/01, docs/05): the spine. An in-process background loop polls
the DB-backed queue and runs each job through ingest -> extract -> structure ->
persist, emitting a stage event at each step for the SSE stream.

State machine: QUEUED -> PROCESSING -> READY, or FAILED with a reason. Transient
errors retry; jobs that exhaust attempts are dead-lettered (card -> FAILED).

Progressive persistence: `base` is written first (so read-now can stream the
one-liner+tldr immediately), then blocks, then media."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import or_, select, update

from app.config import get_settings
from app.models.card import CardState, FailureReason
from app.models.job import JobState
from app.pipeline.extraction import extract_async
from app.pipeline.ingestion.downloader import (
    DownloadError,
    DownloaderConfig,
    download_content_async,
)
from app.pipeline.structuring import structure_async
from app.services import artifact_images, embeddings, events, llm_chat, notify
from app.store import db, media

log = logging.getLogger("pipeline.worker")

_stop = asyncio.Event()


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# --------------------------------------------------------------------------- #
# Queue claim
# --------------------------------------------------------------------------- #

async def _claim_next_job(session) -> db.JobRow | None:
    """Pick one runnable job and mark it PROCESSING. Runnable = QUEUED, or FAILED
    with attempts left (retry)."""
    settings = get_settings()
    res = await session.execute(
        select(db.JobRow)
        .where(
            or_(
                db.JobRow.state == JobState.QUEUED.value,
                (db.JobRow.state == JobState.FAILED.value)
                & (db.JobRow.attempts < settings.max_attempts),
            )
        )
        .order_by(db.JobRow.created_at)
        .limit(1)
    )
    job = res.scalar_one_or_none()
    if job is None:
        return None
    job.state = JobState.PROCESSING.value
    job.started_at = _utcnow()
    await session.commit()
    return job


# --------------------------------------------------------------------------- #
# Persistence helpers (each commits so SSE/clients see progress)
# --------------------------------------------------------------------------- #

async def _set_card_processing(session, card_id: str) -> None:
    await session.execute(
        update(db.CardRow)
        .where(db.CardRow.id == card_id)
        .values(state=CardState.PROCESSING.value)
    )
    await session.commit()


async def _write_base(session, card_id: str, structured) -> None:
    base = structured.base
    await session.execute(
        update(db.CardRow)
        .where(db.CardRow.id == card_id)
        .values(
            one_liner=base.one_liner,
            tldr=base.tldr,
            content_type=base.content_type.value,
            type_confidence=base.type_confidence,
            tags=base.tags,
            primary_action=structured.primary_action.model_dump(),
        )
    )
    await session.commit()


async def _write_blocks(session, card_id: str, blocks: list[dict]) -> None:
    await session.execute(
        update(db.CardRow).where(db.CardRow.id == card_id).values(blocks=blocks)
    )
    await session.commit()


async def _write_media_and_meta(
    session, card_id: str, extraction, caption: str, resolver: str,
    creator: str | None = None,
) -> None:
    values = dict(
        thumbnail=extraction.thumbnail,
        keyframes=extraction.keyframes,
        caption=caption,
        resolver=resolver,
        extraction={
            "transcript": extraction.had_transcript,
            "ocr": extraction.had_ocr,
            "visual": extraction.had_visual,
        },
    )
    if creator:  # article byline -> shown in the source line
        values["creator"] = creator
    await session.execute(
        update(db.CardRow).where(db.CardRow.id == card_id).values(**values)
    )
    await session.commit()


async def _persist_artifacts(session, card_id: str, artifacts) -> None:
    """Aggregate referenced things into the global catalog (docs/12). Each lookup
    is best-effort and isolated — a failure here never affects the card itself."""
    for art in artifacts:
        try:
            thumbnail = await asyncio.to_thread(
                artifact_images.resolve_thumbnail, art
            )
            await db.upsert_artifact(
                session,
                card_id=card_id,
                type_=art.type.value,
                title=art.title,
                creator=art.creator,
                year=art.year,
                thumbnail=thumbnail,
            )
        except Exception:  # noqa: BLE001 — catalog is non-critical to the card
            log.warning("catalog upsert failed for %r", art.title, exc_info=True)


async def _embed_card(session, card_id: str) -> None:
    """Compute + store a semantic-search embedding for the card (docs/09).
    Best-effort and isolated: any failure (no HF key, network) leaves the card
    embedding-less, and search degrades to full-text. Reuses the same flattened
    card-text view as grounded chat (llm_chat.card_context)."""
    row = await db.get_card_row(session, card_id)
    if row is None:
        return
    text = llm_chat.card_context(row.to_card())
    vector = await asyncio.to_thread(embeddings.embed, text)
    if not vector:
        return
    await session.execute(
        update(db.CardRow).where(db.CardRow.id == card_id).values(embedding=vector)
    )
    await session.commit()


async def _finish_ready(session, card_id: str, job: db.JobRow) -> None:
    await session.execute(
        update(db.CardRow)
        .where(db.CardRow.id == card_id)
        .values(state=CardState.READY.value, failure_reason=None)
    )
    job.state = JobState.DONE.value
    job.finished_at = _utcnow()
    await session.commit()


async def _fail(
    session, card_id: str, job: db.JobRow, reason: FailureReason, error: str
) -> bool:
    """Record a failed attempt. Returns True if dead-lettered (terminal)."""
    settings = get_settings()
    job.attempts += 1
    job.last_error = error[:1000]
    dead = job.attempts >= settings.max_attempts
    if dead:
        job.state = JobState.DEAD.value
        job.finished_at = _utcnow()
        await session.execute(
            update(db.CardRow)
            .where(db.CardRow.id == card_id)
            .values(state=CardState.FAILED.value, failure_reason=reason.value)
        )
    else:
        # leave eligible for retry
        job.state = JobState.FAILED.value
    await session.commit()
    return dead


# --------------------------------------------------------------------------- #
# Run one job through the pipeline
# --------------------------------------------------------------------------- #

async def _run_job(session, job: db.JobRow) -> None:
    card = await db.get_card_row(session, job.card_id)
    if card is None:
        job.state = JobState.DEAD.value
        await session.commit()
        return
    card_id = card.id
    url = card.source_url
    platform = card.platform
    tag = f"[card {card_id}]"  # log prefix so concurrent jobs stay distinguishable

    await _set_card_processing(session, card_id)
    events.publish(card_id, "processing", "processing", "Starting")
    log.info("%s pipeline start | url=%s platform=%s", tag, url, platform or "?")

    # 1) Ingestion
    events.publish(card_id, "downloading", "processing", "Downloading media")
    log.info("%s Step 1/6 ingest: resolving + downloading media", tag)
    try:
        cfg = DownloaderConfig(
            output_dir=media.media_root(),
            cookies_path=get_settings().cookies_path or None,
        )
        download = await download_content_async(url, cfg)
    except DownloadError as e:
        log.warning("%s Step 1/6 ingest FAILED (all resolvers exhausted): %s", tag, e)
        dead = await _fail(session, card_id, job, FailureReason.UNAVAILABLE, str(e))
        if dead:
            events.publish(card_id, "failed", "failed", "Could not download",
                           FailureReason.UNAVAILABLE.value)
            notify.notify_card_failed(card_id, FailureReason.UNAVAILABLE.value)
        return
    _count = len(download.data) if isinstance(download.data, list) else 1
    log.info(
        "%s Step 1/6 ingest OK | resolver=%s type=%s items=%d caption=%s",
        tag, download.resolver, download.media_type, _count,
        "yes" if (download.caption or "").strip() else "no",
    )

    # 2) Extraction
    events.publish(card_id, "extracting", "processing", "Extracting audio + frames")
    log.info("%s Step 2/6 extract: transcript + on-screen text from media", tag)
    work_dir = media.job_dir_for_card(card_id)
    source_line = f"{platform or 'unknown'} / {download.resolver}"
    extraction = await extract_async(download, work_dir, source_line)
    log.info(
        "%s Step 2/6 extract OK | frames=%d transcript=%s ocr=%s vision=%s",
        tag, len(extraction.keyframes), extraction.had_transcript,
        extraction.had_ocr, extraction.had_visual,
    )
    if not (extraction.had_transcript or extraction.had_ocr or extraction.had_visual
            or (download.caption or "").strip()):
        log.warning(
            "%s Step 2/6 extract THIN: no transcript, OCR, vision, or caption — "
            "card will lean on whatever little text exists", tag,
        )

    # 3) Structuring (+ validation/fallback) — write base first for progressive render
    events.publish(card_id, "structuring", "processing", "Structuring card")
    log.info("%s Step 3/6 structure: LLM -> validated knowledge card", tag)
    structured = await structure_async(
        extraction.aggregated_text, extraction.transcript, download.caption or ""
    )
    if structured.degraded:
        log.warning(
            "%s Step 3/6 structure DEGRADED: LLM structuring did not succeed "
            "(%s) — falling back to a plain paragraph card",
            tag, structured.degraded_reason or "unknown reason",
        )
    else:
        log.info(
            "%s Step 3/6 structure OK | type=%s blocks=%d artifacts=%d",
            tag, structured.base.content_type.value, len(structured.blocks),
            len(structured.artifacts),
        )

    # 4) Persist progressively: base -> blocks -> media
    events.publish(card_id, "persisting", "processing", "Saving card")
    log.info("%s Step 4/6 persist: writing base -> blocks -> media", tag)
    await _write_base(session, card_id, structured)
    await _write_blocks(session, card_id, structured.blocks)
    await _write_media_and_meta(
        session, card_id, extraction, download.caption or "", download.resolver,
        creator=download.author,
    )

    # 5) Catalog: aggregate any referenced artifacts + fetch their thumbnails.
    if structured.artifacts:
        events.publish(card_id, "cataloging", "processing", "Cataloging references")
        log.info("%s Step 5/6 catalog: %d referenced artifact(s)", tag,
                 len(structured.artifacts))
        await _persist_artifacts(session, card_id, structured.artifacts)
    else:
        log.info("%s Step 5/6 catalog: none referenced, skipping", tag)

    # 6) Semantic index: embed the card for search (best-effort, no-op without a key).
    log.info("%s Step 6/6 index: embedding card for semantic search", tag)
    try:
        await _embed_card(session, card_id)
    except Exception:  # noqa: BLE001 — semantic index is non-critical to the card
        log.warning("%s Step 6/6 index: embedding failed (search degrades to "
                    "full-text)", tag, exc_info=True)

    # Optionally discard the source video, keep keyframes+thumbnail (docs/11)
    if get_settings().discard_source_video and download.media_type == "video":
        media.remove_path(str(download.data))

    await _finish_ready(session, card_id, job)
    events.publish(card_id, "done", "ready", "Card ready")
    notify.notify_card_ready(card_id)
    log.info("%s pipeline DONE | card READY%s", tag,
             " (degraded/paragraph fallback)" if structured.degraded else "")


# --------------------------------------------------------------------------- #
# Loop
# --------------------------------------------------------------------------- #

async def run_worker_loop() -> None:
    settings = get_settings()
    log.info("worker loop started")
    while not _stop.is_set():
        try:
            async with db.session() as session:
                job = await _claim_next_job(session)
                if job is None:
                    await asyncio.sleep(settings.worker_poll_seconds)
                    continue
                try:
                    await asyncio.wait_for(
                        _run_job(session, job),
                        timeout=settings.job_timeout_seconds,
                    )
                except asyncio.TimeoutError:
                    await _fail(
                        session, job.card_id, job, FailureReason.TIMEOUT, "job timed out"
                    )
                    events.publish(job.card_id, "failed", "failed", "Timed out",
                                   FailureReason.TIMEOUT.value)
                except Exception as e:  # noqa: BLE001 — pipeline must never crash the loop
                    log.exception("job %s failed", job.id)
                    await _fail(session, job.card_id, job, FailureReason.UNAVAILABLE, str(e))
        except Exception:  # noqa: BLE001
            log.exception("worker loop iteration error")
            await asyncio.sleep(settings.worker_poll_seconds)
    log.info("worker loop stopped")


def stop_worker() -> None:
    _stop.set()


def reset_stop() -> None:
    _stop.clear()
