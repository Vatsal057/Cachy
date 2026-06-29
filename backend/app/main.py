"""FastAPI app: router registration + in-process worker lifecycle (docs/05).

The worker runs as a background task in the same container — the simplest fit for
a single free HF Space (no Redis to host)."""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app import discovery
from app.api import cards, catalog, collections, concepts, graph, library_chat, search
from app.logging_config import configure_logging
from app.models.card import SCHEMA_VERSION
from app.pipeline import worker
from app.store import db, media

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

# Dev-open CORS so the Flutter web client (Chrome) can reach the API + SSE stream
# from its own origin. Tighten to specific origins before any real deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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

# Serve extracted keyframes/thumbnails so the frontend faces load (docs/05).
# Ephemeral on HF free tier; survives only the container's life (docs/01, docs/11).
app.mount(
    media.MEDIA_URL_PREFIX,
    StaticFiles(directory=media.media_root()),
    name="media",
)


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "schema_version": SCHEMA_VERSION}


# Flutter web SPA — mounted last so all API routes take priority.
# Built into ./static by the multi-stage Dockerfile.
_STATIC = "static"
if __import__("os").path.isdir(_STATIC):
    app.mount("/", StaticFiles(directory=_STATIC, html=True), name="web")
