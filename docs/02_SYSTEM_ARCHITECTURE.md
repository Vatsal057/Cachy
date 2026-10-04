# System Architecture Specification — Cachy

**Version:** 2.0  
**Stack:** Flutter (Dart), FastAPI (Python 3.11+), SQLite / Neon PostgreSQL, Hugging Face Spaces  

---

## 1. High-Level Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │             Clients                    │
                      │  • Flutter Android App (Sideload/APK)  │
                      │  • Flutter Web App (Hugging Face)      │
                      └──────────────────┬─────────────────────┘
                                         │ HTTPS / SSE
                                         ▼
                      ┌────────────────────────────────────────┐
                      │          FastAPI Backend               │
                      │  (Uvicorn, Port 7860, Python 3.11)      │
                      │  • REST API & Auth Verification         │
                      │  • Server-Sent Events (SSE) Stream      │
                      │  • In-Process Background Job Worker     │
                      │  • Instagram DM Poller (@cachyapp)      │
                      └────┬──────────────┬──────────────┬─────┘
                           │              │              │
             ┌─────────────┘              │              └──────────────┐
             ▼                            ▼                             ▼
┌─────────────────────────┐  ┌─────────────────────────┐  ┌─────────────────────────┐
│     Database Store      │  │    External AI & APIs   │  │   Cloud Media Storage   │
│  • Neon Serverless PG   │  │  • Gemini 2.5 Flash /   │  │  • Ephemeral /data/media │
│    (Production)         │  │    Flash Lite           │  │  • Hugging Face Dataset  │
│  • SQLite via aiosqlite │  │  • Cerebras Llama 3.3   │  │    (Optional Persistent) │
│    (Local Dev Fallback) │  │  • Groq Whisper Turbo   │  └─────────────────────────┘
└─────────────────────────┘  │  • BAAI BGE Embeddings  │
                             └─────────────────────────┘
```

---

## 2. Frontend Architecture (`/app`)

The frontend is a cross-platform Flutter client targeting **Android** and **Web**, designed with an **MVVM** pattern using `provider` and `ChangeNotifier`.

### 2.1 Directory Structure
- `lib/ui/core/`: Application shell, theme definitions (`theme.dart`, `brand.dart`), design tokens, and navigation router (`root_gate.dart`).
- `lib/ui/features/`: Modular, self-contained feature slices:
  - `library/`: Main bookshelf, grid/list view, filtering, and tag search.
  - `reader/`: Full card reading experience, interactive checkboxes, step execution, and deep-dive sheets.
  - `capture/`: URL submission dialog, real-time pipeline progress SSE listener.
  - `feed/`: Fullscreen vertical scroll stream replaying insights, highlights, and quizzes.
  - `graph/`: Interactive Obsidian-style force-directed physics graph.
  - `catalog/` & `concepts/`: Entity directories and concept definitions.
  - `share/`: Public card viewer and "Clone to Library" sheet.
  - `profile/`: Account settings, quota indicators, Instagram linking, and export options.
  - `presenter/`: Self-driving demo agent executing UI tours with voice synthesis.
- `lib/data/`: `ApiClient` (HTTP & SSE communication), `IdAuthService` (Cachy ID auth), `AuthService` (Firebase auth), and local cache repositories (`shared_preferences`).
- `lib/domain/models/`: Strongly-typed Dart domain models mirroring backend schemas.

---

## 3. Backend Architecture (`/backend/app`)

The backend is built with FastAPI and runs fully asynchronous using `asyncio` and `SQLAlchemy 2.0`.

### 3.1 Core Subsystems
1. **API Routers (`app/api/`)**:
   - `cards.py`: Card CRUD, SSE streaming (`/cards/{id}/stream`), chat, rabbit-hole queries.
   - `auth_routes.py`: Cachy ID registration, login, and verification.
   - `me.py`: Current user quota, profile, and Instagram handle linking.
   - `share_routes.py`: Public unauthenticated card viewing and cloning.
   - `feed.py`: Knowledge replay feed generation.
   - `graph.py`: Multi-entity knowledge graph calculation and clustering.
   - `search.py`: Semantic vector search and text search.
2. **Pipeline Worker (`app/pipeline/worker.py`)**:
   - An in-process background task running alongside the web server.
   - Implements exponential idle backoff (up to 1800s) to prevent burning serverless database compute hours when idle.
   - Processes jobs through 6 stages: Ingest → Extract → Structure → Insight → Catalog → Index.
3. **Instagram DM Poller (`app/services/ig_dm_poller.py`)**:
   - Background service running `instagrapi` to monitor `@cachyapp` DMs, approve message requests, and feed reels into the ingestion queue.
4. **Data Access (`app/store/db.py`)**:
   - Database connection management supporting async SQLite and async PostgreSQL (`postgresql+asyncpg://`).

---

## 4. Pipeline Stages & Ingestion Flow

```
[Incoming URL]
      │
      ▼
Stage 1: Ingest
      ├─► YouTube / Instagram / TikTok: yt-dlp + keyless scrapers (download video & audio)
      └─► Web Article: trafilatura (clean markdown text)
      │
      ▼
Stage 2: Extract
      ├─► Audio: Groq Whisper API (whisper-large-v3-turbo) → Local faster-whisper fallback
      ├─► Video Keyframes: OpenCV keyframe extraction
      └─► OCR: pytesseract on keyframes for stylized text & slide extraction
      │
      ▼
Stage 3: Structure (AI LLM Chain)
      ├─► Preprocess: Gemini Flash Lite strips conversational fluff
      └─► Schema Generation: Gemini 2.5 Flash → Cerebras Llama 3.3 → Groq Llama 3.3
      │
      ▼
Stage 4: Deep Insight Pass
      ├─► Discussion threads, rabbit-hole prompts, and interactive quizzes
      │
      ▼
Stage 5: Catalog & Concepts
      ├─► Extract referenced artifacts (books, movies, products, locations)
      └─► Extract core conceptual topics
      │
      ▼
Stage 6: Index & Embeddings
      ├─► BAAI/bge-small-en-v1.5 embedding generation
      └─► Persist to DB, emit CardState.READY SSE event, and purge ephemeral video files
```

---

## 5. Database Schema & Tables

- `cards`: Primary card storage (UUID, owner_id, title, summary, source_url, content_type, state, blocks JSON, media filenames).
- `jobs`: Background pipeline queue (card_id, state, attempts, error_message, updated_at).
- `cachy_users`: Cachy ID accounts (username, password_hash, created_at).
- `instagram_links`: Mappings from normalized Instagram handles to Cachy owner IDs.
- `shared_links`: Public card sharing tokens (share_token, card_id, owner_id, view_count).
- `concepts`: Extracted conceptual nodes with AI-generated definitions.
- `artifacts`: Catalog items (books, movies, tools) linked to cards.
- `connections`: Pre-calculated serendipity links between cards.
- `usage_daily`: Daily IP and user quota accounting.
