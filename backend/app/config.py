"""Env-driven settings. Free-first: every external dependency is optional and the
app degrades gracefully when a key is absent (see docs/11)."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # storage
    database_url: str = "sqlite+aiosqlite:///./cachy.db"
    media_dir: str = "./downloads"

    # transcription
    whisper_backend: str = "groq"  # none | groq
    groq_api_key: str = ""
    groq_whisper_model: str = "whisper-large-v3-turbo"

    # structuring LLM
    llm_backend: str = "huggingface"  # huggingface | groq | none
    hf_api_key: str = ""
    hf_model: str = "Qwen/Qwen2.5-72B-Instruct"

    # semantic search embeddings (free, reuses hf_api_key; docs/09)
    embedding_model: str = "BAAI/bge-small-en-v1.5"

    # ingestion
    rapidapi_key: str = ""
    cookies_path: str = ""

    # worker / queue
    max_attempts: int = 3
    worker_poll_seconds: float = 1.0
    job_timeout_seconds: int = 300

    # misc
    discard_source_video: bool = True

    @property
    def groq_enabled(self) -> bool:
        return self.whisper_backend == "groq" and bool(self.groq_api_key.strip())

    @property
    def hf_enabled(self) -> bool:
        return self.llm_backend == "huggingface" and bool(self.hf_api_key.strip())

    @property
    def groq_llm_enabled(self) -> bool:
        return self.llm_backend == "groq" and bool(self.groq_api_key.strip())


@lru_cache
def get_settings() -> Settings:
    return Settings()
