"""
downloader.py — ingestion layer for the reel-to-knowledge pipeline.

Wraps the keyless resolver cascade (your existing file, kept as `resolvers.py`)
behind a clean, async-friendly interface for the FastAPI backend.

Design intent:
- Resolver internals in resolvers.py are intentionally LEFT UNTOUCHED. They are
  fragile by nature (exact headers, magic strings, HTML scraping) and the cascade
  exists precisely so that when one breaks, the next is tried.
- This module only adds the things the app needs around them: structured results,
  logging, per-job isolation, a single ordered cascade, and an async entry point
  so the blocking work never stalls the event loop.

To wire up:
1. Rename your current downloader file to `resolvers.py` (keep it as-is).
2. Remove its old `download_content` and `download_video` functions — this module
   replaces them. The `_download_*` resolver functions stay exactly as they are.
3. (Optional) swap the `print(...)` calls in resolvers.py for a module logger.
"""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from dataclasses import dataclass, field
from typing import Callable, Literal, Optional, Union

import resolvers  # your existing resolver functions, unchanged

log = logging.getLogger("ingestion.downloader")

MediaType = Literal["video", "images"]


# --------------------------------------------------------------------------- #
# Config & result types
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class DownloaderConfig:
    """Per-deployment settings. rapidapi_key is optional and read from env."""
    output_dir: str = "downloads"
    cookies_path: Optional[str] = None
    rapidapi_key: str = field(
        default_factory=lambda: os.getenv("RAPIDAPI_KEY", "").strip()
    )


@dataclass
class DownloadResult:
    """What the pipeline's extraction stage consumes next."""
    media_type: MediaType            # "video" or "images"
    data: Union[str, list[str]]      # path to .mp4, OR list of image paths
    caption: str                     # may be empty; OCR/transcript compensates
    resolver: str                    # which strategy succeeded (for observability)


class DownloadError(RuntimeError):
    """Raised when every resolver in the cascade fails — an expected outcome."""


# --------------------------------------------------------------------------- #
# Cascade definition
# --------------------------------------------------------------------------- #

def _keyless_resolvers() -> list[tuple[str, Callable]]:
    """
    Free, keyless resolvers, tried in order. Each is (name, fn) where fn has the
    signature (url, output_path) -> (path, caption) | None. Order preserved from
    the original cascade.
    """
    return [
        ("vidssave",     resolvers._download_vidssave),
        ("savethevideo", resolvers._download_savethevideo),
        ("saveig",       resolvers._download_saveig),
        ("downloadgram", resolvers._download_downloadgram),
        ("anyvidsave",   resolvers._download_anyvidsave),
        ("igreelsdl",    resolvers._download_igreelsdl),
    ]


# --------------------------------------------------------------------------- #
# Orchestration (sync core)
# --------------------------------------------------------------------------- #

def download_content(url: str, config: DownloaderConfig | None = None) -> DownloadResult:
    """
    Run the full cascade for a single URL and return a structured result.

    Each call gets an isolated job directory so concurrent workers don't clobber
    each other's media files.

    Raises DownloadError if nothing in the cascade succeeds.
    """
    config = config or DownloaderConfig()

    # Per-job isolation: unique dir per call so concurrent downloads never collide.
    job_dir = os.path.join(config.output_dir, uuid.uuid4().hex)
    os.makedirs(job_dir, exist_ok=True)
    output_path = os.path.join(job_dir, "video.mp4")

    # 1) Keyless resolvers — free, fragile, ordered. A raised exception in one
    #    must not abort the cascade; it just moves to the next.
    for name, fn in _keyless_resolvers():
        log.debug("trying keyless resolver: %s", name)
        res = _safe_call(name, lambda: fn(url, output_path))
        if res:
            path, caption = res
            log.info("download ok via %s", name)
            return DownloadResult("video", path, caption, name)

    # 2) RapidAPI — optional, only if a key is configured.
    if config.rapidapi_key:
        log.debug("trying rapidapi")
        res = _safe_call(
            "rapidapi",
            lambda: resolvers._download_rapidapi(url, output_path, config.rapidapi_key),
        )
        if res:
            path, caption = res
            log.info("download ok via rapidapi")
            return DownloadResult("video", path, caption, "rapidapi")

    # 3) yt-dlp — local fallback for videos/reels.
    log.debug("trying yt-dlp")
    res = _safe_call(
        "yt-dlp",
        lambda: resolvers._download_yt_dlp(url, output_path, config.cookies_path),
    )
    if res:
        path, caption = res
        log.info("download ok via yt-dlp")
        return DownloadResult("video", path, caption, "yt-dlp")

    # 4) Instaloader — local fallback for Instagram carousels/images.
    #    NOTE: resolvers._download_instaloader writes to a shared "temp_images"
    #    dir and is NOT concurrency-safe. Fine for single-worker dev; flagged
    #    for a later fix before running parallel workers.
    if "instagram.com" in url:
        log.debug("trying instaloader")
        res = _safe_call("instaloader", lambda: resolvers._download_instaloader(url))
        if res:
            paths, caption = res
            log.info("download ok via instaloader (%d images)", len(paths))
            return DownloadResult("images", paths, caption, "instaloader")

    raise DownloadError(f"all resolvers failed for {url}")


def _safe_call(name: str, fn: Callable):
    """Run a resolver, swallow + log any exception so the cascade continues."""
    try:
        return fn()
    except Exception:
        log.exception("resolver %s raised; continuing cascade", name)
        return None


# --------------------------------------------------------------------------- #
# Async entry point (what the FastAPI worker calls)
# --------------------------------------------------------------------------- #

async def download_content_async(
    url: str, config: DownloaderConfig | None = None
) -> DownloadResult:
    """
    Async-safe entry point. The cascade is blocking (requests + yt-dlp +
    instaloader), so it runs in a worker thread to avoid stalling the event loop.
    """
    return await asyncio.to_thread(download_content, url, config)
