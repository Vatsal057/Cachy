"""Isolated tests for the Verdict Timeline module.

No network, no SerpApi key, no LLM: every test exercises pure logic
(URL parsing, windowing, date windows, deterministic guardrails) or
monkeypatches the LLM boundary.
"""

from app.pipeline import verdicts
from app.pipeline.verdicts import (
    _cdr_window,
    _parse_pub_date,
    _registrable_domain,
    apply_verdict,
    extract_claims,
    text_to_windows,
    verify_transcript,
    video_id_from_url,
    window_segments,
)


# --------------------------------------------------------------------------- #
# video_id_from_url
# --------------------------------------------------------------------------- #

def test_video_id_watch_url():
    assert video_id_from_url("https://www.youtube.com/watch?v=QYXgPkxGZFw") == "QYXgPkxGZFw"


def test_video_id_watch_url_with_extra_params():
    url = "https://www.youtube.com/watch?v=QYXgPkxGZFw&t=42s&feature=shared"
    assert video_id_from_url(url) == "QYXgPkxGZFw"


def test_video_id_shorts():
    assert video_id_from_url("https://www.youtube.com/shorts/QYXgPkxGZFw") == "QYXgPkxGZFw"


def test_video_id_youtu_be():
    assert video_id_from_url("https://youtu.be/QYXgPkxGZFw") == "QYXgPkxGZFw"


def test_video_id_embed():
    assert video_id_from_url("https://www.youtube.com/embed/QYXgPkxGZFw") == "QYXgPkxGZFw"


def test_video_id_rejects_non_youtube():
    assert video_id_from_url("https://www.instagram.com/reel/DeRpwRITEfc/") is None
    assert video_id_from_url("") is None
    assert video_id_from_url("not a url") is None


# --------------------------------------------------------------------------- #
# window_segments
# --------------------------------------------------------------------------- #

def test_window_segments_groups_by_30s():
    segs = [
        {"start": 2.0, "end": 5.0, "text": "hello"},
        {"start": 10.0, "end": 12.0, "text": "world"},
        {"start": 35.0, "end": 40.0, "text": "second window"},
        {"start": 70.0, "end": 75.0, "text": "third"},
    ]
    wins = window_segments(segs)
    assert len(wins) == 3
    assert wins[0]["index"] == 0
    assert wins[0]["text"] == "hello world"
    assert wins[1]["start"] == 30 and wins[1]["text"] == "second window"
    assert wins[2]["start"] == 60 and wins[2]["text"] == "third"


def test_window_segments_skips_empty():
    assert window_segments([]) == []
    assert window_segments([{"start": 0, "end": 1, "text": "   "}]) == []


# --------------------------------------------------------------------------- #
# date handling
# --------------------------------------------------------------------------- #

def test_parse_pub_date():
    dt = _parse_pub_date("Oct 7, 2026")
    assert dt is not None and (dt.year, dt.month, dt.day) == (2026, 10, 7)
    assert _parse_pub_date("garbage") is None
    assert _parse_pub_date("") is None


def test_cdr_window_format():
    w = _cdr_window("Oct 7, 2026")
    assert w is not None
    assert w.startswith("cdr:1,cd_min:10/7/2026,cd_max:")
    assert "qdr" not in w  # never relative windows


def test_cdr_window_rejects_bad_input():
    assert _cdr_window(None) is None
    assert _cdr_window("not a date") is None
    assert _cdr_window("Jan 1, 2099") is None  # future date


def test_registrable_domain():
    assert _registrable_domain("https://sub.example.com/x") == "example.com"
    assert _registrable_domain("https://example.com/") == "example.com"
    assert _registrable_domain("https://www.bbc.co.uk/news") == "co.uk"


# --------------------------------------------------------------------------- #
# apply_verdict — the deterministic guardrails
# --------------------------------------------------------------------------- #

def _ev(link, source="", date="", title="t"):
    return {"title": title, "link": link, "snippet": "s", "source": source, "date": date}


def test_green_needs_two_distinct_domains():
    ev = [_ev("https://a.com/1", source="A"), _ev("https://b.org/2", source="B")]
    verdict, used, note = apply_verdict("claim", ev, {"supports": [0, 1], "contradicts": []})
    assert verdict == "green"
    assert len(used) == 2
    assert all(e["stance"] == "supports" for e in used)


