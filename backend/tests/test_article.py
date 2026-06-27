"""Article ingestion path (docs/02): readable-text extraction for non-video
sources, routing, and the extraction-stage branch. No network — trafilatura is
stubbed."""

import json

import pytest

from app.pipeline.extraction import extract
from app.pipeline.ingestion import article, downloader
from app.pipeline.ingestion.downloader import DownloadResult
from app.pipeline.ingestion.source import platform_for_url


# --------------------------------------------------------------------------- #
# article.fetch_article
# --------------------------------------------------------------------------- #

def _stub_trafilatura(monkeypatch, *, html="<html></html>", payload=None):
    import trafilatura
    monkeypatch.setattr(trafilatura, "fetch_url", lambda url: html)
    monkeypatch.setattr(
        trafilatura, "extract",
        lambda *a, **k: (json.dumps(payload) if payload is not None else None),
    )


def test_fetch_article_extracts_fields(monkeypatch):
    _stub_trafilatura(monkeypatch, payload={
        "title": "Why Sleep Matters",
        "text": "Sleep is essential. " * 30,
        "author": "Jane Doe",
        "image": "https://img/cover.jpg",
        "sitename": "Substack",
    })
    art = article.fetch_article("https://x.substack.com/p/sleep")
    assert art is not None
    assert art.title == "Why Sleep Matters"
    assert art.author == "Jane Doe"
    assert art.image_url == "https://img/cover.jpg"
    assert art.site == "Substack"


def test_fetch_article_too_thin_returns_none(monkeypatch):
    _stub_trafilatura(monkeypatch, payload={"title": "x", "text": "too short"})
    assert article.fetch_article("https://x.com/p") is None


def test_fetch_article_handles_empty_fetch(monkeypatch):
    _stub_trafilatura(monkeypatch, html="")
    assert article.fetch_article("https://x.com/p") is None


def test_fetch_article_handles_no_extract(monkeypatch):
    _stub_trafilatura(monkeypatch, payload=None)  # extract returns None
    assert article.fetch_article("https://x.com/p") is None


# --------------------------------------------------------------------------- #
# routing
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize("url,is_video", [
    ("https://www.instagram.com/reel/abc", True),
    ("https://youtu.be/abc", True),
    ("https://www.youtube.com/shorts/abc", True),
    ("https://www.reddit.com/r/x/comments/1/title", False),
    ("https://en.wikipedia.org/wiki/Sleep", False),
    ("https://someblog.com/post", False),
])
def test_is_video_url(url, is_video):
    assert downloader._is_video_url(url) is is_video


def test_download_content_routes_article(monkeypatch):
    monkeypatch.setattr(article, "fetch_article", lambda url: article.ArticleResult(
        title="T", text="body " * 50, author="A", image_url="https://i/x.jpg",
        site="reddit",
    ))
    res = downloader.download_content("https://www.reddit.com/r/x/comments/1/t")
    assert res.media_type == "article"
    assert res.resolver == "article"
    assert res.title == "T"
    assert res.author == "A"
    assert res.image_url == "https://i/x.jpg"


def test_platform_for_url():
    assert platform_for_url("https://www.reddit.com/r/x") == "reddit"
    assert platform_for_url("https://en.wikipedia.org/wiki/X") == "wikipedia"
    assert platform_for_url("https://x.substack.com/p/y") == "substack"
    assert platform_for_url("https://www.someblog.com/post") == "someblog.com"
    assert platform_for_url("https://youtu.be/abc") == "youtube"


# --------------------------------------------------------------------------- #
# extraction branch
# --------------------------------------------------------------------------- #

def test_extract_article_branch_skips_media(tmp_path):
    download = DownloadResult(
        media_type="article", data="", caption="My Title", resolver="article",
        text="The body of the article goes here.", title="My Title",
        author="Author", image_url="https://img/lead.jpg",
    )
    result = extract(download, str(tmp_path), "reddit / article")
    assert "TITLE: My Title" in result.aggregated_text
    assert "ARTICLE TEXT: The body of the article" in result.aggregated_text
    assert result.thumbnail == "https://img/lead.jpg"  # remote, not downloaded
    assert result.keyframes == []
    assert result.had_transcript is False


def test_fetch_substack_note(monkeypatch):
    note_preloads = {
        "feedData": {
            "feedItem": {
                "comment": {
                    "name": "Thee Book Club",
                    "body": "Love letters to literature",
                    "attachments": [
                        {"type": "image", "imageUrl": "https://img/book.jpg"}
                    ],
                    "bio": "Literary publication"
                }
            }
        }
    }
    html = f'<script>window._preloads = JSON.parse("{json.dumps(json.dumps(note_preloads))[1:-1]}");</script>'
    monkeypatch.setattr("requests.get", lambda *a, **k: type("Resp", (), {"text": html, "status_code": 200})())
    
    art = article.fetch_article("https://substack.com/@user/note/c-123")
    assert art is not None
    assert art.title == "Note by Thee Book Club"
    assert "Love letters to literature" in art.text
    assert "[Attached Image: https://img/book.jpg]" in art.text
    assert art.image_url == "https://img/book.jpg"
    assert art.site == "substack"

