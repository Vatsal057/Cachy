# REST API & Streaming Reference — Cachy

**Version:** 2.0  
**Base URL:** `https://vatxzz-cachy.hf.space` (or local `http://localhost:8000`)  
**Authentication:** `Authorization: Bearer <FIREBASE_ID_TOKEN | CACHY_ID_TOKEN>`  

---

## 1. Cards API (`/cards`)

### Create Card
- **Endpoint:** `POST /cards`
- **Request Body:**
  ```json
  {
    "url": "https://www.instagram.com/reel/DeB6QU6N4Ec/",
    "notes": "Optional manual user note"
  }
  ```
- **Response (201 Created):**
  ```json
  {
    "id": "2feab105-18e8-471c-b291-239fe775a6d1",
    "state": "queued",
    "title": "Ingesting media...",
    "source_url": "https://www.instagram.com/reel/DeB6QU6N4Ec/",
    "created_at": "2026-10-04T05:52:40Z"
  }
  ```

### Stream Pipeline Progress (Server-Sent Events)
- **Endpoint:** `GET /cards/{id}/stream`
- **Headers:** `Accept: text/event-stream`
- **Event Payload:**
  ```json
  event: progress
  data: {"stage": "extract", "message": "Transcribing audio...", "progress": 0.4}

  event: ready
  data: {"stage": "ready", "card": {...}}
  ```

### List User Cards
- **Endpoint:** `GET /cards?limit=50&offset=0&collection_id=optional_uuid`
- **Response (200 OK):** Array of `Card` objects ordered by `created_at DESC`.

### Get Card Details
- **Endpoint:** `GET /cards/{id}`
- **Response (200 OK):** Full card object including typed blocks, tags, concepts, and media links.

### Update Card
- **Endpoint:** `PATCH /cards/{id}`
- **Request Body:**
  ```json
  {
    "title": "Custom Title",
    "tags": ["recipes", "quick"]
  }
  ```

### Delete Card
- **Endpoint:** `DELETE /cards/{id}`
- **Response:** `204 No Content`

### Card AI Chat
- **Endpoint:** `POST /cards/{id}/chat`
- **Request Body:** `{"message": "What temperature should the oven be set to?"}`
- **Response:** `{"reply": "Set the oven to 375°F (190°C) as noted in step 3."}`

---

## 2. Profile & Instagram Account Linking (`/me`)

### Get Current User Quota
- **Endpoint:** `GET /me/quota`
- **Response:**
  ```json
  {
    "cards_remaining": 8,
    "cards_limit": 10,
    "chat_remaining": 28,
    "chat_limit": 30,
    "ip_cards_remaining": 24,
    "ip_cards_limit": 30
  }
  ```

### Get Linked Instagram Handle
- **Endpoint:** `GET /me/instagram`
- **Response:** `{"handle": "vatxzz"}` or `{"handle": null}`

### Link Instagram Handle
- **Endpoint:** `POST /me/instagram`
- **Request Body:** `{"handle": "vatxzz"}`
- **Response:** `{"handle": "vatxzz", "message": "Linked successfully. Send reels to @cachyapp to auto-save."}`

### Unlink Instagram Handle
- **Endpoint:** `DELETE /me/instagram`
- **Response:** `{"message": "Instagram handle unlinked."}`

---

## 3. Public Sharing (`/share`)

### Create Share Link
- **Endpoint:** `POST /cards/{id}/share`
- **Response:**
  ```json
  {
    "share_url": "https://vatxzz-cachy.hf.space/share/a1b2c3d4",
    "token": "a1b2c3d4"
  }
  ```

### View Shared Card (Public)
- **Endpoint:** `GET /share/{token}` (or browser request)
- **Response:** Renders responsive Web reader or returns public card JSON payload.

### Clone Shared Card to Library
- **Endpoint:** `POST /share/{token}/clone`
- **Headers:** Requires authenticated user Bearer token
- **Response:** `{"card_id": "new_cloned_uuid", "status": "cloned"}`

---

## 4. Knowledge Discovery & Replay

### Get Knowledge Feed
- **Endpoint:** `GET /feed`
- **Response:** Ordered stream of shuffled moments (`insight`, `highlight`, `quiz`, `thread`, `connection`).

### Get Knowledge Graph
- **Endpoint:** `GET /graph`
- **Response:** Topology containing `nodes`, `edges`, and `clusters` calculated via label propagation.

### Search Library
- **Endpoint:** `GET /search?q=machine+learning`
- **Response:** Hybrid search results ranking vector semantic matches and full-text matches.
