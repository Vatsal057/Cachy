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
import re
import time
from dataclasses import dataclass
from html.parser import HTMLParser
from typing import Optional
from urllib.parse import urlparse, urlunparse

import requests

from app.pipeline.ingestion import net_guard

log = logging.getLogger("ingestion.article")

# Cap fetched HTML so a giant page can't exhaust memory (M5).
_MAX_HTML_BYTES = 10 * 1024 * 1024  # 10 MB

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

# Reddit requires a descriptive UA for OAuth API access.
_REDDIT_UA = "Cachy/1.0 (knowledge card app)"

# Max top-level comments to include in the card text.
_REDDIT_MAX_COMMENTS = 15

# Module-level token cache: (access_token, expires_at)
_reddit_token: tuple[str, float] | None = None


def _get_reddit_token(client_id: str, client_secret: str) -> str | None:
    """Fetch (or return cached) a Reddit client-credentials token. Valid 1 hour."""
    global _reddit_token
    if _reddit_token and time.time() < _reddit_token[1] - 60:
        return _reddit_token[0]
    try:
        resp = requests.post(
            "https://www.reddit.com/api/v1/access_token",
            auth=(client_id, client_secret),
            data={"grant_type": "client_credentials"},
            headers={"User-Agent": _REDDIT_UA},
            timeout=10,
        )
        if resp.status_code != 200:
            log.warning("reddit token fetch failed: %s", resp.status_code)
            return None
        token = resp.json().get("access_token")
        expires_in = resp.json().get("expires_in", 3600)
        _reddit_token = (token, time.time() + expires_in)
        return token
    except Exception as e:  # noqa: BLE001
        log.warning("reddit token fetch error: %s", e)
        return None


@dataclass
class ArticleResult:
    title: str
    text: str
    author: Optional[str] = None
    image_url: Optional[str] = None
    site: Optional[str] = None


def _reddit_json_url(url: str) -> str:
    """Convert any reddit.com post URL to its .json equivalent."""
    parsed = urlparse(url)
    path = parsed.path.rstrip("/") + ".json"
    return urlunparse(parsed._replace(path=path, query="", fragment=""))


def _fetch_reddit(url: str) -> ArticleResult | None:
    """Fetch a Reddit post via OAuth API (if creds set) or .json fallback."""
    from app.config import get_settings
    cfg = get_settings()
    client_id = cfg.reddit_client_id.strip()
    client_secret = cfg.reddit_client_secret.strip()

    if client_id and client_secret:
        token = _get_reddit_token(client_id, client_secret)
        if token:
            # oauth.reddit.com bypasses IP blocks that hit www.reddit.com
            json_url = _reddit_json_url(url).replace(
                "www.reddit.com", "oauth.reddit.com"
            )
            headers = {"Authorization": f"bearer {token}", "User-Agent": _REDDIT_UA}
        else:
            json_url = _reddit_json_url(url)
            headers = {"User-Agent": _REDDIT_UA}
    else:
        json_url = _reddit_json_url(url)
        headers = {"User-Agent": _REDDIT_UA}

    try:
        resp = requests.get(json_url, headers=headers, timeout=20)
        if resp.status_code != 200:
            log.info("reddit .json returned %s for %s", resp.status_code, json_url)
            return None
        data = resp.json()
    except Exception as e:  # noqa: BLE001
        log.info("reddit fetch failed for %s: %s", json_url, e)
        return None

    try:
        post = data[0]["data"]["children"][0]["data"]
        title = (post.get("title") or "").strip()
        selftext = (post.get("selftext") or "").strip()
        author = post.get("author") or None
        # selftext of "[removed]" or "[deleted]" means no body — treat as empty.
        if selftext in ("[removed]", "[deleted]"):
            selftext = ""

        comments_listing = data[1]["data"]["children"]
        comment_bodies: list[str] = []
        for child in comments_listing:
            if child.get("kind") != "t1":
                continue
            body = (child["data"].get("body") or "").strip()
            if body and body not in ("[deleted]", "[removed]"):
                comment_bodies.append(body)
            if len(comment_bodies) >= _REDDIT_MAX_COMMENTS:
                break

        parts = [title]
        if selftext:
            parts.append(selftext)
        if comment_bodies:
            parts.append("Top comments:\n\n" + "\n\n".join(comment_bodies))
        text = "\n\n".join(parts)
    except (KeyError, IndexError, TypeError) as e:
        log.info("reddit json parse failed for %s: %s", json_url, e)
        return None

    if len(text) < _MIN_CHARS:
        log.info("reddit text too thin (%d chars) for %s", len(text), json_url)
        return None

    return ArticleResult(title=title, text=text, author=author, site="reddit")


