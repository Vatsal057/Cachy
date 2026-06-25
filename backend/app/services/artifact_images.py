"""Free, keyless thumbnail lookup for catalog artifacts (docs/12).

Free-first: every source here is a public API with no key and no
quota worth budgeting — iTunes Search (movies/podcasts/music/tv), Open Library
+ Google Books (books), MusicBrainz/Cover Art Archive (music), Wikidata
(places/products/movies/TV), Wikipedia REST (universal fallback). Best-effort
by design: any miss, timeout, or error returns None and the catalog shows a
placeholder.

The returned value is a remote https URL (hotlinked) — nothing is downloaded or
stored, which fits the ephemeral free-tier filesystem.
"""

from __future__ import annotations

import logging
from urllib.parse import quote

import httpx

from app.models.artifact import Artifact, ArtifactType

log = logging.getLogger("services.artifact_images")

_TIMEOUT = httpx.Timeout(8.0)
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
            return (
                _from_open_library(artifact)
                or _from_google_books(artifact)
                or _from_wikipedia(artifact)
            )
        if artifact.type == ArtifactType.MUSIC:
            return (
                _from_itunes(artifact)
                or _from_musicbrainz(artifact)
                or _from_wikipedia(artifact)
            )
        if artifact.type in _ITUNES_ENTITY:
            return (
                _from_itunes(artifact)
                or _from_wikidata(artifact)
                or _from_wikipedia(artifact)
            )
        # product / place / other
        return _from_wikidata(artifact) or _from_wikipedia(artifact)
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


def _from_google_books(artifact: Artifact) -> str | None:
    q = f"intitle:{artifact.title}"
    if artifact.creator:
        q += f"+inauthor:{artifact.creator}"
    params = {"q": q, "maxResults": 1, "fields": "items(volumeInfo/imageLinks)"}
    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        resp = client.get("https://www.googleapis.com/books/v1/volumes", params=params)
        resp.raise_for_status()
        items = resp.json().get("items") or []
    if not items:
        return None
    links = items[0].get("volumeInfo", {}).get("imageLinks", {})
    url = links.get("thumbnail") or links.get("smallThumbnail")
    if not url:
        return None
    return url.replace("zoom=1", "zoom=0").replace("http://", "https://")


def _from_musicbrainz(artifact: Artifact) -> str | None:
    query = f'release:"{artifact.title}"'
    if artifact.creator:
        query += f' artist:"{artifact.creator}"'
    params = {"query": query, "fmt": "json", "limit": 5}
    mb_headers = {**_HEADERS, "Accept": "application/json"}
    with httpx.Client(timeout=_TIMEOUT, headers=mb_headers) as client:
        resp = client.get("https://musicbrainz.org/ws/2/release", params=params)
        resp.raise_for_status()
        releases = resp.json().get("releases") or []
    for release in releases:
        mbid = release.get("id")
        if not mbid:
            continue
        try:
            with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS, follow_redirects=True) as client:
                cover = client.get(f"https://coverartarchive.org/release/{mbid}/front-500")
                if cover.status_code == 200 and "image" in cover.headers.get("content-type", ""):
                    return str(cover.url)
        except Exception:
            continue
    return None


def _from_wikidata(artifact: Artifact) -> str | None:
    search_params = {
        "action": "wbsearchentities",
        "search": _query(artifact),
        "language": "en",
        "format": "json",
        "limit": 1,
    }
    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        resp = client.get("https://www.wikidata.org/w/api.php", params=search_params)
        resp.raise_for_status()
        results = resp.json().get("search") or []
    if not results:
        return None
    qid = results[0].get("id")
    if not qid:
        return None
    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        entity_resp = client.get(f"https://www.wikidata.org/wiki/Special:EntityData/{qid}.json")
        entity_resp.raise_for_status()
        entities = entity_resp.json().get("entities", {})
    claims = entities.get(qid, {}).get("claims", {})
    p18 = claims.get("P18", [])  # P18 = image
    if not p18:
        return None
    filename = p18[0].get("mainsnak", {}).get("datavalue", {}).get("value")
    if not filename:
        return None
    encoded = filename.replace(" ", "_")
    return f"https://commons.wikimedia.org/wiki/Special:FilePath/{encoded}?width=400"
