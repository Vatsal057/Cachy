# Cachy Deployment to Hugging Face

Deploy Cachy backend to HF Spaces. Frontend (Flutter APK) points at the deployed backend URL.

## Backend Setup on HF

### Create Space
1. [huggingface.co/new-space](https://huggingface.co/new-space)
2. **Space name:** `cachy` (or your choice)
3. **License:** MIT
4. **Space SDK:** Docker
5. **Visibility:** Public (or Private if preferred)

### Dockerfile

Create `Dockerfile` in repo root:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install backend deps
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend ./

# Expose API
EXPOSE 7860

# Run FastAPI via uvicorn on port 7860 (HF default)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
```

### requirements.txt

Ensure `backend/requirements.txt` exists with all deps:
```
fastapi
uvicorn[standard]
sqlalchemy
pydantic
huggingface-hub
groq
# ... (all others)
```

### Push to HF

```bash
cd <repo>
git remote add hf https://huggingface.co/spaces/<username>/cachy
git push hf main
```

HF auto-builds and deploys. Check the Space URL: `https://<username>-cachy.hf.space`

## Frontend Build & Release

### Build APK

```bash
cd app
flutter build apk --release \
  --dart-define=CACHY_API_BASE=https://<username>-cachy.hf.space
```

### Install on Phone

```bash
adb install build/app/outputs/flutter-app/release/app-release.apk
```

## How It Works

- **Backend:** FastAPI on HF, no changes from local. LAN discovery is disabled (no phone on same network as HF).
- **Frontend:** APK hardcodes the HF Space URL at build time.
- **Local testing:** Run `./start.py` locally; phone auto-discovers via UDP broadcast. LAN discovery is skipped when `CACHY_API_BASE` is set (production deploy).

## Environment Variables

Backend respects these on startup:

- `CACHY_LAN_DISCOVERY=0` — Disable UDP responder (harmless to leave on; set to 0 if you prefer).
- `CACHY_HTTP_PORT=7860` — Custom HTTP port (HF uses 7860; uvicorn defaults to 8000 locally).
- `HF_API_KEY` — Hugging Face inference API key (for LLM calls).
- `GROQ_API_KEY` — Groq fallback LLM key.

Set these in HF Space **Settings → Repository secrets**.

## Graph & Concepts

- **Graph backbone:** Concepts (shared ideas), not folders. Cards orbit the concepts they discuss.
- **Wikilinks:** `[[idea]]` in card text resolves to concept pages (tap in reader opens the concept + all cards sharing it).
- **Folders:** Removed from graph (visual clutter). Cards grouped by content-type color.
- **Semantic edges:** Demoted to faint secondary layer (sparse, high threshold).

## Troubleshooting

### Backend won't start on HF
- Check `requirements.txt` has all imports from `app/`.
- Check HF logs: **Space → Logs**.
- Ensure `CACHY_LAN_DISCOVERY=0` or omit (discovery won't reach HF anyway).

### Phone can't reach backend
- Verify APK was built with correct `CACHY_API_BASE` (HF Space URL).
- Check HF Space is Public (or authenticate if Private).
- Check CORS isn't blocking (backend allows `*` origin in dev; tighten before real deploy).

### LLM calls fail
- Verify `HF_API_KEY` + `GROQ_API_KEY` are set in Space secrets.
- Test with `curl https://<space>/health` — should return `{"status":"ok"}`.

## Notes

- **Media:** Thumbnails are ephemeral (survive only container lifetime on HF free tier). Backfill on next deploy.
- **Database:** SQLite in-container. Persists across restarts but deleted on redeploy. For production, mount a persistent volume or use Postgres.
- **Cold starts:** HF free tier sleeps after inactivity. Phone requests wake it (~1-2s first hit).
