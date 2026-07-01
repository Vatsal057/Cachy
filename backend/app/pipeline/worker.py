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
from typing import Any

from sqlalchemy import or_, select, update

from app.api.graph import invalidate_graph_cache
from app.config import get_settings
from app.models.card import CardState, ContentType, FailureReason
from app.models.job import JobState
from app.pipeline.extraction import extract_async
from app.pipeline.ingestion.downloader import (
    DownloadError,
    DownloaderConfig,
    download_content_async,
)
from app.pipeline.insight import analyze_async
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
            action_items=structured.action_items.model_dump(),
        )
    )
    await session.commit()


async def _write_blocks(session, card_id: str, blocks: list[dict]) -> None:
    await session.execute(
        update(db.CardRow).where(db.CardRow.id == card_id).values(blocks=blocks)
    )
    await session.commit()


async def _write_collection(session, card_id: str, content_type: ContentType, owner_id: str | None) -> None:
    """Auto-assign the card to its system collection if not already organized into a custom collection."""
    card = await db.get_card_row(session, card_id)
    if card is not None and card.collection_id is not None:
        return
    collection = await db.get_or_create_collection(
        session, owner_id=owner_id, system_type=content_type.value
    )
    from sqlalchemy import update as sa_update
    await session.execute(
        sa_update(db.CardRow)
        .where(db.CardRow.id == card_id)
        .values(collection_id=collection.id)
    )
    await session.commit()


async def _write_insight(session, card_id: str, insight) -> None:
    """Persist the deep-analysis layer (docs/14). `insight` is a validated model."""
    await session.execute(
        update(db.CardRow)
        .where(db.CardRow.id == card_id)
        .values(insight=insight.model_dump())
    )
    await session.commit()


async def _upload_media_to_hf(extraction, card_id: str):
    """Upload only the thumbnail to HF Dataset — the one frame the app ever
    displays. Other extracted keyframes were just OCR/vision scratch input;
    they're discarded with the rest of the job's scratch dir, never persisted."""
    from dataclasses import replace as dc_replace

    thumbnail = extraction.thumbnail
    if thumbnail and not thumbnail.startswith("http"):
        url = await asyncio.to_thread(media.upload_file, thumbnail, card_id)
        media.remove_path(thumbnail)  # always delete local copy; None url = no thumbnail
        thumbnail = url
    return dc_replace(extraction, thumbnail=thumbnail, keyframes=[])


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


async def _persist_artifacts(session: Any, card_id: str, artifacts: list[Any]) -> None:
    """Aggregate referenced things into the global catalog (docs/12). Thumbnail
    lookups run in parallel — each is best-effort and never blocks the card.
    Skips entirely if the card was deleted mid-pipeline."""
    if await db.get_card_row(session, card_id) is None:
        log.warning("card %s deleted mid-pipeline; skipping artifact persist", card_id)
        return
    async def _resolve_thumb(art: Any) -> tuple[Any, str | None]:
        try:
            thumbnail = await asyncio.to_thread(
                artifact_images.resolve_thumbnail, art
            )
            return art, thumbnail
        except Exception as e:
            log.warning("thumbnail lookup failed for %r: %s", art.title, str(e), exc_info=True)
            return art, None

    resolved = await asyncio.gather(*(_resolve_thumb(art) for art in artifacts))

    for art, thumbnail in resolved:
        try:
            await db.upsert_artifact(
                session,
                card_id=card_id,
                type_=art.type.value,
                title=art.title,
                creator=art.creator,
                year=art.year,
                thumbnail=thumbnail,
            )
        except Exception as e:  # noqa: BLE001 — catalog is non-critical to the card
            await session.rollback()
            log.warning("catalog upsert failed for %r: %s", art.title, str(e), exc_info=True)


async def _persist_concepts(session: Any, card_id: str, concepts: list[str]) -> None:
    """Aggregate evergreen ideas into the global concept store. Best-effort and
    isolated — a failure here never affects the card itself.
    Skips entirely if the card was deleted mid-pipeline."""
    if await db.get_card_row(session, card_id) is None:
        log.warning("card %s deleted mid-pipeline; skipping concept persist", card_id)
        return
    for name in concepts:
        try:
            await db.upsert_concept(session, card_id=card_id, name=name)
        except Exception as e:  # noqa: BLE001 — concepts are non-critical to the card
            await session.rollback()
            log.warning("concept upsert failed for %r: %s", name, str(e), exc_info=True)


async def _embed_card(session: Any, card_id: str) -> None:
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
    invalidate_graph_cache()


