# Deployment & Operations Guide — Cachy

**Version:** 2.0  
**Hosting Platforms:** Hugging Face Spaces (Backend + Web), Cloudflare (Website), Neon (PostgreSQL)  

---

## 1. Cloud Deployment on Hugging Face Spaces

Cachy is designed to deploy entirely on a **free-tier Hugging Face Space** (Docker SDK, CPU-only, 16GB RAM).

### 1.1 One-Command Deployment Script
The repository includes a dedicated release script: [`deploy_hf.sh`](file:///Users/vatsal/MyStuff/Android_Apps/Cachy/deploy_hf.sh).

```bash
./deploy_hf.sh "feat: describe changes"
```

**What the script does automatically:**
1. Compiles Flutter Web in release mode with relative API base (`CACHY_API_BASE=`).
2. Syncs the build artifacts into `web_dist/`.
3. Creates a detached Git commit so the local Git branch remains clean of compiled JS/Wasm binaries.
4. Force-pushes the detached HEAD to the Hugging Face remote (`hf HEAD:main`).
5. Hugging Face detects the push, builds the Docker container, and restarts the service in ~2–3 minutes.

---

## 2. Environment Variables & Secrets Reference

Set these in your Hugging Face Space: **Settings → Variables and secrets**.

| Variable Name | Type | Description |
|---|---|---|
| `DATABASE_URL` | Secret | Neon PostgreSQL async connection string (`postgresql+asyncpg://user:pass@ep-...neon.tech/neondb?ssl=require`). |
| `FIREBASE_PROJECT_ID` | Variable | Public Firebase project ID (e.g. `cachy-057`) for verifying Google ID tokens. |
| `GROQ_API_KEY` | Secret | Groq API key for fast Whisper audio transcription (`whisper-large-v3-turbo`). |
| `CEREBRAS_API_KEY` | Secret | Cerebras key for high-throughput Llama 3.3 70B structuring fallback. |
| `GEMINI_KVA` | Secret | Primary Google Gemini 2.5 Flash API key for card structuring. |
| `GEMINI_JK` | Secret | Google Gemini key for video vision and bundle preprocessing. |
| `GEMINI_VPN` | Secret | Spare Google Gemini API key (pool fallback). |
| `HF_API_KEY` | Secret | Hugging Face user access token for semantic search embeddings and media persistence. |
| `HF_MEDIA_REPO` | Variable | Optional private HF dataset repo (e.g. `username/cachy-media`) for persistent image storage. |
| `IG_SESSION_DATA` | Secret | Raw JSON contents of `ig_session.json` to authenticate `@cachyapp` without triggering login challenges. |
| `IG_BOT_USERNAME` | Variable | Instagram bot username (e.g. `cachyapp`). |
| `IG_BOT_PASSWORD` | Secret | Instagram bot password fallback. |
| `IG_PROXY` | Secret | Optional HTTP/SOCKS5 residential proxy string to bypass cloud datacenter IP firewalls. |

---

## 3. Database Management & Migrations

### 3.1 Initializing a New Neon Postgres Instance
To apply the database schema to a new PostgreSQL host:
```bash
cd backend
python scripts/migrate_postgres.py --url "$DATABASE_URL"
```

### 3.2 Ephemeral Local Development
If `DATABASE_URL` is omitted in local development:
- Cachy defaults to a local SQLite database at `backend/cachy.db`.
- All tables are auto-created on application startup via `db.init_db()`.

---

## 4. Mobile App Build & Release (Android APK)

To build the standalone release APK for sideloading:
```bash
cd app
flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```
The compiled APK will be located at:
`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
