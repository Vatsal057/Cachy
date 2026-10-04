# Product Requirements Document (PRD) — Cachy

**Version:** 2.0  
**Status:** Active / Production  
**Last Updated:** October 2026  
**Authors:** Cachy Engineering Team  

---

## 1. Executive Summary

Cachy is an AI-powered personal knowledge capture engine that turns ephemeral, short-form media (Instagram Reels, TikToks, YouTube Shorts) and web articles into permanent, structured **knowledge cards**. Instead of letting saved links turn into an unorganized "bookmark graveyard," Cachy extracts core steps, recipes, frameworks, entities, and key-value facts, connects them into an interactive **knowledge graph**, and replays insights through a curated **knowledge feed**.

---

## 2. Problem Statement & User Personas

### 2.1 The Problem
- **Ephemeral Consumption:** Users save dozens of useful reels, tips, workout routines, recipes, and tech tutorials every week on social media.
- **Link Graveyards:** Native bookmarks (Instagram Saved, TikTok Favorites, Chrome Bookmarks) only save links—not knowledge. Finding a specific recipe or step 3 weeks later requires re-watching videos.
- **Cognitive Overload:** Video is a high-bandwidth, slow-to-retrieve medium. Users cannot easily search or reference a 60-second video without re-watching it.

### 2.2 Target Personas
1. **The Curious Scroller / Lifelong Learner:** Scans Instagram/TikTok for book summaries, psychology insights, coding tips, and productivity frameworks. Wants quick access without re-watching.
2. **The Recipe & DIY Collector:** Saves cooking videos, DIY crafts, and workout routines. Needs typed ingredients, step-by-step checklists, and timers.
3. **The Offline Student / Commuter:** Needs knowledge accessible offline on their mobile device without burning data or relying on cloud availability.

---

## 3. Product Vision & Principles

1. **Capture is Sacred:** From native Android share sheets to Instagram DMs (`@cachyapp`), capturing a link must be effortless, reliable, and instant.
2. **Free-First, Graceful Degradation:** No feature should fail hard because a third-party API key is depleted. The system cascades through multiple AI providers (Gemini → Cerebras → Groq → On-Device Gemma → Rule-based fallback).
3. **Calm Editorial Aesthetic:** "Calm Editorial Glass": deep charcoal and warm paper palettes, Fraunces serif typography, Inter body, and IBM Plex Mono labels. Zero flashy gamification, streaks, or aggressive push notifications.
4. **Structured Knowledge over Raw Text:** Rather than dumping a transcript, content is structured into typed blocks (steps, key-value tables, checklists, callouts, and maps).

---

## 4. Key Features & Functional Requirements

### 4.1 Automated Ingestion
- **Native Share Sheet:** Android/iOS intent receiver (`receive_sharing_intent`) allows sharing directly to Cachy from any app.
- **Instagram Auto-Save Bot:** Users link their Instagram handle in their profile and DM reels to `@cachyapp`. The server approves pending message requests, extracts reel links, enqueues ingestion, and sends a confirmation reply DM.
- **Supported Media:** Instagram Reels/Posts, TikTok videos, YouTube Shorts, and standard web articles (extracted via `trafilatura`).

### 4.2 Ingestion & Processing Pipeline
1. **Ingest:** Download video/audio via `yt-dlp` / keyless resolvers or scrape clean article text.
2. **Extract:** Audio transcription via Groq Whisper (`whisper-large-v3-turbo`) or local `faster-whisper`; video keyframes and OCR via OpenCV and `pytesseract`.
3. **Structure:** LLM structures raw data into typed blocks (`HeadingBlock`, `ParagraphBlock`, `StepListBlock`, `KeyValueBlock`, `ChecklistBlock`, `CalloutBlock`, `MapBlock`, `TableBlock`).
4. **Insight Pass:** Generates rabbit-hole discussion threads and interactive multiple-choice quiz questions.
5. **Catalog & Concepts:** Extracts referenced artifacts (books, movies, tools) and key conceptual nodes.
6. **Embeddings:** Generates semantic embeddings (`BAAI/bge-small-en-v1.5`) for vector search and graph clustering.

### 4.3 Interactive Knowledge Graph
- Visual representation of cards, concepts, and artifacts.
- Links created via semantic cosine similarity (threshold `0.26`–`0.66`), shared tags, and artifact references.
- Force-directed physics simulation rendered client-side in Flutter.
- Cluster detection via pure-Python label propagation.

### 4.4 Knowledge Feed & Serendipity
- A TikTok/Reel-style vertical feed that replays your own saved cards back to you in bite-sized moments (Key Insights, Quiz questions, Highlights, and Serendipity connections).
- **Serendipity Engine:** Discovers surprising conceptual bridges between two unrelated cards (e.g., linking a cooking card to a productivity framework).

### 4.5 Sharing & Public Access
- Public card sharing via unique short URLs (`/share/{id}`).
- Responsive web reader with action item extraction, reference links, and "Clone to My Cachy" functionality.
- Android App Links integration (`/.well-known/assetlinks.json`) to open shared links natively in the mobile app.

### 4.6 Dual Authentication
- **Firebase Auth:** Anonymous-first authentication with optional one-tap Google Account linking.
- **Cachy ID:** Privacy-focused username/password authentication for users avoiding third-party identity providers.

### 4.7 On-Device Local AI
- Integrated Google Gemma 3 1B on-device model (`flutter_gemma`).
- If cloud daily quotas are exceeded, the mobile client structures raw extraction bundles locally on-device.

---

## 5. Non-Functional Requirements

### 5.1 Performance & Latency
- Ingestion pipeline time: < 30 seconds for standard 60-second video.
- Real-time pipeline updates streamed via Server-Sent Events (SSE).
- Search query latency: < 150ms over 1,000+ local cards.

### 5.2 Scalability & Resource Discipline
- Backend runnable on a single free Hugging Face Space (CPU tier, 16GB RAM).
- In-process `asyncio` background queue avoiding heavy external broker dependencies (Redis/Celery).
- Serverless database idle backoff (up to 30 min) to protect scale-to-zero Neon Postgres compute limits.

### 5.3 Reliability & Privacy
- Source video files discarded immediately after keyframe extraction and audio transcription; zero permanent raw video storage.
- All data isolated by `owner_id` with verified identity headers on all mutating routes.