class _PTagParser(HTMLParser):
    """Extract text nodes inside <p> tags from oEmbed HTML."""
    def __init__(self) -> None:
        super().__init__()
        self._in_p = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list) -> None:  # noqa: ARG002
        if tag == "p":
            self._in_p = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "p":
            self._in_p = False

    def handle_data(self, data: str) -> None:
        if self._in_p:
            self.parts.append(data)


def _fetch_twitter(url: str) -> ArticleResult | None:
    """Fetch a tweet via Twitter's oEmbed endpoint (no auth, no rate-limit key)."""
    # oEmbed only accepts twitter.com URLs, not x.com
    oembed_url = re.sub(r"https?://(www\.)?x\.com", "https://twitter.com", url)
    try:
        resp = requests.get(
            "https://publish.twitter.com/oembed",
            params={"url": oembed_url, "omit_script": "true"},
            headers=_HEADERS,
            timeout=10,
        )
        if resp.status_code != 200:
            log.info("twitter oembed returned %s for %s", resp.status_code, url)
            return None
        data = resp.json()
    except Exception as e:  # noqa: BLE001
        log.info("twitter oembed failed for %s: %s", url, e)
        return None

    html = data.get("html") or ""
    parser = _PTagParser()
    parser.feed(html)
    text = " ".join(parser.parts).strip()

    author = data.get("author_name") or None
    # Build a minimal title from author + first ~80 chars of text.
    title = f"{author}: {text[:80]}" if author else text[:80]

    # Extract tweet ID for a stable title fallback.
    m = re.search(r"/status/(\d+)", url)
    if not title.strip() and m:
        title = f"Tweet {m.group(1)}"

    if not text:
        log.info("twitter oembed returned no text for %s", url)
        return None

    return ArticleResult(title=title, text=text, author=author, site="twitter")


