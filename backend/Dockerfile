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
ENV DATABASE_URL=sqlite+aiosqlite:////data/cachy.db
RUN mkdir -p /data/downloads

# HF Spaces expects the app on 7860.
EXPOSE 7860
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