async def _fail(
    session, card_id: str, job: db.JobRow, reason: FailureReason, error: str
) -> bool:
    """Record a failed attempt. Returns True if dead-lettered (terminal)."""
    settings = get_settings()
    job.attempts += 1
    job.last_error = error[:1000]
    permanent = any(
        x in error.lower()
        for x in ("all resolvers failed", "unsupported url", "not found", "private", "does not exist")
    )
    dead = (job.attempts >= settings.max_attempts) or permanent
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
            output_dir=media.job_dir_for_card(card_id),
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
    source_line = platform.title() if platform else "Short-form video"
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
    await _write_collection(session, card_id, structured.base.content_type, card.owner_id)
    current_blocks = []
    for i, block in enumerate(structured.blocks, 1):
        current_blocks.append(block)
        await _write_blocks(session, card_id, current_blocks)
        heading = block.get("heading") or block.get("title") or f"section {i}"
        events.publish(card_id, "persisting", "processing", f"Adding {heading}...")
        await asyncio.sleep(0.4)
    extraction = await _upload_media_to_hf(extraction, card_id)
    media.remove_path(media.job_dir_for_card(card_id))  # nuke scratch dir
    await _write_media_and_meta(
        session, card_id, extraction, download.caption or "", download.resolver,
        creator=download.author,
    )

    # 4b) Deep analysis (docs/14) — GATED. Only idea-rich cards (the structuring
    # pass judged `depth == "deep"`) get a second LLM call. A simple reel skips
    # this entirely. Best-effort + isolated: a failure leaves insight=None and
    # never blocks the card from going READY.
    if structured.depth == "deep":
        events.publish(card_id, "analyzing", "processing", "Analyzing in depth")
        log.info("%s Step 4b deep-analysis: depth=deep -> running insight pass", tag)
        try:
            row = await db.get_card_row(session, card_id)
            body = llm_chat.card_context(row.to_card()) if row else ""
            insight = await analyze_async(
                structured.base.one_liner, structured.base.tldr, body,
                structured.base.tags,
            )
            if insight is not None:
                await _write_insight(session, card_id, insight)
                rh = insight.rabbit_hole
                log.info(
                    "%s Step 4b deep-analysis OK | threads=%d quiz=%d "
                    "deep_research=%s", tag,
                    len(rh.questions) + len(rh.adjacent_topics) + len(rh.advanced_concepts),
                    len(insight.quiz.questions),
                    "yes" if insight.deep_research_prompt else "no",
                )
            else:
                log.info("%s Step 4b deep-analysis: no usable layer produced", tag)
        except Exception as e:  # noqa: BLE001 — insight is non-critical to the card
            await session.rollback()
            log.warning("%s Step 4b deep-analysis failed: %s", tag, str(e), exc_info=True)
    else:
        log.info("%s Step 4b deep-analysis: depth=shallow, skipping", tag)

    # 5) Catalog: aggregate any referenced artifacts + fetch their thumbnails.
    if structured.artifacts:
        events.publish(card_id, "cataloging", "processing", "Cataloging references")
        log.info("%s Step 5/6 catalog: %d referenced artifact(s)", tag,
                 len(structured.artifacts))
        await _persist_artifacts(session, card_id, structured.artifacts)
    else:
        log.info("%s Step 5/6 catalog: none referenced, skipping", tag)

    # 5b) Concepts: aggregate evergreen ideas into the concept store.
    if structured.concepts:
        events.publish(card_id, "conceptualizing", "processing", "Indexing concepts")
        log.info("%s Step 5b/6 concepts: %d concept(s)", tag, len(structured.concepts))
        await _persist_concepts(session, card_id, structured.concepts)
    else:
        log.info("%s Step 5b/6 concepts: none extracted, skipping", tag)

    # 6) Semantic index: embed the card for search (best-effort, no-op without a key).
    log.info("%s Step 6/6 index: embedding card for semantic search", tag)
    try:
        await _embed_card(session, card_id)
    except Exception as e:  # noqa: BLE001 — semantic index is non-critical to the card
        await session.rollback()
        log.warning("%s Step 6/6 index: embedding failed (search degrades to "
                    "full-text): %s", tag, str(e), exc_info=True)

    await _finish_ready(session, card_id, job)
    events.publish(card_id, "done", "ready", "Card ready")
    notify.notify_card_ready(card_id)
    log.info("%s pipeline DONE | card READY%s", tag,
             " (degraded/paragraph fallback)" if structured.degraded else "")


# --------------------------------------------------------------------------- #
# Loop
# --------------------------------------------------------------------------- #

async def _force_job_dead(job_id: str) -> None:
    """Last-resort: force a job to DEAD via a fresh session so it can never stay
    stuck in PROCESSING when the main session is broken."""
    try:
        async with db.session() as s:
            await s.execute(
                update(db.JobRow)
                .where(db.JobRow.id == job_id)
                .values(state=JobState.DEAD.value, finished_at=_utcnow())
            )
            await s.commit()
        log.warning("job %s: forced to DEAD state via recovery session", job_id)
    except Exception:
        log.error("job %s: could not force DEAD state; job will stay stuck in PROCESSING", job_id)


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
                job_id = job.id
                card_id = job.card_id
                try:
                    await asyncio.wait_for(
                        _run_job(session, job),
                        timeout=settings.job_timeout_seconds,
                    )
                except asyncio.TimeoutError as e:
                    await session.rollback()
                    try:
                        await _fail(
                            session, card_id, job, FailureReason.TIMEOUT, f"job timed out: {e}"
                        )
                    except Exception:
                        await _force_job_dead(job_id)
                    events.publish(card_id, "failed", "failed", "Timed out",
                                   FailureReason.TIMEOUT.value)
                except Exception as e:  # noqa: BLE001 — pipeline must never crash the loop
                    try:
                        await session.rollback()
                    except Exception:
                        log.warning("job %s: session rollback failed after error", job_id)
                    log.exception("job %s failed: %s", job_id, str(e))
                    try:
                        await _fail(session, card_id, job, FailureReason.UNAVAILABLE, str(e))
                    except Exception:
                        await _force_job_dead(job_id)
        except Exception:  # noqa: BLE001
            log.exception("worker loop iteration error")
            await asyncio.sleep(settings.worker_poll_seconds)
    log.info("worker loop stopped")


def stop_worker() -> None:
    _stop.set()


def reset_stop() -> None:
    _stop.clear()
