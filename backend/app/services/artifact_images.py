"""Free, keyless thumbnail lookup for catalog artifacts (docs/12).

Free-first: every source here is a public API with no key and no
quota worth budgeting — iTunes Search (movies/podcasts/music/tv), Open Library
(books), Wikipedia REST (everything else). Best-effort by design: any miss,
timeout, or error returns None and the catalog simply shows a placeholder.

The returned value is a remote https URL (hotlinked) — nothing is downloaded or
stored, which fits the ephemeral free-tier filesystem.
"""

from __future__ import annotations

import logging
from urllib.parse import quote

import httpx

from app.models.artifact import Artifact, ArtifactType

log = logging.getLogger("services.artifact_images")

_TIMEOUT = httpx.Timeout(6.0)
_HEADERS = {"User-Agent": "Cachy/0.1 (catalog thumbnail lookup)"}

# iTunes Search `entity` per artifact type (covers most media).
_ITUNES_ENTITY: dict[ArtifactType, str] = {
    ArtifactType.MOVIE: "movie",
    ArtifactType.TV_SHOW: "tvShow",
    ArtifactType.PODCAST: "podcast",
    ArtifactType.MUSIC: "album",
    ArtifactType.APP: "software",
}


def resolve_thumbnail(artifact: Artifact) -> str | None:
    """Route by type to a free image source. Returns a remote URL or None."""
    try:
        if artifact.type == ArtifactType.BOOK:
            return _from_open_library(artifact) or _from_wikipedia(artifact)
        if artifact.type in _ITUNES_ENTITY:
            return _from_itunes(artifact) or _from_wikipedia(artifact)
        # product / place / other -> Wikipedia is the best free generic source.
        return _from_wikipedia(artifact)
    except Exception as e:  # noqa: BLE001 — thumbnail lookup must never break a card
        log.info("thumbnail lookup failed for %r: %s", artifact.title, e)
        return None


def _query(artifact: Artifact) -> str:
    parts = [artifact.title]
    if artifact.creator:
        parts.append(artifact.creator)
    return " ".join(parts)


def _from_itunes(artifact: Artifact) -> str | None:
    entity = _ITUNES_ENTITY[artifact.type]
    params = {"term": _query(artifact), "entity": entity, "limit": 1}
    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        resp = client.get("https://itunes.apple.com/search", params=params)
        resp.raise_for_status()
        results = resp.json().get("results") or []
    if not results:
        return None
    art = results[0].get("artworkUrl100")
    if not art:
        return None
    # Upscale the 100px thumbnail iTunes returns to a crisper catalog cover.
    return art.replace("100x100bb", "400x400bb")


def _from_open_library(artifact: Artifact) -> str | None:
    params = {"title": artifact.title, "limit": 1}
    if artifact.creator:
        params["author"] = artifact.creator
    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        resp = client.get("https://openlibrary.org/search.json", params=params)
        resp.raise_for_status()
        docs = resp.json().get("docs") or []
    if not docs:
        return None
    cover_id = docs[0].get("cover_i")
    if cover_id:
        return f"https://covers.openlibrary.org/b/id/{cover_id}-L.jpg"
    isbns = docs[0].get("isbn") or []
    if isbns:
        return f"https://covers.openlibrary.org/b/isbn/{isbns[0]}-L.jpg"
    return None


def _from_wikipedia(artifact: Artifact) -> str | None:
    title = quote(artifact.title.replace(" ", "_"))
    url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{title}"
    with httpx.Client(
        timeout=_TIMEOUT, headers=_HEADERS, follow_redirects=True
    ) as client:
        resp = client.get(url)
        if resp.status_code != 200:
            return None
        data = resp.json()
    thumb = data.get("thumbnail") or {}
    return thumb.get("source")
