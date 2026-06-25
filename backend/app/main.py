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

from app.api import cards, search
from app.models.card import SCHEMA_VERSION
from app.pipeline import worker
from app.store import db, media

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("app.main")

_worker_task: asyncio.Task | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _worker_task
    await db.init_db()
    worker.reset_stop()
    _worker_task = asyncio.create_task(worker.run_worker_loop())
    log.info("startup complete; worker running")
    try:
        yield
    finally:
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
app.include_router(search.router)

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
