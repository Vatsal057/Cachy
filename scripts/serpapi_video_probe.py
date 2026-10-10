#!/usr/bin/env python3
"""Probe SerpApi YouTube endpoints on real short-form videos.

Purpose: before building Verdict Timeline, confirm what the APIs actually
return for the kind of videos Cachy ingests (Shorts-style). Specifically:
  (a) does youtube_video return chapters / published_date?
  (b) does youtube_video_transcript return usable segments?

Reads SERPAPI_API_KEY from backend/.env — never hardcode the key.
Each video costs ~2 SerpApi searches. Keep it to 3-5 videos.

Usage:
  python3 scripts/serpapi_video_probe.py <youtube_url_1> <youtube_url_2> ...

Run from the repo root: /Users/vatsal/Desktop/cachy_hackathon
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import requests

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_PATH = REPO_ROOT / "backend" / ".env"
SERPAPI_URL = "https://serpapi.com/search.json"
TIMEOUT = 30


def extract_video_id(url_or_id: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]{11}", url_or_id):
        return url_or_id
    parsed = urlparse(url_or_id)
    if "youtube.com" in parsed.netloc:
        if parsed.path.startswith("/shorts/"):
            return parsed.path.split("/shorts/")[1].split("/")[0].split("?")[0]
        qs = parse_qs(parsed.query)
        if "v" in qs:
            return qs["v"][0]
    elif "youtu.be" in parsed.netloc:
        return parsed.path.strip("/").split("?")[0]
    return url_or_id


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        values[key.strip()] = val.strip().strip('"').strip("'")
    return values


def call(engine: str, video_id: str, api_key: str) -> dict | None:
    try:
        resp = requests.get(
            SERPAPI_URL,
            params={"engine": engine, "v": video_id, "api_key": api_key},
            timeout=TIMEOUT,
        )
        if resp.status_code != 200:
            print(f"  [{engine}] HTTP status {resp.status_code}")
            return None
        data = resp.json()
    except Exception as exc:  # noqa: BLE001 — probe must never crash
        print(f"  [{engine}] request failed: {type(exc).__name__}")
        return None
    if isinstance(data, dict) and data.get("error"):
        print(f"  [{engine}] API error: {data['error']}")
        return None
    return data if isinstance(data, dict) else None


def probe_video(video_url: str, api_key: str) -> None:
    print(f"\n=== {video_url}")
    video_id = extract_video_id(video_url)
    print(f"  video_id: {video_id}")

    details = call("youtube_video", video_id, api_key)
    if details:
        print(f"  title: {details.get('title', '?')[:80]}")
        print(f"  published_date: {details.get('published_date', 'MISSING')}")
        chapters = details.get("chapters") or []
        print(f"  chapters: {len(chapters)}")
        for ch in chapters[:5]:
            print(f"    - {ch.get('time_start')}s: {str(ch.get('title'))[:60]}")
    else:
        print("  youtube_video: no usable response")

    transcript = call("youtube_video_transcript", video_id, api_key)
    if transcript:
        segments = transcript.get("transcript") or []
        print(f"  transcript segments: {len(segments)}")
        if segments:
            first, last = segments[0], segments[-1]
            span_s = (last.get("start_ms", 0) - first.get("start_ms", 0)) // 1000
            print(f"  transcript span: ~{span_s}s")
            print(f"  sample: [{first.get('start_time_text')}] {str(first.get('snippet'))[:80]}")
        t_chapters = transcript.get("chapters") or []
        print(f"  transcript chapters: {len(t_chapters)}")
    else:
        print("  youtube_video_transcript: no usable response")


def main() -> int:
    urls = sys.argv[1:]
    if not urls:
        print("Usage: python3 scripts/serpapi_video_probe.py <youtube_url_1> ...")
        return 1
    if not ENV_PATH.exists():
        print(f".env not found at {ENV_PATH}")
        return 1
    api_key = load_env(ENV_PATH).get("SERPAPI_API_KEY", "")
    if not api_key:
        print("SERPAPI_API_KEY not set in backend/.env")
        return 1
    print(f"Probing {len(urls)} video(s), ~{2 * len(urls)} SerpApi searches.")
    for url in urls:
        probe_video(url, api_key)
    print("\nDone. Key takeaways for Verdict Timeline:")
    print("- chapters>0 means per-chapter ticks are possible;")
    print("  otherwise transcript-window segmentation is the primary path.")
    print("- missing published_date / missing transcript = rethink the feature.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
