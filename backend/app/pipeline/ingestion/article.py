"""article.py — readable-text ingestion for non-video sources (docs/02).

A parallel path to the resolver cascade: for URLs that are articles/posts rather
than short-form video (Reddit, Wikipedia, Substack, blogs, news, …), there is no
media to download — the content *is* text. This module fetches the page and
extracts the main readable body, title, author, and a lead image.

Free-first (CLAUDE.md): trafilatura is a keyless, local extractor — no API, no
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

log = logging.getLogger("ingestion.article")

# A body shorter than this is almost certainly a paywall/login wall or a failed
# extraction, not a real article — reject so the caller can fall through.
_MIN_CHARS = 200


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

    try:
        downloaded = trafilatura.fetch_url(url)
        if not downloaded:
            log.info("article fetch returned nothing for %s", url)
            return None
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