def test_syndication_guard_same_domain_is_not_green():
    ev = [_ev("https://news.a.com/1"), _ev("https://www.a.com/2")]
    verdict, used, _ = apply_verdict("claim", ev, {"supports": [0, 1], "contradicts": []})
    assert verdict == "amber"  # one registrable domain -> not corroborated twice


def test_amber_single_source():
    ev = [_ev("https://a.com/1", source="A")]
    verdict, used, note = apply_verdict("claim", ev, {"supports": [0], "contradicts": []})
    assert verdict == "amber"
    assert "needs more" in note


def test_red_dated_contradiction_wins():
    ev = [
        _ev("https://a.com/1", source="A"),
        _ev("https://b.org/2", source="B"),
        _ev("https://factcheck.org/3", source="FC", date="Oct 8, 2026"),
    ]
    stance = {"supports": [0, 1], "contradicts": [2]}
    verdict, used, note = apply_verdict("claim", ev, stance)
    assert verdict == "red"
    assert used[0]["stance"] == "contradicts"
    assert "Oct 8, 2026" in note


def test_red_undated_contradiction():
    ev = [_ev("https://factcheck.org/3", source="FC")]
    verdict, used, _ = apply_verdict("claim", ev, {"supports": [], "contradicts": [0]})
    assert verdict == "red"


def test_grey_insufficient_evidence():
    verdict, used, note = apply_verdict("claim", [], {"supports": [], "contradicts": []})
    assert verdict == "grey"
    assert used == []
    assert "Not enough evidence" in note


def test_grey_when_evidence_takes_no_stance():
    ev = [_ev("https://a.com/1"), _ev("https://b.org/2")]
    verdict, _, _ = apply_verdict("claim", ev, {"supports": [], "contradicts": []})
    assert verdict == "grey"


def test_stance_indices_clamped():
    ev = [_ev("https://a.com/1")]
    # out-of-range indices must not crash or leak
    verdict, used, _ = apply_verdict("claim", ev, {"supports": [5], "contradicts": [9]})
    assert verdict == "grey"


# --------------------------------------------------------------------------- #
# extract_claims — LLM boundary monkeypatched
# --------------------------------------------------------------------------- #

def test_extract_claims_caps_and_validation(monkeypatch):
    import app.pipeline.structuring as structuring

    payload = (
        '[{"window_index": 0, "claim": "Sweet potatoes have vitamin D.", "query": "sweet potato vitamin D"},'
        ' {"window_index": 0, "claim": "Second claim same window.", "query": "second query"},'
        ' {"window_index": 0, "claim": "Third claim same window over cap.", "query": "third query"},'
        ' {"window_index": 99, "claim": "Bad window index.", "query": "bad"},'
        ' {"window_index": 1, "claim": "", "query": "empty claim"},'
        ' {"window_index": 1, "claim": "Good claim window one.", "query": "good query one"}]'
    )
    monkeypatch.setattr(structuring, "complete", lambda *a, **k: payload)
    windows = [
        {"index": 0, "start": 0, "end": 30, "text": "sweet potatoes vitamin D"},
        {"index": 1, "start": 30, "end": 60, "text": "more text here"},
    ]
    claims = extract_claims(windows)
    # 2 per window cap drops the third window-0 claim; bad index + empty dropped
    assert len(claims) == 3
    assert claims[0]["claim"] == "Sweet potatoes have vitamin D."
    assert claims[0]["window_start"] == 0
    assert claims[2]["window_index"] == 1


def test_extract_claims_bad_json_returns_empty(monkeypatch):
    import app.pipeline.structuring as structuring
    monkeypatch.setattr(structuring, "complete", lambda *a, **k: "not json at all")
    windows = [{"index": 0, "start": 0, "end": 30, "text": "hello"}]
    assert extract_claims(windows) == []


def test_extract_claims_no_llm_returns_empty(monkeypatch):
    import app.pipeline.structuring as structuring

    def _boom(*a, **k):
        raise RuntimeError("no key")

    monkeypatch.setattr(structuring, "complete", _boom)
    windows = [{"index": 0, "start": 0, "end": 30, "text": "hello"}]
    assert extract_claims(windows) == []


