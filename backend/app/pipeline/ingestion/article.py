"""article.py — readable-text ingestion for non-video sources (docs/02).

A parallel path to the resolver cascade: for URLs that are articles/posts rather
than short-form video (Reddit, Wikipedia, Substack, blogs, news, …), there is no
media to download — the content *is* text. This module fetches the page and
extracts the main readable body, title, author, and a lead image.

Free-first: trafilatura is a keyless, local extractor — no API, no
quota. Best-effort by design: any miss/timeout/too-thin result returns None and
the caller treats it as a normal ingestion failure (the cascade/graceful-fail
model of docs/02), never a crash.

Distinct from resolvers.py: that file is the fragile, untouched video-scraper
layer. This is new orchestration the app owns.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Optional

import requests

log = logging.getLogger("ingestion.article")

_MIN_CHARS = 200

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.5",
}


@dataclass
class ArticleResult:
    title: str
    text: str
    author: Optional[str] = None
    image_url: Optional[str] = None
    site: Optional[str] = None


def fetch_article(url: str) -> ArticleResult | None:
    """Fetch + extract a readable article from `url`. Returns None on any failure
    or if the extracted body is too thin to be a real article."""
    try:
        import trafilatura
    except Exception as e:  # noqa: BLE001 — dep missing -> article path simply unavailable
        log.warning("trafilatura unavailable; article path disabled: %s", e)
        return None

    # Reddit 403s all scrapers post-2023 — skip early, don't waste the round-trip.
    if "reddit.com" in url.lower():
        log.info("reddit url skipped (scraping blocked); url=%s", url)
        return None

    try:
        resp = requests.get(url, headers=_HEADERS, timeout=20, allow_redirects=True)
        downloaded = resp.text
        if not downloaded or len(downloaded) < _MIN_CHARS:
            log.info("article fetch empty for %s (status=%s)", url, resp.status_code)
            return None
    except Exception as e:  # noqa: BLE001
        log.info("article fetch failed for %s: %s", url, e)
        return None

    try:
        raw = trafilatura.extract(
            downloaded,
            output_format="json",
            with_metadata=True,
            favor_recall=True,
            include_comments=False,
            include_tables=True,
        )
        if not raw:
            return None
        data = json.loads(raw)
    except Exception as e:  # noqa: BLE001 — any extraction error is a normal miss
        log.info("article extraction failed for %s: %s", url, e)
        return None

    text = (data.get("text") or "").strip()
    if len(text) < _MIN_CHARS:
        log.info("article body too thin (%d chars) for %s", len(text), url)
        return None

    title = (data.get("title") or "").strip()
    author = (data.get("author") or "").strip() or None
    image_url = (data.get("image") or "").strip() or None
    site = (data.get("sitename") or data.get("hostname") or "").strip() or None

    return ArticleResult(
        title=title,
        text=text,
        author=author,
        image_url=image_url,
        site=site,
    )
