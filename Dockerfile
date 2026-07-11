# Hugging Face Spaces (Docker SDK). CPU-only, ephemeral FS.
# Flutter web is pre-built locally by deploy_hf.sh and committed to web_dist/.
# For persistent storage: enable the HF Spaces persistent storage addon
# and set DATABASE_URL + MEDIA_DIR to point at the mounted /data volume.
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/pyproject.toml ./
COPY backend/app ./app
RUN pip install --no-cache-dir .

# Flutter web output (pre-built by deploy_hf.sh, served as SPA after API routes)
COPY web_dist ./static

RUN mkdir -p /data/downloads && chown -R 1000:1000 /data && chmod -R 777 /data

ENV MEDIA_DIR=/data/downloads
ENV DATABASE_URL=sqlite+aiosqlite:////data/cachy.db
# Firebase project id (public, not a secret) — enables ID-token verification on
# every data route. HF_API_KEY (media + embeddings) stays a Space secret.
ENV FIREBASE_PROJECT_ID=cachy-057

EXPOSE 7860
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
