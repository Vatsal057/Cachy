"""Verdict Timeline: per-window factual-claim verification via SerpApi.

For a YouTube video the agent:
  1. perceives — transcript (SerpApi youtube_video_transcript) + published_date
     (youtube_video), grouped into fixed 30-second windows;
  2. plans — one LLM call extracts up to 2 checkable factual claims per window
     (max 8/video), dropping opinions, predictions and greetings BEFORE any
     search budget is spent;
  3. acts — per claim, Google Search date-bounded to [published_date, today]
     plus Google News, with a query-hash cache so a re-check never re-pays;
  4. judges — deterministic guardrails in code (LLM proposes, code disposes):
       green  = 2+ corroborating sources from distinct domains
       red    = a specific dated contradiction
       amber  = exactly 1 corroborating source
       grey   = insufficient evidence (the honest fallback — the system refuses
                to verdict without search data rather than hallucinating);
  5. reports — the timeline lives on the card, so the note remembers what the
     web confirmed.

Same discipline as enrichment/insight: best-effort and isolated. No API key,
no transcript, an API error, or empty evidence yields None — never a failed
card. Without SerpApi every tick is grey, which is the proof of dependence:
the feature is absent, not degraded.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import re
from datetime import datetime, timezone
from urllib.parse import urlparse, parse_qs

import requests

from app.config import get_settings

log = logging.getLogger("pipeline.verdicts")

_SERPAPI_URL = "https://serpapi.com/search.json"
_TIMEOUT_SECONDS = 20
_WINDOW_SECONDS = 30
_MAX_CLAIMS = 8
_MAX_CLAIMS_PER_WINDOW = 2
_SEARCH_NUM = 10

# In-memory query cache: sha256(engine + sorted params) -> response dict.
# A re-check of the same claim never re-pays for the same search.
_SEARCH_CACHE: dict[str, dict] = {}


# --------------------------------------------------------------------------- #
# SerpApi plumbing — cached, never raises, never logs the key
# --------------------------------------------------------------------------- #

def _cache_key(engine: str, params: dict) -> str:
    canon = engine + "|" + "&".join(
        f"{k}={params[k]}" for k in sorted(params) if k != "api_key"
    )
    return hashlib.sha256(canon.encode()).hexdigest()


def _serpapi_get(engine: str, params: dict) -> dict | None:
    """GET SerpApi search.json. Returns the parsed dict, or None on any
    failure (network, HTTP error, API error, bad JSON). Results are cached
    by query hash for the process lifetime."""
    settings = get_settings()
    if not settings.serpapi_enabled:
        return None
    query = dict(params)
    query["engine"] = engine
    query["api_key"] = settings.serpapi_api_key.strip()
    key = _cache_key(engine, query)
    if key in _SEARCH_CACHE:
        return _SEARCH_CACHE[key]
    try:
        resp = requests.get(_SERPAPI_URL, params=query, timeout=_TIMEOUT_SECONDS)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:  # noqa: BLE001 — network/API failure -> no data
        log.warning("verdicts: SerpApi %s request failed: %s", engine, e)
        return None
    if not isinstance(data, dict) or data.get("error"):
        log.warning("verdicts: SerpApi %s error: %s", engine, (data or {}).get("error"))
        return None
    _SEARCH_CACHE[key] = data
    return data


# --------------------------------------------------------------------------- #
# Video identity + transcript
# --------------------------------------------------------------------------- #

def video_id_from_url(url: str) -> str | None:
    """Extract the 11-char YouTube video id from watch / youtu.be / shorts /
    embed / live URLs. None for anything else."""
    if not url or "youtu" not in url:
        return None
    try:
        parsed = urlparse(url)
    except Exception:  # noqa: BLE001
        return None
    host = parsed.hostname or ""
    if "youtube.com" in host:
        qs = parse_qs(parsed.query)
        if qs.get("v"):
            return qs["v"][0]
        m = re.search(r"/(shorts|embed|live)/([A-Za-z0-9_-]{11})", parsed.path)
        if m:
            return m.group(2)
    elif "youtu.be" in host:
        m = re.search(r"/([A-Za-z0-9_-]{11})", parsed.path)
        if m:
            return m.group(1)
    return None


def fetch_transcript(video_id: str) -> list[dict] | None:
    """Timestamped transcript segments [{start, end, text}] or None."""
    data = _serpapi_get("youtube_video_transcript", {"v": video_id})
    if not data:
        return None
    raw = data.get("transcript") or []
    out: list[dict] = []
    for seg in raw:
        if not isinstance(seg, dict):
            continue
        text = str(seg.get("text") or seg.get("snippet") or "").strip()
        if not text:
            continue
        try:
            start = float(seg.get("start", 0) or 0)
            end = float(seg.get("end", start) or start)
        except (TypeError, ValueError):
            start, end = 0.0, 0.0
        out.append({"start": start, "end": end, "text": text})
    return out or None


def fetch_published_date(video_id: str) -> str | None:
    """The video's published_date string (e.g. 'Oct 7, 2026') or None. Every
    verdict is 'as of' dated from this anchor."""
    data = _serpapi_get("youtube_video", {"v": video_id})
    if not data:
        return None
    pub = str(data.get("published_date") or "").strip()
    return pub or None


def window_segments(segments: list[dict], window_seconds: int = _WINDOW_SECONDS) -> list[dict]:
    """Group transcript segments into fixed windows: [{index, start, end, text}]."""
    windows: list[dict] = []
    for seg in segments:
        start = float(seg.get("start", 0) or 0)
        idx = int(start // window_seconds)
        while len(windows) <= idx:
            w = len(windows)
            windows.append({
                "index": w,
                "start": w * window_seconds,
                "end": (w + 1) * window_seconds,
                "text": "",
            })
        windows[idx]["text"] = (windows[idx]["text"] + " " + seg["text"]).strip()
    return [w for w in windows if w["text"].strip()]


def text_to_windows(text: str, window_seconds: int = _WINDOW_SECONDS, words_per_window: int = 65) -> list[dict]:
    """Turn a raw text transcript (e.g. from an Instagram Reel Whisper extraction) into timed windows."""
    words = text.split()
    if not words:
        return []
    windows: list[dict] = []
    chunk_size = max(20, words_per_window)
    for i in range(0, len(words), chunk_size):
        chunk_words = words[i:i + chunk_size]
        w_idx = len(windows)
        windows.append({
            "index": w_idx,
            "start": w_idx * window_seconds,
            "end": (w_idx + 1) * window_seconds,
            "text": " ".join(chunk_words),
        })
    return windows


# --------------------------------------------------------------------------- #
# Claim extraction — one LLM call, strict JSON, multilingual-aware
# --------------------------------------------------------------------------- #

_CLAIM_SYSTEM = """You read transcript windows from a short video. Extract the FACTUAL claims worth verifying.

