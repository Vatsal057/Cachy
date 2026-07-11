"""Media storage — HF Dataset repo only (no local persistence).

Per-job scratch dirs live under the OS temp directory and are nuked after each
job completes. Thumbnails and keyframes are uploaded to HF Dataset; if upload
fails or HF is not configured the card simply has no thumbnail (None). Nothing
is kept on the machine running the backend."""

from __future__ import annotations

import logging
import os
import shutil
import tempfile
from pathlib import Path

from app.config import get_settings

log = logging.getLogger(__name__)


def job_dir_for_card(card_id: str) -> str:
    """OS temp scratch dir for one card's job (download + extraction).
    Cleaned up after upload; same path returned on repeated calls within a job."""
    path = os.path.join(tempfile.gettempdir(), "cachy_" + card_id)
    os.makedirs(path, exist_ok=True)
    return path


def to_media_url(path: str | None) -> str | None:
    """Normalise a stored media ref to the owner-checked proxy path.

    Media now streams through `GET /media/{card_id}/{filename}` (auth-gated) so
    the HF dataset can stay private. This maps every historical storage shape to
    that scheme:
    - `/media/...` proxy paths pass through unchanged (new scheme).
    - Legacy absolute HF dataset URLs are rewritten to the proxy path so they
      still resolve after the repo goes private.
    - Other external image URLs (non-HF) pass through untouched.
    - Legacy local scratch paths like `/tmp/cachy_<card_id>/thumb.jpg` are
      rebuilt into the proxy path from the embedded card_id.
    - Returns None when the path can't be resolved."""
    if not path:
        return None
    if path.startswith("/media/"):
        return path
    if path.startswith("http://") or path.startswith("https://"):
        marker = "/resolve/main/media/"
        if "huggingface.co/datasets/" in path and marker in path:
            return "/media/" + path.split(marker, 1)[1]
        return path
    # Legacy local path like /tmp/cachy_<card_id>/thumb.jpg
    parts = path.replace("\\", "/").split("/")
    card_id = next(
        (p[len("cachy_"):] for p in parts if p.startswith("cachy_")), None
    )
    if card_id:
        return f"/media/{card_id}/{Path(path).name}"
    return None


def remove_path(path: str | None) -> None:
    """Delete a file or directory, silently ignoring errors."""
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
    """Delete a card's scratch dir plus any explicit paths (called on card deletion)."""
    remove_path(job_dir_for_card(card_id))
    for p in paths:
        remove_path(p)


# --------------------------------------------------------------------------- #
# HF Dataset media upload (free, no credit card)
# --------------------------------------------------------------------------- #

def upload_file(local_path: str, card_id: str) -> str | None:
    """Upload a local media file to the HF Dataset media repo and return its public URL.

    Returns None if HF media is not configured or upload fails — caller treats
    this as no thumbnail rather than keeping a local copy."""
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
        # Store the owner-checked proxy path, not the raw HF URL — the client
        # fetches media through GET /media/{card_id}/{filename} (auth-gated).
        return f"/media/{card_id}/{Path(local_path).name}"
    except Exception as exc:
        log.warning("HF media upload failed for %s: %s", local_path, exc)
        return None
