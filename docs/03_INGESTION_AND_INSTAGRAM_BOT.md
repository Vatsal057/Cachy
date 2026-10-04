# Ingestion Pipelines & Instagram Bot Specification — Cachy

**Version:** 2.0  
**Components:** `app/pipeline/ingestion/`, `app/services/ig_dm_poller.py`  

---

## 1. Instagram Auto-Save Bot Architecture

Cachy allows users to automatically ingest reels into their personal knowledge library simply by sending a Direct Message to `@cachyapp` on Instagram.

```
[User DMs Reel to @cachyapp]
             │
             ▼
    [direct_pending_inbox]
             │
             ├─► Not Approved? ──► cl.direct_pending_approve(thread_id)
             │
             ▼
    [Extract Reel URLs]
             │ (Supports: clip, media_share, xma_share, raw text)
             ▼
    [Resolve Cachy Owner]
             │ (Matches Instagram username via instagram_links table)
             ▼
    [Check Daily Card Quota]
             │
             ├─► Quota Available ──► Enqueue Card (degraded=False)
             └─► Quota Exceeded  ──► Enqueue Card (degraded=True)
             │
             ▼
    [Send Instant Reply DM] ──► "Saved to your Cachy shelf!"
```

---

## 2. Ingestion Protocols & Key Edge Cases

### 2.1 The Message Request (Pending Inbox) Requirement
By default, Instagram places incoming DMs from accounts the bot does not follow into the **Pending Requests** folder (`direct_pending_inbox`).
- Standard inbox queries (`direct_threads()`) will **not** return these messages.
- The poller queries both `cl.direct_pending_inbox()` and `cl.direct_threads()`.
- When a thread is found in pending status, it is approved via `cl.direct_pending_approve(thread_id)` before attempting to broadcast any reply.

### 2.2 Multi-Format Reel Parsing
Instagram clients send reels in differing formats depending on whether the user shared via web, mobile share sheet, or direct attachment:
1. **`msg.clip`**: Native reel attachment shared from the mobile app.
2. **`msg.media_share`**: Standard feed post or carousel shared in DM.
3. **`msg.xma_share`**: Rich media attachment generated when using the in-app Instagram share sheet (`video_url` or `target_url`).
4. **`msg.text`**: Plain text message containing an `instagram.com/reel/...` or `instagram.com/p/...` URL.

### 2.3 Burst Queues (Consecutive Reels)
Users frequently send 3–6 reels in quick succession. The poller walks backwards through the thread's message history up to 10 messages until it encounters the bot's own previous reply, extracting and enqueuing all unacknowledged reels in a single batch.

---

## 3. Cloud TLS & Docker Transport Discipline

### 3.1 The `curl_cffi` Cloud Handshake Bug
In containerized cloud environments (e.g. Hugging Face Spaces on AWS), the default `instagrapi` v2 transport (`curl_cffi`) attempts HTTP/2 prior knowledge and post-quantum TLS curves (`X25519MLKEM768`). Datacenter egress routers terminate or drop these handshakes, causing requests to hang for 60 seconds and fail with:
```
SSLError curl private transport failed (SSLError)
```

### 3.2 Enforcing Standard Python `requests`
To guarantee 100% cloud reliability:
1. The client is explicitly instantiated with `Client(private_transport="requests")`.
2. After loading stored session files, `cl._configure_private_session_retry("requests")` is executed to prevent stored settings from reverting to `curl`.
3. If an `SSLError` is intercepted during runtime, the poller automatically reconfigures to `requests` transport and retries.
4. The container `Dockerfile` installs `ca-certificates` and `curl`.

---

## 4. Video & Audio Ingestion Engine

### 4.1 Resolver Fallback Chain
Video downloading is executed through a cascading fallback strategy in `app/pipeline/ingestion/downloader.py`:
1. **Direct `yt-dlp`**: Standard extractor for YouTube Shorts and TikTok.
2. **Keyless Web Scrapers**: When Instagram blocks direct datacenter IP downloads, the resolver attempts keyless services in order:
   - `vidssave`
   - `savethevideo`
   - `saveig`
   - `downloadgram`

### 4.2 Article Ingestion
Web links and blog posts are processed via `trafilatura`, which strips boilerplate, ads, and navigation headers, producing clean semantic markdown for structuring.

### 4.3 Ephemeral Storage Discipline
Downloaded video files are saved to `/data/downloads` strictly for the duration of the keyframe and audio extraction steps. Once keyframes are extracted and the audio is transcribed, the original video file is **immediately deleted** from disk.
