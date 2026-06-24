# 02 — Ingestion

## Strategy

There is no clean official API for reel media, so ingestion uses a **cascade of
keyless third-party resolver services**, with local tools as fallback. These
services are fragile by nature — they get rate-limited, change endpoints, and
quietly die — so the cascade is built to treat **total failure as a normal,
expected outcome**, not a crash.

This is a deliberate, accepted tradeoff (it runs against the source platforms'
terms of service). It is appropriate for a personal/early-stage tool; revisit
before any wide public distribution.

## The cascade (order matters)

Tried in sequence; first success wins:

1. **Keyless resolvers** (free): vidssave → savethevideo → saveig → downloadgram
   → anyvidsave → igreelsdl
2. **RapidAPI** (optional, only if `RAPIDAPI_KEY` is set) — kept as a paid escape
   hatch; the app does not depend on it.
3. **yt-dlp** (local) — videos/reels fallback.
4. **instaloader** (local) — Instagram carousels/images fallback.

## Module layout

```
ingestion/
  resolvers.py    # the working resolver functions — LEFT UNTOUCHED
  downloader.py   # clean orchestration + async wrapper (the integration layer)
```

`resolvers.py` is the original working code. Its internals (exact headers, magic
strings, HTML scraping) are intentionally **not refactored** — that's the
fragile part that "just works," and rewriting it risks breaking it.

`downloader.py` is the thin layer the app actually calls. It provides:

- `DownloaderConfig` — output dir, cookies path, optional RapidAPI key (from env).
- `DownloadResult(media_type, data, caption, resolver)` — structured result;
  records *which* resolver succeeded for observability.
- `download_content(url, config)` — sync cascade; isolates each job in a unique
  directory; catches per-resolver exceptions so one failure doesn't abort the chain.
- `download_content_async(url, config)` — the FastAPI entry point. The cascade is
  blocking (requests + yt-dlp + instaloader), so it runs in a worker thread via
  `asyncio.to_thread` to avoid stalling the event loop.

## How the worker calls it

```python
from ingestion.downloader import download_content_async, DownloadError

async def ingest(job):
    job.state = "PROCESSING"
    try:
        result = await download_content_async(job.url)
    except DownloadError:
        job.state = "FAILED"; job.reason = "unavailable"
        return None
    # result.media_type -> "video" | "images"
    # result.data       -> path to .mp4 | list of image paths
    # result.caption    -> may be empty; OCR/transcript compensates
    # result.resolver   -> which strategy won (logged for metrics)
    return result
```

## Known issues to fix before scaling

- **instaloader is not concurrency-safe.** It writes to a shared `temp_images`
  dir and `rmtree`s it; parallel jobs will fight. Fine for single-worker dev;
  give it a per-job dir before running parallel workers.
- **Captions are often empty** from several resolvers. Downstream extraction
  (transcript + OCR) is the real content source; never depend on caption alone.
- **Resolver rot.** Expect individual resolvers to break over time. Monitor
  per-resolver success rate (it's recorded on every card) and prune/replace dead ones.

## Caching

Cache by source URL. Re-sharing the same reel returns the existing card instead
of re-running the cascade — saves resolver load, extraction compute, and LLM quota.
