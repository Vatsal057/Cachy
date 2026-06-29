# Stage 1: Build Flutter web
# Empty CACHY_API_BASE → relative URLs → same-origin API calls
FROM ghcr.io/cirruslabs/flutter:3.29.3 AS flutter-build
WORKDIR /build
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ .
RUN flutter build web --release --dart-define=CACHY_API_BASE=

# Stage 2: Python backend (Hugging Face Spaces Docker SDK, CPU-only, ephemeral FS)
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

# Flutter web output served as SPA fallback after all API routes
COPY --from=flutter-build /build/build/web ./static

RUN mkdir -p /data/downloads

ENV MEDIA_DIR=/data/downloads
ENV DATABASE_URL=sqlite+aiosqlite:////data/cachy.db

EXPOSE 7860
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "7860"]
