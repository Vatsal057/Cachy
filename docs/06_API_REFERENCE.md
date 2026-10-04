# REST API & Streaming Reference — Cachy

**Version:** 2.0 (Schema Version: `1.6`)  
**Base URL:** `https://vatxzz-cachy.hf.space` (or local `http://localhost:8000`)  
**Authentication Header:** `Authorization: Bearer <TOKEN>`  
*(Supports both Firebase ID Tokens and Cachy ID JWTs)*  

---

## 1. Authentication & Identity (`/id` & `/auth`)

### 1.1 Cachy ID Register
- **Endpoint:** `POST /id/register`
- **Rate Limit:** 20 requests / 60 seconds per IP
- **Request Body:**
  ```json
  {
    "username": "vatsal",
    "password": "secure_password_123"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "uid": "cid_9a8b7c6d5e4f",
    "username": "vatsal",
    "recovery_code": "cachy-recov-a1b2-c3d4-e5f6"
  }
  ```
  *(Note: Passwords and recovery codes are hashed via argon2id. Recovery code is displayed once).*

### 1.2 Cachy ID Login
- **Endpoint:** `POST /id/login`
- **Request Body:** `{"username": "vatsal", "password": "secure_password_123"}`
- **Security:** Returns generic 401 with constant-time dummy verification on nonexistent users. Account locks for 15 minutes after 5 failed attempts.
- **Response (200 OK):**
  ```json
  {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "uid": "cid_9a8b7c6d5e4f",
    "username": "vatsal"
  }
  ```

### 1.3 Cachy ID Password Reset
- **Endpoint:** `POST /id/reset`
- **Request Body:** `{"username": "vatsal", "recovery_code": "cachy-recov-...", "new_password": "..."}`
- **Response (200 OK):** `{"token": "...", "uid": "...", "username": "vatsal"}`

### 1.4 Legacy Claim & Guest Merge (`/auth`)
- `POST /auth/claim`: Adopts pre-auth rows keyed by display name (`{"name": "Vatsal"}`). Gated behind `LEGACY_CLAIM_ENABLED`.
- `POST /auth/merge`: Merges an anonymous guest library into the authenticated user account (`{"guest_token": "..."}`).

---

## 2. Card Management & Processing (`/cards`)

### 2.1 Create Card (Enqueue Job)
- **Endpoint:** `POST /cards`
- **Request Body:**
  ```json
  {
    "url": "https://www.instagram.com/reel/DeB6QU6N4Ec/",
    "prefer_local": false
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "card_id": "2feab105-18e8-471c-b291-239fe775a6d1",
    "state": "queued",
    "cached": false,
    "quota_degraded": false
  }
  ```

### 2.2 Stream Pipeline Events (Server-Sent Events)
- **Endpoint:** `GET /cards/{card_id}/stream`
- **Event format:** `data: {"stage": "ingest" | "extract" | "structure" | "insight" | "catalog" | "ready" | "failed", "progress": 0.5, "message": "..."}\n\n`

### 2.3 List Cards
- **Endpoint:** `GET /cards?limit=50&offset=0&collection_id=optional_uuid`
- **Response (200 OK):** Array of full `Card` objects ordered by `created_at DESC`.

### 2.4 Get Card
- **Endpoint:** `GET /cards/{card_id}`
- **Response (200 OK):** Complete Card model including typed blocks, tags, insight layer, and action items.

### 2.5 Patch Card (User Edits, Checklists, Collections)
- **Endpoint:** `PATCH /cards/{card_id}`
- **Request Body:**
  ```json
  {
    "blocks": [...],
    "action_items": {"followed": true, "items": [{"id": "act_1", "text": "Buy basil", "done": true}]},
    "collection_id": "coll_uuid",
    "clear_collection": false
  }
  ```

### 2.6 Delete Card
- **Endpoint:** `DELETE /cards/{card_id}`
- **Action:** Deletes card, job rows, share links, local thumbnails/keyframes, and remote Hugging Face dataset media. Invalidates graph cache.

### 2.7 Fetch Raw Extraction Bundle (On-Device AI)
- **Endpoint:** `GET /cards/{card_id}/bundle`
- **Purpose:** Fetches raw transcript, OCR text, and caption for quota-degraded cards to allow on-device structuring via Google Gemma 3 1B.

