"""Shared test fixtures. Each test session gets an isolated temp SQLite DB and a
temp media dir, with no API keys — so the whole suite runs offline and the
graceful-degradation paths are exercised by default."""

from __future__ import annotations

import os
import tempfile

import pytest

# Configure env BEFORE app modules import settings.
_TMP = tempfile.mkdtemp(prefix="cachy_test_")
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{_TMP}/test.db"
os.environ["MEDIA_DIR"] = f"{_TMP}/media"
# Pin every external backend off so the suite runs offline and exercises the
# graceful-degradation paths — these override any real key in a developer's .env.
os.environ["LLM_BACKEND"] = "none"
os.environ["HF_API_KEY"] = ""
os.environ["GROQ_API_KEY"] = ""
os.environ["WHISPER_BACKEND"] = "none"
os.environ["MAX_ATTEMPTS"] = "2"

from app.config import get_settings  # noqa: E402
from app.store import db  # noqa: E402

get_settings.cache_clear()


@pytest.fixture
async def database():
    await db.init_db()
    yield db
    await db.dispose_db()