Return ONLY a JSON array (no prose, no fences). Each item:
{ "window_index": int, "claim": str, "query": str }

Rules:
- Only checkable factual claims: named entities, numbers, dates, concrete assertions about the world.
- SKIP opinions, advice, predictions, greetings, jokes, calls to action.
- At most 2 claims per window, at most 8 total. Fewer is fine. Empty array is fine.
- The transcript may be in Hindi, Bengali, or English. Write `claim` and `query` in ENGLISH regardless.
- `query` is 3-8 keywords for a web search on the claim. No quotes, no operators.
- `claim` is one plain sentence, max 25 words.
"""


def _clean_str(value, limit: int = 300) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.split()).strip()[:limit]


def extract_claims(windows: list[dict]) -> list[dict]:
    """LLM proposes claims; code validates. Returns [{window_index, claim,
    query, window_start, window_end}]. Never raises."""
    if not windows:
        return []
    digest = "\n\n".join(
        f"[window {w['index']} | {w['start']:.0f}s-{w['end']:.0f}s]\n{w['text'][:600]}"
        for w in windows
    )
    try:
        from app.pipeline.structuring import complete, _strip_fences
        raw = complete(
            f"Transcript windows:\n---\n{digest}\n---",
            system=_CLAIM_SYSTEM,
            max_tokens=2048,
        )
    except Exception as e:  # noqa: BLE001 — LLM unavailable -> no claims
        log.warning("verdicts: claim extraction LLM call failed: %s", e)
        return []
    if not raw:
        return []
    try:
        data = json.loads(_strip_fences(raw))
    except (json.JSONDecodeError, TypeError):
        log.warning("verdicts: claim extraction output was not JSON")
        return []
    if not isinstance(data, list):
        return []
    by_window: dict[int, int] = {}
    win_lookup = {w["index"]: w for w in windows}
    out: list[dict] = []
    for item in data:
        if not isinstance(item, dict) or len(out) >= _MAX_CLAIMS:
            continue
        wi = item.get("window_index")
        if not isinstance(wi, int) or wi not in win_lookup:
            continue
        if by_window.get(wi, 0) >= _MAX_CLAIMS_PER_WINDOW:
            continue
        claim = _clean_str(item.get("claim"), 300)
        query = _clean_str(item.get("query"), 120)
        if not claim or not query:
            continue
        by_window[wi] = by_window.get(wi, 0) + 1
        w = win_lookup[wi]
        out.append({
            "window_index": wi,
            "window_start": w["start"],
            "window_end": w["end"],
            "claim": claim,
            "query": query,
        })
    return out


# --------------------------------------------------------------------------- #
# Evidence retrieval — date-bounded search + news
# --------------------------------------------------------------------------- #

def _parse_pub_date(pub_date: str) -> datetime | None:
    for fmt in ("%b %d, %Y", "%B %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(pub_date.strip(), fmt).replace(tzinfo=timezone.utc)
        except (ValueError, AttributeError):
            continue
    return None


def _cdr_window(pub_date: str | None) -> str | None:
    """Absolute date window for tbs=cdr:1 (absolute, fast). Never qdr: narrow
    relative windows hang ~90s on zero-result misses; cdr returns in ~3s."""
    if not pub_date:
        return None
    start = _parse_pub_date(pub_date)
    if not start:
        return None
    today = datetime.now(timezone.utc)
    if start > today:
        return None
    return (f"cdr:1,cd_min:{start.month}/{start.day}/{start.year},"
            f"cd_max:{today.month}/{today.day}/{today.year}")


def _registrable_domain(link: str) -> str:
    """Last two labels of the host: sub.example.com -> example.com. Used so
    one wire story syndicated across 40 subdomains still counts once."""
    try:
        host = (urlparse(link).hostname or "").lower()
    except Exception:  # noqa: BLE001
        return ""
    parts = host.split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else host


def _clean_evidence(data: dict, limit: int = 10) -> list[dict]:
    out: list[dict] = []
    seen: set[str] = set()
    results = data.get("organic_results") or data.get("news_results") or []
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
        raw_source = item.get("source")
        if isinstance(raw_source, dict):
            source_str = str(raw_source.get("name") or "").strip()
        else:
            source_str = str(raw_source or "").strip()
        out.append({
            "title": title[:200],
            "link": link,
            "snippet": str(item.get("snippet") or "").strip()[:500],
            "source": source_str[:100],
            "date": str(item.get("date") or "").strip()[:40],
        })
        if len(out) >= limit:
            break
    return out


def search_evidence(query: str, pub_date: str | None) -> list[dict]:
    """Date-bounded Google search + Google News for one claim. Merged,
    deduped by link. Never raises."""
    if not query:
        return []
    params: dict = {"q": query, "num": _SEARCH_NUM}
    tbs = _cdr_window(pub_date)
    if tbs:
        params["tbs"] = tbs
    merged: list[dict] = []
    seen: set[str] = set()
    for engine in ("google", "google_news"):
        data = _serpapi_get(engine, params)
        if not data:
            continue
        for ev in _clean_evidence(data, limit=_SEARCH_NUM):
            if ev["link"] in seen:
                continue
            seen.add(ev["link"])
            merged.append(ev)
    return merged


# --------------------------------------------------------------------------- #
# Judgement — LLM proposes stances, CODE disposes the verdict
# --------------------------------------------------------------------------- #

_STANCE_SYSTEM = """You judge whether web sources support or contradict a factual claim.

