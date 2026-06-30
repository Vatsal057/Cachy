"""Env-driven settings. Free-first: every external dependency is optional and the
app degrades gracefully when a key is absent (see docs/11)."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # storage — set DATABASE_URL=postgresql+asyncpg://... for Neon/persistent DB
    database_url: str = "sqlite+aiosqlite:///./cachy.db"
    media_dir: str = "./downloads"
    # HF Dataset repo for persistent media (thumbnails + keyframes).
    # Create a public dataset repo e.g. "yourname/cachy-media". Reuses hf_api_key.
    hf_media_repo: str = "Vatxzz/cachy-media"

    # transcription
    whisper_backend: str = "groq"  # none | groq
    groq_api_key: str = ""
    groq_whisper_model: str = "whisper-large-v3-turbo"

    # structuring LLM — note generation: Cerebras primary (60k TPM, reliable 70b
    # JSON), Groq fallback. HF stays for the other services (catalog/chat/concept/
    # embeddings) but is no longer in the note-generation path.
    cerebras_api_key: str = ""
    cerebras_llm_model: str = "gpt-oss-120b"
    llm_backend: str = "huggingface"  # huggingface | groq | none (legacy services)
    hf_api_key: str = ""
    hf_model: str = "Qwen/Qwen2.5-72B-Instruct"
    groq_llm_model: str = "llama-3.3-70b-versatile"  # structuring fallback

    # bundle preprocessor (Gemini 3.x Flash Lite — 500 RPD / 250k TPM, separate
    # quota pool): dedupe + strip filler on the fat bundle before structuring.
    # Reuses gemini_api_key. Failure -> raw bundle passed through (never blocks).
    gemini_preprocess_model: str = "gemini-flash-lite-latest"

    # vision reader for stylized carousel slides (free Groq tier; reuses groq_api_key)
    groq_vision_model: str = "meta-llama/llama-4-scout-17b-16e-instruct"

    # Gemini vision (generous free tier: 1M TPM / 1500 req/day)
    gemini_api_key: str = ""
    gemini_vision_model: str = "gemini-2.0-flash-lite"

    # NVIDIA NVLM vision (OpenAI-compatible; free credits at integrate.api.nvidia.com)
    nvidia_api_key: str = ""
    nvidia_vision_model: str = "nvidia/nvlm-d-72b"

    # local Whisper via faster-whisper (no API, no rate limits)
    # tiny=39MB | base=74MB | small=244MB
    local_whisper_model: str = "base"

    # semantic search embeddings (free, reuses hf_api_key; docs/09)
    embedding_model: str = "BAAI/bge-small-en-v1.5"

    # ingestion
    rapidapi_key: str = ""
    cookies_path: str = ""
    reddit_client_id: str = ""
    reddit_client_secret: str = ""

    # worker / queue
    max_attempts: int = 3
    worker_poll_seconds: float = 1.0
    job_timeout_seconds: int = 300

    # misc
    discard_source_video: bool = True

    @property
    def hf_media_enabled(self) -> bool:
        return bool(self.hf_media_repo and self.hf_api_key)

    @property
    def groq_enabled(self) -> bool:
        return self.whisper_backend == "groq" and bool(self.groq_api_key.strip())

    @property
    def hf_enabled(self) -> bool:
        return self.llm_backend == "huggingface" and bool(self.hf_api_key.strip())

    @property
    def groq_llm_enabled(self) -> bool:
        # Groq is usable whenever the key is present — both as primary (llm_backend=groq)
        # and as fallback when the primary backend (HF) fails.
        return bool(self.groq_api_key.strip())

    @property
    def cerebras_enabled(self) -> bool:
        # note-generation primary; needs only a Cerebras key, independent of llm_backend
        return bool(self.cerebras_api_key.strip())

    @property
    def gemini_preprocess_enabled(self) -> bool:
        return bool(self.gemini_api_key.strip())

    @property
    def groq_vision_enabled(self) -> bool:
        # vision only needs a Groq key, independent of the structuring backend
        return bool(self.groq_api_key.strip())

    @property
    def gemini_vision_enabled(self) -> bool:
        return bool(self.gemini_api_key.strip())

    @property
    def nvidia_vision_enabled(self) -> bool:
        return bool(self.nvidia_api_key.strip())

    @property
    def local_whisper_enabled(self) -> bool:
        return self.whisper_backend == "local"


@lru_cache
def get_settings() -> Settings:
    return Settings()
