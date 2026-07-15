# Hugging Face Spaces (Docker, free tier). CPU-only, ephemeral FS.
FROM python:3.11-slim

# System deps: ffmpeg (audio+frames), tesseract (OCR). Both free, local.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg \
        tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
RUN pip install --no-cache-dir .

COPY app ./app

ENV MEDIA_DIR=/data/downloads
# DATABASE_URL is intentionally NOT set here — set it as an HF Space secret to the
# Neon postgres URL (postgresql+asyncpg://...). Never hardcode it (holds a
# password). Without the secret the app falls back to ephemeral local SQLite.
RUN mkdir -p /data/downloads

# HF Spaces expects the app on 7860.
EXPOSE 7860
# --proxy-headers + trust the HF Spaces router so request.client.host is the real
# client IP (not the proxy) — the per-IP card quota depends on it (M9).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860", "--proxy-headers", "--forwarded-allow-ips", "*"]
