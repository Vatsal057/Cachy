"""Source-platform labelling (docs/02). One place that maps a URL to a human
platform label, shared by the API (at card creation) and the worker (for the
observability source line). Covers the video platforms and the common article
sources, with a generic host fallback so any URL gets a sensible label."""

from __future__ import annotations

from urllib.parse import urlparse

# host substring -> platform label
_KNOWN: tuple[tuple[str, str], ...] = (
    ("twitter.com", "twitter"),
    ("x.com", "twitter"),
    ("instagram.com", "instagram"),
    ("youtube.com", "youtube"),
    ("youtu.be", "youtube"),
    ("reddit.com", "reddit"),
    ("wikipedia.org", "wikipedia"),
    ("linkedin.com", "linkedin"),
    ("substack.com", "substack"),
    ("medium.com", "medium"),
)


def platform_for_url(url: str) -> str | None:
    """A platform label for `url`: a known platform, else the bare host (no
    `www.`), else None for an unparseable URL."""
    u = url.lower()
    for needle, label in _KNOWN:
        if needle in u:
            return label
    host = urlparse(url).netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    return host or None
