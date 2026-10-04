# Authentication & Security Architecture — Cachy

**Version:** 2.0  
**Stack:** Firebase Auth (JWT), Cachy ID (Password Hashing), FastAPI Dependencies  

---

## 1. Dual Identity System

Cachy supports two authentication models, allowing both frictionless onboarding and private, independent account ownership.

```
                    ┌─────────────────────────────────┐
                    │      Client Identity Gate       │
                    └────────────────┬────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 ▼                                       ▼
    ┌─────────────────────────┐             ┌─────────────────────────┐
    │     Firebase Auth       │             │       Cachy ID          │
    │ • Anonymous-first       │             │ • Independent username  │
    │ • One-tap Google link   │             │   and password          │
    │ • Public Project ID     │             │ • Salted PBKDF2/scrypt  │
    └────────────┬────────────┘             └────────────┬────────────┘
                 │ Bearer ID Token                       │ Bearer Token
                 └───────────────────┬───────────────────┘
                                     ▼
                        ┌─────────────────────────┐
                        │   FastAPI `get_owner`   │
                        │      Dependency         │
                        └────────────┬────────────┘
                                     ▼
                        [Verified owner_id string]
```

---

## 2. Authentication Implementations

### 2.1 Firebase Anonymous-First Auth
1. **Silent Onboarding:** When a user opens Cachy for the first time, `AuthService` creates an anonymous Firebase user. The user can immediately capture cards without hitting a login screen.
2. **Account Linking:** In the Profile screen, the user can link their Google Account to their anonymous account with one tap, preserving their existing cards while securing access across devices.

### 2.2 Cachy ID Authentication
For users who prefer avoiding Google / Firebase services:
- **Registration (`POST /auth/cachy-id/register`)**: Creates an account with a unique username and hashed password.
- **Login (`POST /auth/cachy-id/login`)**: Validates credentials and returns an authenticated Bearer token.
- **Header Transport**: Passed as `Authorization: Bearer cachy_id:<token>`.

### 2.3 The `OwnerDep` Route Guard
All data routes (Cards, Collections, Concepts, Chat, Instagram linking) inject the `OwnerDep` FastAPI dependency:
```python
async def get_owner(request: Request, authorization: str | None = Header(None)) -> str:
    # 1. Inspect Authorization Bearer header
    # 2. Check for Cachy ID token
    # 3. Check for Firebase JWT (validated against Google public certs)
    # 4. Return normalized owner_id string or raise 401 Unauthorized
```

---

## 3. Quotas & Abuse Prevention

1. **IP-Level Daily Cap (`quota_ip_cards_per_day = 30`)**:
   - Tracked via `X-Forwarded-For` header trusted behind Hugging Face Spaces proxy.
   - Prevents automated scrapers from overwhelming the free CPU worker.
2. **User Daily Card Quota (`quota_cards_per_day = 10`)**:
   - Authenticated free users receive 10 fully AI-structured cards per UTC day.
   - Any submissions beyond this quota automatically degrade (`degraded=True`) to on-device structuring or raw text.
3. **Chat Daily Quota (`quota_chat_per_day = 30`)**:
   - Caps AI chat queries per day to keep inference costs at zero.

---

## 4. Secret & Credential Management

- **Zero Secret Commits:** All secrets (`DATABASE_URL`, `HF_API_KEY`, `IG_SESSION_DATA`, `GROQ_API_KEY`) are managed via environment variables and Hugging Face Space Secrets.
- **Neon Postgres Connection:** `DATABASE_URL` uses SSL parameters (`postgresql+asyncpg://...`) and is never committed to Git.
- **Ephemeral Video Purging:** Video files downloaded during ingestion are purged immediately after transcription; raw media is never stored on disk or exposed to the network.
