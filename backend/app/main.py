"""FastAPI app: router registration + in-process worker lifecycle (docs/05).

The worker runs as a background task in the same container — the simplest fit for
a single free HF Space (no Redis to host)."""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app import discovery
from app.config import get_settings
from app.api import auth_routes, cards, catalog, collections, concepts, connections, feed, graph, library_chat, me, media, search
from app.logging_config import configure_logging
from app.models.card import SCHEMA_VERSION
from app.pipeline import worker
from app.store import db

# Apply at import time (catches logs before lifespan runs).
configure_logging()
log = logging.getLogger("app.main")

_worker_task: asyncio.Task | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _worker_task
    # Re-apply after uvicorn has configured its own handlers so our format wins.
    configure_logging()
    await db.init_db()
    async with db.session() as s:
        reset_count = await db.reset_orphaned_processing_jobs(s)
        if reset_count > 0:
            log.info("reset %d orphaned job(s) from processing to queued", reset_count)
    worker.reset_stop()
    _worker_task = asyncio.create_task(worker.run_worker_loop())
    discovery_transport = await discovery.start_discovery()
    log.info("startup complete; worker running")
    try:
        yield
    finally:
        if discovery_transport is not None:
            discovery_transport.close()
        worker.stop_worker()
        if _worker_task is not None:
            _worker_task.cancel()
            try:
                await _worker_task
            except asyncio.CancelledError:
                pass
        await db.dispose_db()
        log.info("shutdown complete")


app = FastAPI(title="Cachy", version="0.1.0", lifespan=lifespan)


async def require_admin(x_admin_token: str | None = Header(None)) -> None:
    """Gate for owner-only endpoints; unset ADMIN_TOKEN disables them entirely."""
    import hmac

    expected = get_settings().admin_token
    if not expected or not x_admin_token or not hmac.compare_digest(
        x_admin_token, expected
    ):
        raise HTTPException(status_code=401, detail="admin token required")


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    import traceback

    tb = traceback.format_exc()
    log.error("Unhandled exception on %s %s:\n%s", request.method, request.url, tb)
    # Never leak exception text or tracebacks to callers — logs only.
    return JSONResponse(status_code=500, content={"detail": "internal error"})


# CORS: set CORS_ORIGINS (comma-separated) to the real web origins in deployment;
# defaults to the local dev origin.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in get_settings().cors_origins.split(",") if o.strip()]
    or ["http://localhost:8000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(cards.router)
app.include_router(catalog.router)
app.include_router(collections.router)
app.include_router(concepts.router)
app.include_router(library_chat.router)
app.include_router(search.router)
app.include_router(graph.router)
app.include_router(feed.router)
app.include_router(connections.router)
app.include_router(me.router)
app.include_router(media.router)
app.include_router(auth_routes.router)

# Media is persisted to HF Dataset (no local static mount — nothing stored on disk).


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "schema_version": SCHEMA_VERSION}


@app.get("/admin/stats", dependencies=[Depends(require_admin)])
async def admin_stats() -> dict:
    """Owner and card counts across all users."""
    from sqlalchemy import func, select
    from app.store.db import CardRow, session as db_session
    async with db_session() as s:
        rows = (
            await s.execute(
                select(CardRow.owner_id, func.count().label("cards"))
                .group_by(CardRow.owner_id)
                .order_by(func.count().desc())
            )
        ).all()
    users = [{"owner": r[0] or "(anonymous)", "cards": r[1]} for r in rows]
    return {"total_users": len(users), "users": users}


@app.get("/debug/jobs", dependencies=[Depends(require_admin)])
async def debug_jobs() -> dict:
    from sqlalchemy import select
    from app.store.db import JobRow, session as db_session

    async with db_session() as s:
        jobs = (
            await s.execute(
                select(JobRow).order_by(JobRow.created_at.desc()).limit(20)
            )
        ).scalars().all()
    return {
        "jobs": [
            {
                "id": j.id,
                "card_id": j.card_id,
                "state": j.state,
                "attempts": j.attempts,
                "last_error": j.last_error,
                "created_at": str(j.created_at),
                "started_at": str(j.started_at),
                "finished_at": str(j.finished_at),
            }
            for j in jobs
        ]
    }


@app.post("/debug/kill_stuck", dependencies=[Depends(require_admin)])
async def kill_stuck() -> dict:
    import asyncio
    from sqlalchemy import update
    from app.store.db import JobRow, JobState, session as db_session
    from datetime import datetime, timezone
    global _worker_task

    async with db_session() as s:
        res = await s.execute(
            update(JobRow)
            .where(JobRow.state == JobState.PROCESSING.value)
            .values(state=JobState.DEAD.value, finished_at=datetime.now(timezone.utc), last_error="Killed via debug endpoint")
        )
        await s.commit()

    if _worker_task is not None:
        _worker_task.cancel()
    worker.reset_stop()
    _worker_task = asyncio.create_task(worker.run_worker_loop())

    return {"killed": res.rowcount, "worker_restarted": True}





# Flutter web SPA — mounted last so all API routes take priority.
# Built into ./static by the multi-stage Dockerfile.
_STATIC = "static"
if __import__("os").path.isdir(_STATIC):
    app.mount("/", StaticFiles(directory=_STATIC, html=True), name="web")
