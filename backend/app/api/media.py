"""Owner-checked media proxy.

Thumbnails and keyframes live in a private HF Dataset repo (only you see your
cards). Clients can't fetch the raw HF URL anymore; they go through this
endpoint, which verifies the caller owns the card, then streams the bytes from
HF using the server-side token.
"""

from __future__ import annotations

import logging
import mimetypes
from typing import Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.auth import OwnerDep
from app.config import get_settings
from app.store import db

log = logging.getLogger(__name__)

router = APIRouter(prefix="/media", tags=["media"])


@router.get("/{card_id}/{filename}")
async def get_media(card_id: str, filename: str, owner_id: OwnerDep) -> Any:
    """Stream one media file for a card the caller owns.

    404 for unknown or non-owned cards (never reveal another owner's media);
    401 falls out of [OwnerDep] for anonymous callers.
    """
    async with db.session() as s:
        row = await db.get_card_row(s, card_id)
    if row is None or row.owner_id != owner_id:
        raise HTTPException(status_code=404, detail="not found")

    settings = get_settings()
    if not settings.hf_media_enabled:
        raise HTTPException(status_code=404, detail="media not configured")

    from huggingface_hub import hf_hub_download
    from huggingface_hub.utils import EntryNotFoundError

    try:
        local_path = hf_hub_download(
            repo_id=settings.hf_media_repo,
            repo_type="dataset",
            filename=f"media/{card_id}/{filename}",
            token=settings.hf_api_key,
        )
    except EntryNotFoundError:
        raise HTTPException(status_code=404, detail="not found")
    except Exception as exc:  # network / auth / gone — treat as absent, log the cause
        log.warning("media fetch failed for %s/%s: %s", card_id, filename, exc)
        raise HTTPException(status_code=404, detail="not found")

    content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    return FileResponse(
        local_path,
        media_type=content_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )
