"""Owner-checked media proxy: 401 anon, 404 non-owned, 200 owned + bytes."""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.store import db


async def _make_card(owner_id: str) -> str:
    """Insert a minimal card owned by ``owner_id``; return its id."""
    async with db.session() as s:
        row = db.CardRow(source_url="http://example.com/x", owner_id=owner_id)
        s.add(row)
        await s.commit()
        return row.id


def test_to_media_url_normalisation() -> None:
    """Every historical storage shape maps to the /media proxy path."""
    from app.store.media import to_media_url

    assert to_media_url(None) is None
    # New scheme passes through.
    assert to_media_url("/media/abc/thumb.jpg") == "/media/abc/thumb.jpg"
    # Legacy absolute HF URL -> proxy path (survives the repo going private).
    legacy = (
        "https://huggingface.co/datasets/Vatxzz/cachy-media/resolve/main/"
        "media/abc/thumb.jpg"
    )
    assert to_media_url(legacy) == "/media/abc/thumb.jpg"
    # Non-HF external image is left alone.
    assert to_media_url("https://example.com/pic.png") == "https://example.com/pic.png"
    # Legacy local scratch path -> proxy path.
    assert to_media_url("/tmp/cachy_abc/thumb.jpg") == "/media/abc/thumb.jpg"


async def test_media_anonymous_401(client) -> None:
    """No verified identity -> rejected (401 bad token / 503 auth unconfigured)."""
    from app.auth import get_owner
    from app.main import app

    card_id = await _make_card("uid-a")
    del app.dependency_overrides[get_owner]
    resp = await client.get(f"/media/{card_id}/thumb.jpg")
    assert resp.status_code in (401, 503)


async def test_media_non_owner_404(client) -> None:
    """A card owned by someone else is invisible — 404, never another's media."""
    from app.auth import get_owner
    from app.main import app

    card_id = await _make_card("uid-a")
    app.dependency_overrides[get_owner] = lambda: "uid-b"
    resp = await client.get(f"/media/{card_id}/thumb.jpg")
    assert resp.status_code == 404


async def test_media_owner_200(client, monkeypatch, tmp_path) -> None:
    """The owner gets the bytes, correct content-type, and a private cache header."""
    from app.auth import get_owner
    from app.main import app

    card_id = await _make_card("uid-a")
    app.dependency_overrides[get_owner] = lambda: "uid-a"

    # Turn HF media on and stub the download to a local fixture file.
    monkeypatch.setenv("HF_API_KEY", "hf_test")
    monkeypatch.setenv("HF_MEDIA_REPO", "acme/cachy-media")
    get_settings.cache_clear()

    fixture = tmp_path / "thumb.jpg"
    fixture.write_bytes(b"\xff\xd8\xff\xe0jpegbytes")

    import huggingface_hub

    def _fake_download(*, repo_id, repo_type, filename, token):
        assert repo_id == "acme/cachy-media"
        assert repo_type == "dataset"
        assert filename == f"media/{card_id}/thumb.jpg"
        assert token == "hf_test"
        return str(fixture)

    monkeypatch.setattr(huggingface_hub, "hf_hub_download", _fake_download)

    resp = await client.get(f"/media/{card_id}/thumb.jpg")
    assert resp.status_code == 200
    assert resp.content == b"\xff\xd8\xff\xe0jpegbytes"
    assert resp.headers["content-type"] == "image/jpeg"
    assert resp.headers["cache-control"] == "private, max-age=3600"
    get_settings.cache_clear()
