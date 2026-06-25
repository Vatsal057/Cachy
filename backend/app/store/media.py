"""Media file storage (local disk for MVP; ephemeral on HF free tier).

Per-job isolated directories so concurrent workers never collide (docs/01, docs/02).
Keyframes + thumbnail are kept; the source video may be discarded after extraction
(docs/11)."""

from __future__ import annotations

import os
import shutil
import uuid

from app.config import get_settings


def media_root() -> str:
    root = get_settings().media_dir
    os.makedirs(root, exist_ok=True)
    return root


def new_job_dir() -> str:
    """A unique directory for one ingestion+extraction job."""
    job_dir = os.path.join(media_root(), uuid.uuid4().hex)
    os.makedirs(job_dir, exist_ok=True)
    return job_dir


def job_dir_for_card(card_id: str) -> str:
    return os.path.join(media_root(), "card_" + card_id)


# URL prefix the static mount (app.main) serves media_root() under.
MEDIA_URL_PREFIX = "/media"


def to_media_url(path: str | None) -> str | None:
    """Map an on-disk media path under media_root() to a served URL.

    The DB keeps raw disk paths (deletion needs them); only the serialized Card
    carries URLs. Absolute http(s) refs pass through; paths outside media_root()
    return None so the frontend degrades to its accent face rather than 404."""
    if not path:
        return None
    if path.startswith("http://") or path.startswith("https://"):
        return path
    rel = os.path.relpath(os.path.abspath(path), os.path.abspath(media_root()))
    if rel.startswith(os.pardir) or os.path.isabs(rel):
        return None
    return MEDIA_URL_PREFIX + "/" + rel.replace(os.sep, "/")


def remove_path(path: str | None) -> None:
    if not path:
        return
    try:
        if os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
        elif os.path.exists(path):
            os.remove(path)
    except OSError:
        pass


def remove_card_media(card_id: str, paths: list[str | None]) -> None:
    """Delete a card's per-job dir plus any explicit media paths (docs/08)."""
    remove_path(job_dir_for_card(card_id))
    for p in paths:
        remove_path(p)