def _fetch_substack(url: str, html: Optional[str] = None) -> ArticleResult | None:
    """Fetch and parse Substack posts, notes, or publications from window._preloads.

    Substack HTML embeds clean JSON metadata inside window._preloads, allowing us
    to extract posts, notes, and profile bios directly without scraping boilerplate overlays.
    """
    if html is None:
        try:
            resp = requests.get(url, headers=_HEADERS, timeout=20, allow_redirects=True)
            html = resp.text
        except Exception as e:
            log.info("substack fetch failed for %s: %s", url, e)
            return None

    m = re.search(r"window\._preloads\s*=\s*JSON\.parse\((\".*?\")\)", html)
    if not m:
        return None

    try:
        data = json.loads(json.loads(m.group(1)))
    except Exception as e:
        log.info("substack preloads json parse failed for %s: %s", url, e)
        return None

    site = "substack"

    post = data.get("post")
    if isinstance(post, dict) and post.get("title"):
        title = (post.get("title") or "").strip()
        author = None
        bylines = post.get("publishedBylines")
        if isinstance(bylines, list) and bylines:
            author = bylines[0].get("name")
        if not author:
            author = data.get("pub", {}).get("author_name") or data.get("pub", {}).get("name")

        image_url = post.get("cover_image") or post.get("social_image") or data.get("pub", {}).get("hero_image")
        body_html = post.get("body_html") or ""

        text = ""
        if body_html:
            try:
                import trafilatura
                text = trafilatura.extract("<html><body>" + body_html + "</body></html>") or ""
            except Exception as e:
                log.info("trafilatura body_html extraction failed for %s: %s", url, e)
        if not text:
            text = re.sub(r"<[^>]+>", " ", body_html)
            text = re.sub(r"\s+", " ", text).strip()

        if not text and post.get("truncated_body_text"):
            text = post.get("truncated_body_text")

        if text:
            return ArticleResult(title=title, text=text, author=author, image_url=image_url, site=site)

    fi = data.get("feedData", {}).get("feedItem", {})
    if isinstance(fi, dict) and fi:
        item = fi.get("comment") or fi.get("post") or fi
        if isinstance(item, dict):
            author = item.get("name") or item.get("handle")
            body = (item.get("body") or "").strip()
            image_url = None
            parts = []
            if author:
                parts.append(f"Substack Note by {author}:")
            if body:
                parts.append(body)
            for att in item.get("attachments", []):
                if isinstance(att, dict):
                    if att.get("type") == "image" and not image_url:
                        image_url = att.get("imageUrl")
                        parts.append(f"[Attached Image: {image_url}]")
                    elif att.get("type") == "post":
                        p_title = att.get("title") or ""
                        p_desc = att.get("description") or ""
                        parts.append(f"[Restacked Post: {p_title} - {p_desc}]")
            bio = item.get("bio")
            if bio:
                parts.append(f"Author Bio: {bio}")

            text = "\n\n".join(parts).strip()
            title = f"Note by {author}" if author else "Substack Note"
            if text or image_url:
                return ArticleResult(title=title, text=text or title, author=author, image_url=image_url, site=site)

    pub = data.get("pub")
    if isinstance(pub, dict) and pub.get("name"):
        name = (pub.get("name") or "").strip()
        author = pub.get("author_name") or pub.get("author_handle")
        bio = pub.get("author_bio") or pub.get("hero_text") or pub.get("description") or ""
        image_url = pub.get("hero_image") or pub.get("cover_photo_url") or pub.get("logo_url")

        parts = [f"Substack Publication: {name}" + (f" by {author}" if author else "")]
        if bio:
            parts.append(bio.strip())
        text = "\n\n".join(parts).strip()
        return ArticleResult(title=name, text=text, author=author, image_url=image_url, site=site)

    return None


def fetch_article(url: str) -> ArticleResult | None:
    """Fetch + extract a readable article from `url`. Returns None on any failure
    or if the extracted body is too thin to be a real article."""
    # Reject non-http(s) / private-host URLs before any fetch (N17 SSRF).
    try:
        net_guard.check_url(url)
    except net_guard.UnsafeUrlError as e:
        log.info("article fetch rejected unsafe url %s: %s", url, e)
        return None

    u = url.lower()
    if "reddit.com" in u:
        return _fetch_reddit(url)
    if "twitter.com" in u or "x.com" in u:
        return _fetch_twitter(url)

    try:
        resp = requests.get(
            url, headers=_HEADERS, timeout=20, allow_redirects=True, stream=True
        )
        # Cap the body so a giant page can't exhaust memory (M5).
        raw = net_guard.capped_content(resp, max_bytes=_MAX_HTML_BYTES)
        downloaded = raw.decode(resp.encoding or "utf-8", errors="replace")
        if not downloaded:
            log.info("article fetch empty for %s (status=%s)", url, resp.status_code)
            return None
    except net_guard.DownloadTooLargeError as e:
        log.info("article fetch too large for %s: %s", url, e)
        return None
    except Exception as e:  # noqa: BLE001
        log.info("article fetch failed for %s: %s", url, e)
        return None

    if "substack.com" in u or "window._preloads" in downloaded:
        sub = _fetch_substack(url, html=downloaded)
        if sub:
            return sub

    if len(downloaded) < _MIN_CHARS:
        log.info("article fetch too thin for %s", url)
        return None

    try:
        import trafilatura
    except Exception as e:  # noqa: BLE001 — dep missing -> article path simply unavailable
        log.warning("trafilatura unavailable; article path disabled: %s", e)
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
