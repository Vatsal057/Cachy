"""downloader.py — ingestion orchestration layer (docs/02).

Wraps the keyless resolver cascade (resolvers.py, kept untouched) behind a clean,
async-friendly interface for the FastAPI worker.

Design intent:
- Resolver internals in resolvers.py are intentionally LEFT UNTOUCHED. They are
  fragile by nature and the cascade exists precisely so that when one breaks, the
  next is tried.
- This module only adds what the app needs around them: structured results,
  logging, per-job isolation, a single ordered cascade, and an async entry point
  so blocking work never stalls the event loop.

The current resolvers.py ships yt-dlp + instaloader. Older keyless scrapers
(vidssave, savethevideo, ...) are *probed* via getattr: if a future resolvers.py
defines them they slot into the front of the cascade automatically; if absent the
cascade simply falls through to yt-dlp then instaloader. So you can drop in a
richer resolvers.py later without touching this layer.
"""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from dataclasses import dataclass, field
from typing import Callable, Literal, Optional, Union

from . import article, resolvers  # resolvers unchanged; article is the text path

log = logging.getLogger("ingestion.downloader")

MediaType = Literal["video", "images", "article"]

# URLs on these hosts go to the fragile video resolver cascade; everything else
# is treated as a readable article/post (docs/02 article path).
_VIDEO_HOSTS = ("instagram.com", "youtube.com", "youtu.be")

# Optional keyless resolvers, in cascade order. Probed by name; missing ones skip.
_KEYLESS_NAMES = [
    "vidssave",
    "savethevideo",
    "saveig",
    "downloadgram",
    "anyvidsave",
    "igreelsdl",
]


# --------------------------------------------------------------------------- #
# Config & result types
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class DownloaderConfig:
    """Per-deployment settings. rapidapi_key/cookies are optional."""
    output_dir: str = "downloads"
    cookies_path: Optional[str] = None
    rapidapi_key: str = field(
        default_factory=lambda: os.getenv("RAPIDAPI_KEY", "").strip()
    )


@dataclass
class DownloadResult:
    """What the pipeline's extraction stage consumes next."""
    media_type: MediaType            # "video" | "images" | "article"
    data: Union[str, list[str]]      # path to .mp4, list of image paths, or "" for article
    caption: str                     # may be empty; OCR/transcript compensates
    resolver: str                    # which strategy succeeded (for observability)

    # Article path only (media_type == "article"): the content is text, not media.
    text: str = ""                   # extracted readable body
    title: str = ""                  # article/post title
    author: str | None = None        # byline, if any
    image_url: str | None = None     # remote lead-image URL (hotlinked, not downloaded)


class DownloadError(RuntimeError):
    """Raised when every resolver in the cascade fails — an expected outcome."""


# --------------------------------------------------------------------------- #
# Cascade helpers
# --------------------------------------------------------------------------- #

def _keyless_resolvers() -> list[tuple[str, Callable]]:
    """Resolve the optional keyless scrapers that actually exist in resolvers.py.

    Each fn has signature (url, output_path) -> (path, caption) | None.
    """
    found: list[tuple[str, Callable]] = []
    for name in _KEYLESS_NAMES:
        fn = getattr(resolvers, f"_download_{name}", None)
        if callable(fn):
            found.append((name, fn))
    return found


def _safe_call(name: str, fn: Callable):
    """Run a resolver, swallow + log any exception so the cascade continues."""
    try:
        return fn()
    except Exception:
        log.exception("resolver %s raised; continuing cascade", name)
        return None


def _is_video_url(url: str) -> bool:
    """True for the short-form video platforms handled by the resolver cascade."""
    u = url.lower()
    return any(host in u for host in _VIDEO_HOSTS)


def _article_result(url: str) -> DownloadResult | None:
    """The text path: extract a readable article. None if nothing usable."""
    art = article.fetch_article(url)
    if art is None:
        return None
    log.info("download ok via article extractor (%d chars)", len(art.text))
    return DownloadResult(
        media_type="article",
        data="",
        caption=art.title,
        resolver="article",
        text=art.text,
        title=art.title,
        author=art.author,
        image_url=art.image_url,
    )


