"""Media file storage — local disk (dev) or Cloudflare R2 (production).

Per-job isolated directories so concurrent workers never collide (docs/01, docs/02).
Keyframes + thumbnail are kept; the source video may be discarded after extraction
(docs/11). When R2 is configured, upload_file() returns a persistent public URL and
the caller is responsible for deleting the local temp file afterward."""

from __future__ import annotations

import logging
import os
import shutil
import uuid
from pathlib import Path

from app.config import get_settings

log = logging.getLogger(__name__)


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
    abs_path = os.path.abspath(path)
    rel = os.path.relpath(abs_path, os.path.abspath(media_root()))
    if not (rel.startswith(os.pardir) or os.path.isabs(rel)):
        return MEDIA_URL_PREFIX + "/" + rel.replace(os.sep, "/")

    # If path is outside local media_root() (e.g., /data/downloads/... from cloud DB),
    # fallback to cloud server repo (HF Dataset media storage)
    s = get_settings()
    if s.hf_media_repo:
        parts = path.replace("\\", "/").split("/")
        card_id = None
        for p in parts:
            if p.startswith("card_"):
                card_id = p[len("card_"):]
                break
        if card_id:
            filename = Path(path).name
            return f"https://huggingface.co/datasets/{s.hf_media_repo}/resolve/main/media/{card_id}/{filename}"

    return None


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


# --------------------------------------------------------------------------- #
# HF Dataset media upload (free, no credit card)
# --------------------------------------------------------------------------- #

def upload_file(local_path: str, card_id: str) -> str | None:
    """Upload a local media file to the HF Dataset media repo and return its public URL.

    Returns None if HF media is not configured or upload fails (caller keeps
    the local path as fallback). Files are grouped under media/{card_id}/."""
    s = get_settings()
    if not s.hf_media_enabled:
        return None
    from huggingface_hub import HfApi
    path_in_repo = f"media/{card_id}/{Path(local_path).name}"
    try:
        HfApi(token=s.hf_api_key).upload_file(
            path_or_fileobj=local_path,
            path_in_repo=path_in_repo,
            repo_id=s.hf_media_repo,
            repo_type="dataset",
            commit_message="media upload",
        )
        return f"https://huggingface.co/datasets/{s.hf_media_repo}/resolve/main/{path_in_repo}"
    except Exception as exc:
        log.warning("HF media upload failed for %s: %s", local_path, exc)
        return None
