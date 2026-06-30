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
    """Return a publicly accessible URL for a media path.

    - http(s) refs pass through as-is (already an HF URL or external link).
    - Local paths reconstruct the HF Dataset URL from the card_id embedded in the
      path (handles old rows that still have a local path in the DB).
    - Returns None if no HF repo is configured or the path can't be resolved."""
    if not path:
        return None
    if path.startswith("http://") or path.startswith("https://"):
        return path
    # Reconstruct HF URL from a legacy local path like /tmp/cachy_<card_id>/thumb.jpg
    s = get_settings()
    if s.hf_media_repo:
        parts = path.replace("\\", "/").split("/")
        card_id = None
        for p in parts:
            if p.startswith("cachy_"):
                card_id = p[len("cachy_"):]
                break
        if card_id:
            filename = Path(path).name
            return f"https://huggingface.co/datasets/{s.hf_media_repo}/resolve/main/media/{card_id}/{filename}"
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
        return f"https://huggingface.co/datasets/{s.hf_media_repo}/resolve/main/{path_in_repo}"
    except Exception as exc:
        log.warning("HF media upload failed for %s: %s", local_path, exc)
        return None
