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
# Pin every external backend off so the suite runs offline and exercises the
# graceful-degradation paths — these override any real key in a developer's .env.
os.environ["LLM_BACKEND"] = "none"
os.environ["HF_API_KEY"] = ""
os.environ["GROQ_API_KEY"] = ""
os.environ["CEREBRAS_API_KEY"] = ""
for _gemini_var in ("GEMINI_JK", "GEMINI_KVA", "GEMINI_VPN", "GEMINI_VVA", "GEMINI_VV", "GEMINI_D08", "GEMINI_DVU"):
    os.environ[_gemini_var] = ""
os.environ["WHISPER_BACKEND"] = "none"
os.environ["MAX_ATTEMPTS"] = "2"

from typing import Annotated  # noqa: E402

import httpx  # noqa: E402
from fastapi import Header  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.store import db  # noqa: E402

get_settings.cache_clear()


def _fake_owner(x_owner_id: Annotated[str | None, Header()] = None) -> str:
    """Test identity: uid from the x-owner-id header, else a fixed test uid."""
    return x_owner_id or "test-user"


@pytest.fixture
async def database(tmp_path, monkeypatch: pytest.MonkeyPatch):
    """Isolated per-test database: fresh temp SQLite file, engine rebuilt."""
    monkeypatch.setenv("DATABASE_URL", f"sqlite+aiosqlite:///{tmp_path}/test.db")
    get_settings.cache_clear()
    await db.dispose_db()
    await db.init_db()
    yield db
    await db.dispose_db()
    get_settings.cache_clear()


@pytest.fixture
async def client(database):
    """App-bound HTTP client on the isolated per-test database.

    Auth is stubbed: the test uid comes from the x-owner-id header (legacy test
    convention), defaulting to "test-user". Tests exercising real auth behavior
    reassign or delete app.dependency_overrides[get_owner] themselves.
    """
    from app.auth import get_owner
    from app.main import app

    app.dependency_overrides[get_owner] = _fake_owner
    transport = httpx.ASGITransport(app=app)
    try:
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
            yield c
    finally:
        app.dependency_overrides.clear()
