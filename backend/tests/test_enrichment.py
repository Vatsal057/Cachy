"""Tests for the SerpApi web-enrichment step.

The contract under test: enrichment is best-effort and isolated. No API key,
a network failure, an API error, or an empty result set must yield None —
never an exception, never a failed card."""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.pipeline import enrichment as en


def _settings(**overrides):
    base = {"serpapi_api_key": "", "serpapi_enabled": False}
    base.update(overrides)
    return SimpleNamespace(**base)


class TestBuildQuery:
    def test_combines_one_liner_and_tags(self):
        q = en._build_query("Sourdough starter basics", "", ["baking", "bread"])
        assert q == "Sourdough starter basics baking bread"

    def test_caps_at_two_tags(self):
        q = en._build_query("Topic", "", ["a", "b", "c", "d"])
        assert q == "Topic a b"

    def test_empty_without_one_liner(self):
        assert en._build_query("", "some tldr", ["tag"]) == "tag"
        assert en._build_query("", "", []) == ""

    def test_truncates_long_queries(self):
        q = en._build_query("x" * 300, "", [])
        assert len(q) <= 200


class TestCleanSources:
    def _item(self, **kw):
        base = {
            "title": "Title",
            "link": "https://example.com/1",
            "snippet": "Snippet",
            "source": "Example",
        }
        base.update(kw)
        return base

    def test_keeps_valid_results(self):
        got = en._clean_sources({"organic_results": [self._item()]})
        assert len(got) == 1
        assert got[0]["title"] == "Title"
        assert got[0]["link"] == "https://example.com/1"

    def test_drops_missing_title_or_link(self):
        got = en._clean_sources(
            {"organic_results": [self._item(title=""), self._item(link="")]}
        )
        assert got == []

    def test_dedupes_by_link(self):
        got = en._clean_sources({"organic_results": [self._item(), self._item()]})
        assert len(got) == 1

    def test_caps_at_five(self):
        items = [self._item(link=f"https://example.com/{i}") for i in range(9)]
        assert len(en._clean_sources({"organic_results": items})) == 5

    def test_tolerates_malformed_payload(self):
        assert en._clean_sources({}) == []
        assert en._clean_sources({"organic_results": "nope"}) == []
        assert en._clean_sources({"organic_results": [None, 42]}) == []


class TestEnrich:
    def test_none_without_api_key(self, monkeypatch):
        monkeypatch.setattr(en, "get_settings", lambda: _settings())
        assert en.enrich("Topic", "", ["tag"]) is None

    def test_none_on_network_failure(self, monkeypatch):
        monkeypatch.setattr(
            en, "get_settings", lambda: _settings(serpapi_api_key="k", serpapi_enabled=True)
        )

        def _boom(*a, **k):
            raise ConnectionError("down")

        monkeypatch.setattr(en.requests, "get", _boom)
        assert en.enrich("Topic", "", []) is None

    def test_none_on_api_error_payload(self, monkeypatch):
        monkeypatch.setattr(
            en, "get_settings", lambda: _settings(serpapi_api_key="k", serpapi_enabled=True)
        )

        class _Resp:
            def raise_for_status(self):
                pass

            def json(self):
                return {"error": "Invalid API key"}

        monkeypatch.setattr(en.requests, "get", lambda *a, **k: _Resp())
        assert en.enrich("Topic", "", []) is None

    def test_returns_sources_on_success(self, monkeypatch):
        monkeypatch.setattr(
            en, "get_settings", lambda: _settings(serpapi_api_key="k", serpapi_enabled=True)
        )

        class _Resp:
            def raise_for_status(self):
                pass

            def json(self):
                return {
                    "organic_results": [
                        {
                            "title": "T",
                            "link": "https://example.com",
                            "snippet": "S",
                            "source": "Ex",
                        }
                    ]
                }

        monkeypatch.setattr(en.requests, "get", lambda *a, **k: _Resp())
        got = en.enrich("Topic", "", [])
        assert got["query"] == "Topic"
        assert len(got["sources"]) == 1

    def test_none_when_no_usable_sources(self, monkeypatch):
        monkeypatch.setattr(
            en, "get_settings", lambda: _settings(serpapi_api_key="k", serpapi_enabled=True)
        )

        class _Resp:
            def raise_for_status(self):
                pass

            def json(self):
                return {"organic_results": []}

        monkeypatch.setattr(en.requests, "get", lambda *a, **k: _Resp())
        assert en.enrich("Topic", "", []) is None