# --------------------------------------------------------------------------- #
# Reel raw transcript windowing & verification
# --------------------------------------------------------------------------- #

def test_text_to_windows_splits_raw_reel_transcript():
    # 130 words -> 2 windows of 65 words
    words = [f"word{i}" for i in range(130)]
    text = " ".join(words)
    windows = text_to_windows(text, window_seconds=30, words_per_window=65)
    assert len(windows) == 2
    assert windows[0]["index"] == 0
    assert windows[0]["start"] == 0
    assert windows[0]["end"] == 30
    assert len(windows[0]["text"].split()) == 65
    assert windows[1]["index"] == 1
    assert windows[1]["start"] == 30
    assert windows[1]["end"] == 60


def test_text_to_windows_empty():
    assert text_to_windows("") == []
    assert text_to_windows("   ") == []


def test_verify_transcript_no_key_returns_none(monkeypatch):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "serpapi_api_key", "")
    assert verify_transcript("Some factual statement about health.") is None


def test_claim_verdict_model_with_trace():
    from app.models.card import ClaimVerdict
    cv = ClaimVerdict(
        window_index=0,
        window_start=0.0,
        window_end=30.0,
        claim="Water boils at 100C",
        verdict="green",
        note="Corroborated by BBC Science",
        query="water boiling temperature",
        trace={
            "search_query": "water boiling temperature",
            "engines": ["google", "google_news"],
            "sources_scanned": 5,
            "corroborations": 2,
            "contradictions": 0,
            "decision_rule": "Corroborated by 2 distinct domain(s)",
        },
    )
    assert cv.query == "water boiling temperature"
    assert cv.trace["sources_scanned"] == 5
    assert cv.trace["engines"] == ["google", "google_news"]


def test_share_html_renders_agent_trace():
    from app.api.share import _render_verdicts_html
    verdicts_data = {
        "video_id": "test_vid",
        "claims": [
            {
                "window_index": 0,
                "window_start": 0,
                "window_end": 30,
                "claim": "Bananas are radioactive.",
                "verdict": "green",
                "note": "Corroborated by EPA",
                "query": "banana potassium 40 radioactivity",
                "evidence": [{"source": "EPA", "link": "https://epa.gov/radiation"}],
                "trace": {
                    "search_query": "banana potassium 40 radioactivity",
                    "engines": ["google", "google_news"],
                    "sources_scanned": 4,
                    "corroborations": 2,
                    "contradictions": 0,
                    "decision_rule": "Corroborated by 2 distinct domain(s)",
                },
            }
        ],
    }
    html = _render_verdicts_html(verdicts_data)
    assert "Search &amp; Decision Trace" in html or "Search & Decision Trace" in html
    assert "banana potassium 40 radioactivity" in html
    assert "Google Search, Google News" in html
    assert "Corroborated by 2 distinct domain(s)" in html


def test_downloader_serpapi_youtube_fallback(monkeypatch, tmp_path):
    from app.pipeline.ingestion.downloader import _serpapi_youtube_result
    from app.pipeline import verdicts
    import requests

    monkeypatch.setattr(
        verdicts,
        "fetch_transcript",
        lambda vid: [{"start": 0.0, "end": 5.0, "text": "This is test transcript content."}],
    )

    class DummyOEmbedResp:
        status_code = 200
        def json(self):
            return {
                "title": "Test Title",
                "author_name": "Test Author",
                "thumbnail_url": "https://example.com/thumb.jpg",
            }

    class DummyThumbResp:
        status_code = 200
        content = b"fake-jpg-data"

    def mock_get(url, *args, **kwargs):
        if "oembed" in url:
            return DummyOEmbedResp()
        return DummyThumbResp()

    monkeypatch.setattr(requests, "get", mock_get)

    out_file = tmp_path / "video.mp4"
    res = _serpapi_youtube_result("https://www.youtube.com/shorts/5PO-ZlmaORs", str(out_file))

    assert res is not None
    assert res.media_type == "article"
    assert res.resolver == "serpapi-youtube"
    assert "This is test transcript content." in res.text
    assert res.caption == "Test Title"
    assert res.author == "Test Author"