Return ONLY a JSON object (no prose, no fences):
{ "supports": [int], "contradicts": [int] }

Rules:
- Indices refer to the numbered sources below. An index goes in at most one list.
- supports: the source's title+snippet clearly AFFIRMS the claim.
- contradicts: the source's title+snippet clearly DENIES or corrects the claim, with a specific counter-fact.
- When unsure, put the index in NEITHER list. Silence beats a wrong verdict.
- Ignore sources that are merely about the same topic without taking a position.
"""


def classify_stance(claim: str, evidence: list[dict]) -> dict:
    """Returns {'supports': [indices], 'contradicts': [indices]}. Never raises."""
    empty = {"supports": [], "contradicts": []}
    if not claim or not evidence:
        return empty
    numbered = "\n\n".join(
        f"[{i}] {ev['title']}\n{ev['snippet'][:300]}"
        for i, ev in enumerate(evidence[:10])
    )
    try:
        from app.pipeline.structuring import complete, _strip_fences
        raw = complete(
            f"Claim: {claim}\n\nSources:\n---\n{numbered}\n---",
            system=_STANCE_SYSTEM,
            max_tokens=512,
        )
    except Exception as e:  # noqa: BLE001
        log.warning("verdicts: stance classification failed: %s", e)
        return empty
    if not raw:
        return empty
    try:
        data = json.loads(_strip_fences(raw))
    except (json.JSONDecodeError, TypeError):
        return empty
    if not isinstance(data, dict):
        return empty
    n = len(evidence[:10])

    def _idxs(key: str) -> list[int]:
        vals = data.get(key)
        if not isinstance(vals, list):
            return []
        return [v for v in vals if isinstance(v, int) and 0 <= v < n]

    supports = _idxs("supports")
    contradicts = [v for v in _idxs("contradicts") if v not in supports]
    return {"supports": supports, "contradicts": contradicts}


def apply_verdict(claim: str, evidence: list[dict], stance: dict) -> tuple[str, list[dict], str]:
    """Deterministic guardrails. Returns (verdict, used_evidence, note).

    green needs corroboration from 2 DISTINCT registrable domains;
    red needs a dated contradiction; amber is a single corroboration;
    everything else is grey — insufficient evidence, stated honestly."""
    supports = [evidence[i] for i in stance.get("supports", []) if i < len(evidence)]
    contradicts = [evidence[i] for i in stance.get("contradicts", []) if i < len(evidence)]

    # Red: a specific dated contradiction wins over corroboration — the video is
    # wrong on this claim and we can point at why.
    dated_contra = [ev for ev in contradicts if ev.get("date")]
    if dated_contra:
        ev = dated_contra[0]
        used = [{**ev, "stance": "contradicts"}]
        note = f"Contradicted by {ev.get('source') or _registrable_domain(ev['link'])}"
        if ev.get("date"):
            note += f" ({ev['date']})"
        return ("red", used, note)
    if contradicts:
        ev = contradicts[0]
        used = [{**ev, "stance": "contradicts"}]
        return ("red", used,
                f"Contradicted by {ev.get('source') or _registrable_domain(ev['link'])}")

    domains: dict[str, dict] = {}
    for ev in supports:
        d = _registrable_domain(ev["link"])
        if d and d not in domains:
            domains[d] = ev
    if len(domains) >= 2:
        used = [{**ev, "stance": "supports"} for ev in list(domains.values())[:4]]
        names = [ev.get("source") or _registrable_domain(ev["link"]) for ev in used[:2]]
        return ("green", used, f"Corroborated by {', '.join(names)}")
    if len(domains) == 1:
        ev = list(domains.values())[0]
        used = [{**ev, "stance": "supports"}]
        return ("amber", used,
                f"One source ({ev.get('source') or _registrable_domain(ev['link'])}) — needs more")
    return ("grey", [], "Not enough evidence to verify")


# --------------------------------------------------------------------------- #
# Orchestrator
# --------------------------------------------------------------------------- #

def verify_transcript(
    transcript: list[dict] | str,
    pub_date: str | None = None,
    video_id: str = "",
) -> dict | None:
    """Run the verdict agent directly on a transcript (list of segment dicts or raw text)."""
    settings = get_settings()
    if not settings.serpapi_enabled:
        return None
    try:
        return _verify_transcript(transcript, pub_date=pub_date, video_id=video_id)
    except Exception as e:  # noqa: BLE001 — verdicts never break the card
        log.warning("verdicts: verify_transcript failed: %s", e)
        return None


def _verify_transcript(
    transcript: list[dict] | str,
    pub_date: str | None = None,
    video_id: str = "",
) -> dict | None:
    if isinstance(transcript, str):
        windows = text_to_windows(transcript)
    else:
        windows = window_segments(transcript)
    if not windows:
        return None
    claims = extract_claims(windows)
    if not claims:
        log.info("verdicts: no checkable claims -> no timeline")
        return None
    checked_at = datetime.now(timezone.utc).isoformat()
    out_claims: list[dict] = []
    for c in claims:
        evidence = search_evidence(c["query"], pub_date)
        stance = classify_stance(c["claim"], evidence)
        verdict, used, note = apply_verdict(c["claim"], evidence, stance)
        sup_count = len(stance.get("supports", []))
        contra_count = len(stance.get("contradicts", []))
        rule_desc = (
            f"Contradicted by dated source: {note}" if verdict == "red"
            else f"Corroborated by {sup_count} distinct domain(s)" if verdict == "green"
            else f"Single source corroboration ({sup_count}) — requires 2+ independent domains" if verdict == "amber"
            else f"Insufficient independent evidence scanned ({len(evidence)} sources)"
        )
        out_claims.append({
            "window_index": c["window_index"],
            "window_start": c["window_start"],
            "window_end": c["window_end"],
            "claim": c["claim"],
            "query": c["query"],
            "verdict": verdict,
            "note": note,
            "evidence": used,
            "trace": {
                "search_query": c["query"],
                "engines": ["google", "google_news"],
                "sources_scanned": len(evidence),
                "corroborations": sup_count,
                "contradictions": contra_count,
                "decision_rule": rule_desc,
            },
        })
        log.info("verdicts: [%s] %s -> %s", video_id or "transcript", c["claim"][:60], verdict)
    return {
        "video_id": video_id,
        "checked_at": checked_at,
        "published_date": pub_date or "",
        "claims": out_claims,
    }


def verify_video(video_id: str) -> dict | None:
    """Run the verdict agent on one YouTube video. Returns the VerdictTimeline
    dict (validated by the caller into the pydantic model) or None when the
    run cannot produce anything honest. Never raises."""
    settings = get_settings()
    if not settings.serpapi_enabled:
        return None
    try:
        return _verify_video(video_id)
    except Exception as e:  # noqa: BLE001 — verdicts never break the card
        log.warning("verdicts: verify_video failed for %s: %s", video_id, e)
        return None


def _verify_video(video_id: str) -> dict | None:
    segments = fetch_transcript(video_id)
    if not segments:
        log.info("verdicts: no transcript for %s -> no timeline", video_id)
        return None
    pub_date = fetch_published_date(video_id)
    return _verify_transcript(segments, pub_date=pub_date, video_id=video_id)


async def verify_transcript_async(
    transcript: list[dict] | str,
    pub_date: str | None = None,
    video_id: str = "",
) -> dict | None:
    return await asyncio.to_thread(verify_transcript, transcript, pub_date, video_id)


async def verify_video_async(video_id: str) -> dict | None:
    return await asyncio.to_thread(verify_video, video_id)
