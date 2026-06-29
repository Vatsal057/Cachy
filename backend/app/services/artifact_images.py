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
# Wikimedia policy requires a descriptive User-Agent with a contact URL/email.
# Without this, their API returns 403. See: https://meta.wikimedia.org/wiki/User-Agent_policy
_HEADERS = {
    "User-Agent": (
        "Cachy/1.0 (personal knowledge library; "
        "https://github.com/Vatsal057/Cachy) httpx/python"
    )
}


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
                or _from_wikimedia_commons(artifact)
            )
        if artifact.type == ArtifactType.MUSIC:
            return (
                _from_itunes(artifact)
                or _from_musicbrainz(artifact)
                or _from_wikipedia(artifact)
                or _from_wikimedia_commons(artifact)
            )
        if artifact.type in _ITUNES_ENTITY:
            return (
                _from_itunes(artifact)
                or _from_wikidata(artifact)
                or _from_wikipedia(artifact)
                or _from_wikimedia_commons(artifact)
            )
        # product / place / other / software / web
        return (
            _from_wikidata(artifact)
            or _from_wikipedia(artifact)
            or _from_wikimedia_commons(artifact)
        )
    except Exception as e:  # noqa: BLE001 — thumbnail lookup must never break a card
        log.info("thumbnail lookup failed for %r: %s", artifact.title, e)
        return None


def _query(artifact: Artifact) -> str:
    parts = [artifact.title]
    if artifact.creator:
        parts.append(artifact.creator)
    return " ".join(parts)


def _queries(artifact: Artifact) -> list[str]:
    qs = []
    full = _query(artifact)
    qs.append(full)
    if artifact.creator and artifact.title != full:
        qs.append(artifact.title)
    return qs


def _words_overlap(query: str, title: str) -> bool:
    """Return True if at least one significant word (>3 chars) from the query
    appears in the matched Wikipedia article title (case-insensitive).
    Prevents clearly wrong fuzzy matches (e.g. 'SkyKit Learn' -> 'A Discovery of Witches').
    """
    q_words = {w.lower() for w in query.split() if len(w) > 3}
    t_lower = title.lower()
    return any(w in t_lower for w in q_words)


def _from_itunes(artifact: Artifact) -> str | None:
    entity = _ITUNES_ENTITY[artifact.type]
    for query in _queries(artifact):
        params = {"term": query, "entity": entity, "limit": 1}
        with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
            resp = client.get("https://itunes.apple.com/search", params=params)
            resp.raise_for_status()
            results = resp.json().get("results") or []
        if results:
            art = results[0].get("artworkUrl100")
            if art:
                return art.replace("100x100bb", "400x400bb")
    return None


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
    """Two-step fuzzy lookup: search Wikipedia first (handles typos/alt names),
    then fetch the summary of the best match to get its thumbnail."""
    for query in _queries(artifact):
        with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
            search_resp = client.get(
                "https://en.wikipedia.org/w/api.php",
                params={
                    "action": "query",
                    "list": "search",
                    "srsearch": query,
                    "format": "json",
                    "srlimit": 1,
                    "srprop": "",
                },
            )
            if search_resp.status_code != 200:
                continue
            hits = search_resp.json().get("query", {}).get("search", [])
        if not hits:
            continue
        matched_title = hits[0]["title"]
        if not _words_overlap(query, matched_title):
            continue
        page_title = quote(matched_title.replace(" ", "_"))
        with httpx.Client(
            timeout=_TIMEOUT, headers=_HEADERS, follow_redirects=True
        ) as client:
            summary_resp = client.get(
                f"https://en.wikipedia.org/api/rest_v1/page/summary/{page_title}"
            )
            if summary_resp.status_code == 200:
                thumb = summary_resp.json().get("thumbnail") or {}
                source = thumb.get("source")
                if source:
                    return source
    return None


def _from_wikimedia_commons(artifact: Artifact) -> str | None:
    """Search Wikimedia Commons directly for logos or icons."""
    for query in _queries(artifact):
        search_q = f"{query} logo"
        with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
            resp = client.get(
                "https://commons.wikimedia.org/w/api.php",
                params={
                    "action": "query",
                    "list": "search",
                    "srsearch": search_q,
                    "format": "json",
                    "srnamespace": 6,
                    "srlimit": 1,
                },
            )
            if resp.status_code != 200:
                continue
            hits = resp.json().get("query", {}).get("search", [])
        if not hits:
            continue
        matched_title = hits[0]["title"]
        if not _words_overlap(query, matched_title):
            continue
        filename = matched_title.replace("File:", "").strip()
        encoded = filename.replace(" ", "_")
        return f"https://commons.wikimedia.org/wiki/Special:FilePath/{encoded}?width=400"
    return None




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
    results = []
    for query in _queries(artifact):
        search_params = {
            "action": "wbsearchentities",
            "search": query,
            "language": "en",
            "format": "json",
            "limit": 3,
        }
        with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
            resp = client.get("https://www.wikidata.org/w/api.php", params=search_params)
            resp.raise_for_status()
            results = resp.json().get("search") or []
        if results:
            break
    if not results:
        return None

    best_fallback = None
    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        for hit in results[:3]:
            qid = hit.get("id")
            if not qid:
                continue
            try:
                entity_resp = client.get(f"https://www.wikidata.org/wiki/Special:EntityData/{qid}.json")
                entity_resp.raise_for_status()
                entities = entity_resp.json().get("entities", {})
            except Exception:
                continue
            claims = entities.get(qid, {}).get("claims", {})
            for prop in ("P154", "P18"):
                entries = claims.get(prop, [])
                if entries:
                    filename = entries[0].get("mainsnak", {}).get("datavalue", {}).get("value")
                    if filename:
                        encoded = filename.replace(" ", "_")
                        url = f"https://commons.wikimedia.org/wiki/Special:FilePath/{encoded}?width=400"
                        if prop == "P154":
                            return url
                        if not best_fallback:
                            best_fallback = url
            p856 = claims.get("P856", [])
            if p856:
                website_url = p856[0].get("mainsnak", {}).get("datavalue", {}).get("value")
                if website_url:
                    from urllib.parse import urlparse
                    domain = urlparse(website_url).netloc
                    if domain:
                        return f"https://www.google.com/s2/favicons?domain={domain}&sz=256"
    return best_fallback