def _yt_dlp_result(url: str, output_path: str, cookies_path: str | None) -> DownloadResult | None:
    """yt-dlp as a video safety net — it supports far more sites than the keyless
    scrapers, so it can rescue a non-video host that is actually a video page."""
    yt = getattr(resolvers, "_download_yt_dlp", None)
    if not callable(yt):
        return None
    res = _safe_call("yt-dlp", lambda: yt(url, output_path, cookies_path))
    if res:
        path, caption = res
        log.info("download ok via yt-dlp")
        return DownloadResult("video", path, caption, "yt-dlp")
    return None


# --------------------------------------------------------------------------- #
# Orchestration (sync core)
# --------------------------------------------------------------------------- #

def download_content(
    url: str, config: DownloaderConfig | None = None
) -> DownloadResult:
    """Run the full cascade for a single URL and return a structured result.

    Each call gets an isolated job directory so concurrent workers don't clobber
    each other's media files. Raises DownloadError if nothing succeeds.
    """
    config = config or DownloaderConfig()

    # Article path: non-video hosts carry readable text, not media. Try text
    # extraction first; if it yields nothing, fall through to yt-dlp in case the
    # page is actually a video the cascade can handle (docs/02 article path).
    if not _is_video_url(url):
        art = _article_result(url)
        if art is not None:
            return art
        job_dir = os.path.join(config.output_dir, uuid.uuid4().hex)
        os.makedirs(job_dir, exist_ok=True)
        yt = _yt_dlp_result(
            url, os.path.join(job_dir, "video.mp4"), config.cookies_path
        )
        if yt is not None:
            return yt
        raise DownloadError(f"no article or video extracted for {url}")

    # Per-job isolation: unique dir per call so concurrent downloads never collide.
    job_dir = os.path.join(config.output_dir, uuid.uuid4().hex)
    os.makedirs(job_dir, exist_ok=True)
    output_path = os.path.join(job_dir, "video.mp4")

    # 1) Optional keyless resolvers & RapidAPI — free, fragile, ordered (Instagram only).
    if "instagram.com" in url:
        for name, fn in _keyless_resolvers():
            log.debug("trying keyless resolver: %s", name)
            res = _safe_call(name, lambda fn=fn: fn(url, output_path))
            if res:
                if len(res) == 3:
                    m_type, path_or_list, caption = res
                else:
                    path_or_list, caption = res
                    m_type = "video"
                log.info("download ok via %s", name)
                return DownloadResult(m_type, path_or_list, caption, name)

        rapid = getattr(resolvers, "_download_rapidapi", None)
        if config.rapidapi_key and callable(rapid):
            log.debug("trying rapidapi")
            res = _safe_call(
                "rapidapi",
                lambda: rapid(url, output_path, config.rapidapi_key),
            )
            if res:
                if len(res) == 3:
                    m_type, path_or_list, caption = res
                else:
                    path_or_list, caption = res
                    m_type = "video"
                log.info("download ok via rapidapi")
                return DownloadResult(m_type, path_or_list, caption, "rapidapi")

    # 3) yt-dlp — local fallback for videos/reels.
    yt = getattr(resolvers, "_download_yt_dlp", None)
    if callable(yt):
        log.debug("trying yt-dlp")
        res = _safe_call(
            "yt-dlp", lambda: yt(url, output_path, config.cookies_path)
        )
        if res:
            path, caption = res
            log.info("download ok via yt-dlp")
            return DownloadResult("video", path, caption, "yt-dlp")

    # 4) Instaloader — local fallback for Instagram carousels/images.
    #    NOTE: resolvers._download_instaloader writes to a shared "temp_images"
    #    dir and is NOT concurrency-safe. Fine for single-worker dev; flagged for
    #    a later fix before running parallel workers (docs/02).
    insta = getattr(resolvers, "_download_instaloader", None)
    if "instagram.com" in url and callable(insta):
        log.debug("trying instaloader")
        res = _safe_call("instaloader", lambda: insta(url))
        if res:
            paths, caption = res
            log.info("download ok via instaloader (%d images)", len(paths))
            return DownloadResult("images", paths, caption, "instaloader")

    raise DownloadError(f"all resolvers failed for {url}")


# --------------------------------------------------------------------------- #
# Async entry point (what the FastAPI worker calls)
# --------------------------------------------------------------------------- #

async def download_content_async(
    url: str, config: DownloaderConfig | None = None
) -> DownloadResult:
    """Async-safe entry point. The cascade is blocking (requests + yt-dlp +
    instaloader), so it runs in a worker thread to avoid stalling the event loop.
    """
    return await asyncio.to_thread(download_content, url, config)
