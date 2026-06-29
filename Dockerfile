# Hugging Face Spaces (Docker SDK). CPU-only, ephemeral FS.
# For persistent storage: enable the HF Spaces persistent storage addon ($1/mo)
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

RUN mkdir -p /data/downloads

ENV MEDIA_DIR=/data/downloads
ENV DATABASE_URL=sqlite+aiosqlite:////data/cachy.db

# HF Spaces routes external traffic to port 7860.
EXPOSE 7860
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