### 2.8 Upload On-Device Structured Card
- **Endpoint:** `POST /cards/{card_id}/structure`
- **Request Body:** Device-generated card payload. Server validates with standard LLM schema rules, embeds card for semantic search, and removes raw bundle.

### 2.9 Single Card AI Chat & History
- `POST /cards/{card_id}/chat`: `{"messages": [{"role": "user", "content": "..."}]}` → `{"reply": "..."}`
- `GET /cards/{card_id}/chat`: Restores card conversation history.

### 2.10 Exploratory "Rabbit Hole" Threads
- `POST /cards/{card_id}/rabbithole`: `{"topic": "...", "trail": ["step1", "step2"], "root": "..."}` → `{"explanation": "...", "threads": ["next1", "next2"]}`
- `GET /cards/{card_id}/rabbithole?root=...`: Restores the multi-step branching research trail.

### 2.11 Bulk Import
- **Endpoint:** `POST /cards/import`
- **Request Body:** `{"cards": [...]}` (Capped at 1,000 cards; used for local device backup restoration).

---

## 3. Public Sharing (`/cards/{id}/share` & `/s/{token}`)

| Endpoint | Method | Scope | Purpose |
|---|---|---|---|
| `/cards/{card_id}/share` | `POST` | Owner | Create or retrieve active unlisted share link. |
| `/cards/{card_id}/share` | `GET` | Owner | Fetch active link details. |
| `/cards/{card_id}/share` | `DELETE` | Owner | Revoke and deactivate share link. |
| `/share/{token}` | `GET` | Public | Returns clean JSON card payload for in-app preview sheets. |
| `/share/{token}/save` | `POST` | Auth | Clones card into caller's library (zero quota charge). |
| `/s/{token}` | `GET` | Public | Server-rendered HTML reader with OpenGraph tags for rich social previews. |
| `/s/{token}/media/{name}`| `GET` | Public | Token-gated thumbnail and keyframe streaming. |
| `/.well-known/assetlinks.json` | `GET` | Public | Android Verified App Links configuration. |

---

## 4. Knowledge Graph, Feed & Search

### 4.1 Knowledge Graph
- **Endpoint:** `GET /graph`
- **Response:** `{"nodes": [...], "edges": [...], "clusters": [...]}`
- **Edge Types:** Semantic cosine similarity (`0.26`–`0.66`), catalog artifact reference links, and tag co-occurrence.

### 4.2 Serendipity Connections
- **Endpoint:** `GET /connections`
- **Response:** Array of cross-card conceptual bridges with AI-generated connective explanations.

### 4.3 Knowledge Replay Feed
- **Endpoint:** `GET /feed`
- **Response:** Stream of shuffled, zero-LLM-cost moments: `insight`, `highlight`, `quiz`, `thread`, and `connection`.

### 4.4 Library Chat
- **Endpoint:** `POST /chat` & `GET /chat`
- **Purpose:** Full-library conversational Q&A synthesizing insights across multiple saved cards.

### 4.5 Hybrid Search
- **Endpoint:** `GET /search?q=query`
- **Response:** Combined vector semantic matches (`BAAI/bge-small-en-v1.5`) and full-text keyword matches.

---

## 5. Account & Infrastructure Management

### 5.1 Quota & Usage
- **Endpoint:** `GET /me/quota`
- **Response:** `{"cards_remaining": 8, "cards_limit": 10, "chat_remaining": 28, "chat_limit": 30, "ip_cards_remaining": 24}`

### 5.2 Instagram Auto-Save Handle
- `GET /me/instagram`: Returns linked handle (`{"handle": "vatxzz"}`).
- `POST /me/instagram`: Links username (`{"handle": "vatxzz"}`).
- `DELETE /me/instagram`: Unlinks Instagram handle.

### 5.3 Owner-Checked Media Proxy
- **Endpoint:** `GET /media/{card_id}/{filename}`
- **Security:** Verifies caller owns `card_id`, then streams keyframes/thumbnails securely from the private Hugging Face Dataset repository.

### 5.4 Self-Driving Presenter Mode
- **Endpoint:** `POST /presenter/ask`
- **Request Body:** `{"prompt": "Show me recipes", "history": [...]}`
- **Response:** Ordered list of `{say: "...", action: "navigate|search|open_card|filter_graph|..."}` beats executed client-side.
