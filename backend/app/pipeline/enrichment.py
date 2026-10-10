"""Web enrichment (SerpApi): the "go further" layer for every card.

After structuring, the card's one-liner + top tags become a web-search query.
SerpApi (Google engine) returns the top live sources on the topic, stored on
the card as a "related sources" layer the app can render.

Same discipline as insight/embeddings: best-effort and isolated. No API key,
a network hiccup, an API error, or an empty result set yields None — never a
failed card. Free SerpApi tier is 250 searches/month; one card costs one
search."""

from __future__ import annotations

import asyncio
import logging

import requests

from app.config import get_settings

log = logging.getLogger("pipeline.enrichment")

_SERPAPI_URL = "https://serpapi.com/search.json"
_MAX_SOURCES = 5
_TIMEOUT_SECONDS = 20


def _build_query(one_liner: str, tldr: str, tags: list[str]) -> str:
    """A tight search query from the card's own words. One-liner carries the
    topic; up to two tags sharpen it."""
    parts: list[str] = []
    if one_liner and one_liner.strip():
        parts.append(one_liner.strip())
    for tag in (tags or [])[:2]:
        if isinstance(tag, str) and tag.strip():
            parts.append(tag.strip())
    return " ".join(parts)[:200].strip()


def _clean_sources(data: dict) -> list[dict]:
    """Validate organic results into {title, link, snippet, source} dicts.
    Drops anything without a title+link; dedupes by URL; caps the count."""
    out: list[dict] = []
    seen: set[str] = set()
    results = data.get("organic_results") or []
    if not isinstance(results, list):
        return out
    for item in results:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "").strip()
        link = str(item.get("link") or "").strip()
        if not title or not link or link in seen:
            continue
        seen.add(link)
        out.append(
            {
                "title": title[:200],
                "link": link,
                "snippet": str(item.get("snippet") or "").strip()[:400],
                "source": str(item.get("source") or "").strip()[:100],
            }
        )
        if len(out) >= _MAX_SOURCES:
            break
    return out


def enrich(one_liner: str, tldr: str, tags: list[str]) -> dict | None:
    """Fetch live web sources for the card's topic. Returns
    {"query": str, "sources": [...]} or None when the step should be skipped.
    Never raises — the caller treats None as "no enrichment layer"."""
    settings = get_settings()
    if not settings.serpapi_enabled:
        return None
    query = _build_query(one_liner, tldr, tags)
    if not query:
        return None
    try:
        resp = requests.get(
            _SERPAPI_URL,
            params={
                "engine": "google",
                "q": query,
                "api_key": settings.serpapi_api_key.strip(),
                "num": _MAX_SOURCES,
            },
            timeout=_TIMEOUT_SECONDS,
        )
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:  # noqa: BLE001 — network/API failure -> no layer
        log.warning("enrichment: SerpApi request failed: %s", e)
        return None
    if not isinstance(data, dict):
        return None
    if data.get("error"):
        log.warning("enrichment: SerpApi error: %s", data["error"])
        return None
    sources = _clean_sources(data)
    if not sources:
        log.info("enrichment: no usable sources for query %r", query)
        return None
    return {"query": query, "sources": sources}


async def enrich_async(one_liner: str, tldr: str, tags: list[str]) -> dict | None:
    return await asyncio.to_thread(enrich, one_liner, tldr, tags)
