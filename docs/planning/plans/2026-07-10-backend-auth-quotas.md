# Backend Auth + Quotas + Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the spoofable `x-owner-id` header with verified Firebase ID tokens, add per-user/per-IP daily quotas with degrade-to-fallback, and lock down admin/debug/error surfaces.

**Architecture:** A FastAPI dependency `get_owner` verifies the bearer token via `firebase_admin.auth.verify_id_token` and yields the uid; every route swaps its header param for this dependency. Quotas live in a new `usage` table keyed `(owner_id, day, kind)`; past-quota card creation flags the job `degraded` so the worker takes the existing paragraph-fallback path instead of failing. A temporary `/auth/claim` migrates legacy name-keyed rows.

**Tech Stack:** FastAPI, SQLAlchemy async + aiosqlite, firebase-admin, pytest + pytest-asyncio + httpx.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-10-public-distribution-auth-quotas-design.md`.
- Python style: type hints + docstrings on every function; explicit error handling (no `except: pass`); `pathlib.Path`; config only via `app.config.Settings` (pydantic-settings, `.env`).
- Quota defaults (env-overridable): cards 10/day, chat 30/day, connections-refresh 3/day, per-IP cards 30/day.
- `x-owner-id` header support is removed entirely; legacy name survives only as `/auth/claim`'s body parameter.
- Every external dependency optional / graceful degradation preserved: if `FIREBASE_PROJECT_ID` is unset, `get_owner` must raise 503 with "auth not configured" (never crash at import).
- Run tests with `cd backend && .venv/bin/pytest` after every task.
- Do not commit unless the user asked; each task's Commit step is conditional on that standing permission being granted at execution time.

---

### Task 1: Restore the pytest harness

**Files:**
- Create: `backend/tests/__init__.py` (empty)
- Create: `backend/tests/conftest.py`
- Create: `backend/tests/test_health.py`

**Interfaces:**
- Produces: `client` async fixture (httpx.AsyncClient against the app, fresh in-memory-style temp SQLite per test) used by every later test.

- [ ] **Step 1: Write conftest**

```python
"""Shared fixtures: temp-file SQLite DB + httpx client bound to the app.

The worker loop is not started (tests drive functions directly); lifespan is
bypassed by calling db.init_db() ourselves against a temp database file.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient


@pytest_asyncio.fixture
async def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> AsyncIterator[AsyncClient]:
    """App-bound HTTP client with an isolated database per test."""
    db_path = tmp_path / "test.db"
    monkeypatch.setenv("DATABASE_URL", f"sqlite+aiosqlite:///{db_path}")
    # Settings and the engine are cached at import; reset both.
    from app import config
    config.get_settings.cache_clear()
    from app.store import db as store_db
    await store_db.dispose_db()
    store_db.reset_engine()  # added in Step 2 if absent
    await store_db.init_db()

    from app.main import app
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    await store_db.dispose_db()
```

- [ ] **Step 2: Ensure `reset_engine` exists in `backend/app/store/db.py`**

Read `db.py`'s engine setup. If the engine/sessionmaker are module-level singletons built from `get_settings().database_url` at import, add:

```python
def reset_engine() -> None:
    """Rebuild the engine/sessionmaker from current settings (tests swap DATABASE_URL)."""
    global _engine, _session_factory
    _engine = create_async_engine(get_settings().database_url, future=True)
    _session_factory = async_sessionmaker(_engine, expire_on_commit=False)
```

Match the actual variable names used in `db.py` (`_engine` / `_session_factory` may differ — mirror what `dispose_db()` touches).

- [ ] **Step 3: Write the smoke test**

```python
"""Harness smoke test: the app answers /health on an isolated DB."""

import pytest


@pytest.mark.asyncio
async def test_health(client) -> None:
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
```

- [ ] **Step 4: Run**

Run: `cd backend && .venv/bin/pytest tests/test_health.py -v` — Expected: PASS. If `pytest-asyncio` mode errors appear, add to `backend/pyproject.toml` under `[tool.pytest.ini_options]`: `asyncio_mode = "auto"` (then the `@pytest.mark.asyncio` markers are optional but harmless).

- [ ] **Step 5: Commit** — `test: restore pytest harness with isolated per-test DB`

---

### Task 2: `get_owner` — Firebase token verification dependency

**Files:**
- Modify: `backend/pyproject.toml` (add `"firebase-admin>=6.5"` to dependencies)
- Modify: `backend/app/config.py` (add `firebase_project_id: str = ""`)
- Create: `backend/app/auth.py`
- Create: `backend/tests/test_auth.py`

**Interfaces:**
- Produces: `async def get_owner(authorization: str | None = Header(None)) -> str` — FastAPI dependency returning the verified uid; raises HTTPException 401 (missing/invalid token) or 503 (auth unconfigured). Also `OwnerDep = Annotated[str, Depends(get_owner)]` for route signatures.

- [ ] **Step 1: Write failing tests**

```python
"""get_owner: valid token -> uid; garbage/missing -> 401; unconfigured -> 503."""

from unittest.mock import patch

import pytest
from fastapi import HTTPException

from app.auth import get_owner


@pytest.mark.asyncio
async def test_missing_header_401() -> None:
    with pytest.raises(HTTPException) as exc:
        await get_owner(authorization=None)
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_valid_token_returns_uid(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-project")
    from app import config
    config.get_settings.cache_clear()
    with patch("app.auth._verify", return_value={"uid": "user-123"}):
        uid = await get_owner(authorization="Bearer sometoken")
    assert uid == "user-123"


@pytest.mark.asyncio
async def test_invalid_token_401(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-project")
    from app import config
    config.get_settings.cache_clear()
    with patch("app.auth._verify", side_effect=ValueError("bad token")):
        with pytest.raises(HTTPException) as exc:
            await get_owner(authorization="Bearer garbage")
    assert exc.value.status_code == 401


@pytest.mark.asyncio
async def test_unconfigured_503(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FIREBASE_PROJECT_ID", raising=False)
    from app import config
    config.get_settings.cache_clear()
    with pytest.raises(HTTPException) as exc:
        await get_owner(authorization="Bearer sometoken")
    assert exc.value.status_code == 503
```

- [ ] **Step 2: Run to verify failure** — `cd backend && .venv/bin/pytest tests/test_auth.py -v` — Expected: FAIL, `ModuleNotFoundError: app.auth`.

- [ ] **Step 3: Implement `backend/app/auth.py`**

```python
"""Verified identity: Firebase ID token -> uid.

The client sends `Authorization: Bearer <ID token>`; we verify the signature
against Google's public certs (firebase-admin handles fetching/rotation).
No service-account secret is needed for verification — only the project id.
"""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import Depends, Header, HTTPException

from app.config import get_settings

log = logging.getLogger("app.auth")

_initialized = False


def _verify(token: str) -> dict:
    """Verify a Firebase ID token, initializing the SDK lazily (once)."""
    global _initialized
    import firebase_admin
    from firebase_admin import auth as fb_auth

    if not _initialized:
        firebase_admin.initialize_app(
            options={"projectId": get_settings().firebase_project_id}
        )
        _initialized = True
    return fb_auth.verify_id_token(token)


async def get_owner(authorization: str | None = Header(None)) -> str:
    """FastAPI dependency: the verified Firebase uid of the caller."""
    if not get_settings().firebase_project_id:
        raise HTTPException(status_code=503, detail="auth not configured")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        decoded = _verify(token)
    except Exception as exc:  # firebase raises several exc types; all mean 401
        log.info("token verification failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(status_code=401, detail="invalid or expired token")
    return str(decoded["uid"])


OwnerDep = Annotated[str, Depends(get_owner)]
```

Add to `backend/app/config.py` inside `Settings` (near the storage block):

```python
    # auth — Firebase project id; token verification needs no secret.
    firebase_project_id: str = ""
```

Add `"firebase-admin>=6.5",` to `dependencies` in `backend/pyproject.toml`, then `cd backend && .venv/bin/pip install -e .`.

- [ ] **Step 4: Run** — `cd backend && .venv/bin/pytest tests/test_auth.py -v` — Expected: 4 PASS.

- [ ] **Step 5: Commit** — `feat: verified Firebase identity dependency (get_owner)`

---

### Task 3: Swap every `x_owner_id` header for `OwnerDep`

**Files:**
- Modify: `backend/app/api/cards.py`, `catalog.py`, `collections.py`, `concepts.py`, `connections.py`, `feed.py`, `graph.py`, `library_chat.py`, `search.py` (≈56 sites)
- Create: `backend/tests/test_auth_routes.py`

**Interfaces:**
- Consumes: `OwnerDep` from Task 2.
- Produces: every data route requires auth; tests override `get_owner` via `app.dependency_overrides` (this is also the pattern all later route tests use).

- [ ] **Step 1: Write failing tests**

```python
"""Routes reject anonymous callers and scope rows to the verified uid."""

import pytest

from app.auth import get_owner
from app.main import app


@pytest.mark.asyncio
async def test_cards_requires_auth(client) -> None:
    resp = await client.get("/cards")
    # 401 (bad token) or 503 (auth unconfigured in test env) — never 200.
    assert resp.status_code in (401, 503)


@pytest.mark.asyncio
async def test_owner_scoping(client) -> None:
    app.dependency_overrides[get_owner] = lambda: "uid-a"
    try:
        created = await client.post("/cards", json={"url": "https://example.com/a"})
        assert created.status_code in (200, 201)
        mine = await client.get("/cards")
        assert mine.status_code == 200

        app.dependency_overrides[get_owner] = lambda: "uid-b"
        theirs = await client.get("/cards")
        assert theirs.status_code == 200
        assert theirs.json() == []  # uid-b sees nothing of uid-a's
    finally:
        app.dependency_overrides.clear()
```

- [ ] **Step 2: Run to verify failure** — `cd backend && .venv/bin/pytest tests/test_auth_routes.py -v` — Expected: `test_cards_requires_auth` FAILS (anonymous GET /cards currently returns 200).

- [ ] **Step 3: Mechanical swap in all 9 API modules**

In each file: add `from app.auth import OwnerDep`; replace every parameter
`x_owner_id: Annotated[str | None, Header()] = None` with `owner_id: OwnerDep`
and every body use of `x_owner_id` with `owner_id`. Delete now-unused `Header` imports. Where routes special-cased `owner_id is None` (e.g. `cards.py:241`), the branch is dead — owner is always set now; remove the conditional and always filter by owner. Grep afterwards: `grep -rn "x_owner_id" backend/app` must return nothing.

The SSE stream route (`/cards/{id}/stream`) gets the same `OwnerDep`.

- [ ] **Step 4: Run full suite** — `cd backend && .venv/bin/pytest -v` — Expected: all PASS.

- [ ] **Step 5: Commit** — `feat: all data routes require verified owner identity`

---

### Task 4: Usage table + quota dependency

**Files:**
- Modify: `backend/app/store/db.py` (UsageRow + helpers; add `degraded` to JobRow; add both columns to the lightweight migration map near line 383)
- Modify: `backend/app/config.py` (quota settings)
- Create: `backend/app/quota.py`
- Create: `backend/tests/test_quota.py`

**Interfaces:**
- Produces:
  - `db.UsageRow` (`owner_id: str, day: str, kind: str, count: int`, PK = first three)
  - `async def db.spend_usage(session, *, owner_id: str, kind: str, limit: int) -> tuple[bool, int]` — atomically increments and returns `(allowed, used_after)`; increments even when over limit is NOT performed (count stays at limit).
  - `quota.spend(kind: str, limit_attr: str)` — dependency factory raising 429 `{"error": "quota", "kind": ..., "used": ..., "limit": ..., "resets_at": ...}`.
  - `quota.card_budget(owner_id, request, session) -> bool` — non-raising check for card creation (True = within quota, False = degrade), which also enforces the per-IP cap (raising 429 only for the IP cap).
  - `JobRow.degraded: bool` column.

- [ ] **Step 1: Write failing tests**

```python
"""Quota accounting: daily counters, limits, per-IP cap, UTC rollover."""

import pytest

from app.store import db


@pytest.mark.asyncio
async def test_spend_usage_counts_and_caps(client) -> None:  # client fixture builds the DB
    async with db.session() as s:
        for i in range(3):
            allowed, used = await db.spend_usage(s, owner_id="u1", kind="chat", limit=3)
            assert allowed and used == i + 1
        allowed, used = await db.spend_usage(s, owner_id="u1", kind="chat", limit=3)
        assert not allowed and used == 3


@pytest.mark.asyncio
async def test_usage_is_per_owner_and_per_kind(client) -> None:
    async with db.session() as s:
        await db.spend_usage(s, owner_id="u1", kind="chat", limit=3)
        allowed, used = await db.spend_usage(s, owner_id="u2", kind="chat", limit=3)
        assert allowed and used == 1
        allowed, used = await db.spend_usage(s, owner_id="u1", kind="cards", limit=3)
        assert allowed and used == 1
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL, `spend_usage` not defined.

- [ ] **Step 3: Implement**

`db.py` additions:

```python
class UsageRow(Base):
    """Daily metered usage. One row per (owner, UTC day, kind); owner_id also
    stores "ip:<addr>" rows for the anonymous-farming IP cap."""

    __tablename__ = "usage"

    owner_id: Mapped[str] = mapped_column(String, primary_key=True)
    day: Mapped[str] = mapped_column(String, primary_key=True)  # "YYYY-MM-DD" UTC
    kind: Mapped[str] = mapped_column(String, primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)


def _today() -> str:
    """Current UTC day key."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


async def spend_usage(
    db_session: AsyncSession, *, owner_id: str, kind: str, limit: int
) -> tuple[bool, int]:
    """Increment today's counter unless at limit. Returns (allowed, used_after)."""
    day = _today()
    row = await db_session.get(UsageRow, (owner_id, day, kind))
    if row is None:
        row = UsageRow(owner_id=owner_id, day=day, kind=kind, count=0)
        db_session.add(row)
    if row.count >= limit:
        return False, row.count
    row.count += 1
    await db_session.commit()
    return True, row.count
```

`JobRow` gains `degraded: Mapped[bool] = mapped_column(Boolean, default=False)`; add `"degraded": "BOOLEAN DEFAULT 0"` to the jobs entry of the additive-migration map (the dict near db.py:383 that backfills missing columns).

`config.py` additions:

```python
    # quotas (per UTC day)
    quota_cards_per_day: int = 10
    quota_chat_per_day: int = 30
    quota_connections_refresh_per_day: int = 3
    quota_ip_cards_per_day: int = 30
```

`backend/app/quota.py`:

```python
"""Per-user daily quotas. Chat-style routes raise 429; card creation degrades
instead (see cards.py) so a save never hard-fails."""

from __future__ import annotations

from datetime import datetime, time, timezone

from fastapi import Depends, HTTPException, Request

from app.auth import get_owner
from app.config import get_settings
from app.store import db


def _resets_at() -> str:
    """ISO timestamp of the next UTC midnight (quota reset)."""
    now = datetime.now(timezone.utc)
    tomorrow = datetime.combine(now.date(), time.min, tzinfo=timezone.utc)
    return tomorrow.replace(day=now.day).isoformat()  # replaced in Step 3b


def spend(kind: str, limit_attr: str):
    """Dependency factory: spend one unit of `kind` or raise 429."""

    async def _dep(owner_id: str = Depends(get_owner)) -> str:
        limit = getattr(get_settings(), limit_attr)
        async with db.session() as s:
            allowed, used = await db.spend_usage(
                s, owner_id=owner_id, kind=kind, limit=limit
            )
        if not allowed:
            raise HTTPException(
                status_code=429,
                detail={
                    "error": "quota", "kind": kind,
                    "used": used, "limit": limit, "resets_at": _resets_at(),
                },
            )
        return owner_id

    return _dep


async def card_budget(owner_id: str, request: Request) -> bool:
    """Card-creation budget. Enforces the per-IP cap (429) and returns whether
    the owner still has AI budget today (False -> degrade, never fail)."""
    settings = get_settings()
    ip = request.client.host if request.client else "unknown"
    async with db.session() as s:
        ip_ok, _ = await db.spend_usage(
            s, owner_id=f"ip:{ip}", kind="cards", limit=settings.quota_ip_cards_per_day
        )
        if not ip_ok:
            raise HTTPException(status_code=429, detail={
                "error": "quota", "kind": "ip", "limit": settings.quota_ip_cards_per_day,
                "used": settings.quota_ip_cards_per_day, "resets_at": _resets_at(),
            })
        allowed, _ = await db.spend_usage(
            s, owner_id=owner_id, kind="cards", limit=settings.quota_cards_per_day
        )
    return allowed
```

- [ ] **Step 3b: Fix `_resets_at`** — the naive `.replace(day=...)` is wrong at month end. Use:

```python
from datetime import timedelta

def _resets_at() -> str:
    now = datetime.now(timezone.utc)
    tomorrow = datetime.combine(now.date() + timedelta(days=1), time.min, tzinfo=timezone.utc)
    return tomorrow.isoformat()
```

- [ ] **Step 4: Run** — `cd backend && .venv/bin/pytest tests/test_quota.py -v` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: usage table + daily quota accounting`

---

### Task 5: Wire quotas into routes; degrade card creation

**Files:**
- Modify: `backend/app/api/cards.py` (create route + chat + rabbithole), `backend/app/api/library_chat.py`, `backend/app/api/connections.py`
- Modify: `backend/app/pipeline/worker.py` + `backend/app/pipeline/structuring.py` (degraded path)
- Create: `backend/app/api/me.py` (`GET /me/quota`), register in `main.py`
- Create: `backend/tests/test_quota_routes.py`

**Interfaces:**
- Consumes: `quota.spend`, `quota.card_budget`, `JobRow.degraded` from Task 4.
- Produces: `structure(bundle, transcript, caption, force_fallback: bool = False)` — when True returns `_paragraph_fallback(...)` immediately, with `degraded=True, degraded_reason="quota"`. `GET /me/quota` → `{"cards": {"used": n, "limit": n}, "chat": {...}, "resets_at": iso}`.

- [ ] **Step 1: Write failing tests**

```python
"""Quota wiring: chat 429s past limit; card creation degrades; /me/quota reports."""

import pytest

from app.auth import get_owner
from app.main import app
from app.store import db


@pytest.fixture(autouse=True)
def _small_limits(monkeypatch):
    monkeypatch.setenv("QUOTA_CARDS_PER_DAY", "1")
    monkeypatch.setenv("QUOTA_CHAT_PER_DAY", "1")
    from app import config
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def as_user():
    app.dependency_overrides[get_owner] = lambda: "uid-q"
    yield
    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_card_creation_degrades_past_quota(client, as_user) -> None:
    r1 = await client.post("/cards", json={"url": "https://example.com/1"})
    assert r1.status_code in (200, 201)
    r2 = await client.post("/cards", json={"url": "https://example.com/2"})
    assert r2.status_code in (200, 201)  # degrade, never fail
    async with db.session() as s:
        jobs = (await s.execute(db.select(db.JobRow).order_by(db.JobRow.created_at))).scalars().all()
    assert [j.degraded for j in jobs] == [False, True]


@pytest.mark.asyncio
async def test_me_quota(client, as_user) -> None:
    resp = await client.get("/me/quota")
    assert resp.status_code == 200
    body = resp.json()
    assert body["cards"]["limit"] == 1 and "resets_at" in body
```

(If `db.select` isn't re-exported, import `select` from sqlalchemy in the test.)

- [ ] **Step 2: Run to verify failure** — Expected: FAIL (`degraded` never True; /me/quota 404).

- [ ] **Step 3: Implement**

`cards.py` create route: add `request: Request` param; after resolving the cache-miss path and before creating the JobRow, call `within = await quota.card_budget(owner_id, request)`; create the job with `degraded=not within`; include `"quota_degraded": not within` in the response body.

Chat routes: append `dependencies=[Depends(quota.spend("chat", "quota_chat_per_day"))]` to the route decorators of card chat, rabbithole (in `cards.py`) and library chat (`library_chat.py`). Connections refresh: inside the handler, only when `refresh=True`, call the spend dependency logic directly:

```python
if refresh:
    await quota.spend("connections_refresh", "quota_connections_refresh_per_day")(owner_id)
```

`structuring.py`: change signature to `def structure(bundle: str, transcript: str = "", caption: str = "", force_fallback: bool = False) -> "StructuredCard":` and as the first statement:

```python
    if force_fallback:
        log.info("structuring: quota-degraded card -> paragraph fallback")
        return _paragraph_fallback(bundle, transcript, caption, reason="quota")
```

Match `_paragraph_fallback`'s real signature (read it first; pass whatever it actually takes, setting `degraded_reason="quota"` however the non-forced fallback path does).

`worker.py` `_run_job`: where `structure(...)` is called, pass `force_fallback=job.degraded`.

`me.py`:

```python
"""The caller's own quota status — powers the profile meter."""

from __future__ import annotations

from fastapi import APIRouter

from app.auth import OwnerDep
from app.config import get_settings
from app.quota import _resets_at
from app.store import db

router = APIRouter(prefix="/me", tags=["me"])


@router.get("/quota")
async def my_quota(owner_id: OwnerDep) -> dict:
    """Today's used/limit per metered kind."""
    settings = get_settings()
    day = db._today()
    out: dict = {"resets_at": _resets_at()}
    async with db.session() as s:
        for kind, limit in (
            ("cards", settings.quota_cards_per_day),
            ("chat", settings.quota_chat_per_day),
        ):
            row = await s.get(db.UsageRow, (owner_id, day, kind))
            out[kind] = {"used": row.count if row else 0, "limit": limit}
    return out
```

Register in `main.py`: `from app.api import me` + `app.include_router(me.router)`.

- [ ] **Step 4: Run full suite** — `cd backend && .venv/bin/pytest -v` — Expected: all PASS.

- [ ] **Step 5: Commit** — `feat: quotas wired — chat 429s, cards degrade, /me/quota`

---

### Task 6: `/auth/claim` — legacy name migration

**Files:**
- Modify: `backend/app/store/db.py` (ClaimRow + `claim_owner` helper)
- Create: `backend/app/api/auth_routes.py`, register in `main.py`
- Create: `backend/tests/test_claim.py`

**Interfaces:**
- Produces: `POST /auth/claim {"name": str}` → 200 `{"claimed": <row count>}` or 409 if the name was already claimed. `db.claim_owner(session, *, name: str, uid: str) -> int | None` (None = already claimed by someone else).

- [ ] **Step 1: Write failing tests**

```python
"""First-claim-wins migration of legacy name-keyed rows."""

import pytest

from app.auth import get_owner
from app.main import app
from app.store import db


async def _seed_legacy_card(name: str) -> None:
    async with db.session() as s:
        s.add(db.CardRow(owner_id=name, url=f"https://example.com/{name}", state="ready"))
        await s.commit()


@pytest.mark.asyncio
async def test_claim_repoints_rows(client) -> None:
    await _seed_legacy_card("Vatsal")
    app.dependency_overrides[get_owner] = lambda: "uid-new"
    try:
        resp = await client.post("/auth/claim", json={"name": "Vatsal"})
        assert resp.status_code == 200 and resp.json()["claimed"] >= 1
        again = await client.post("/auth/claim", json={"name": "Vatsal"})
        assert again.status_code == 200  # same uid re-claiming is a no-op success
        app.dependency_overrides[get_owner] = lambda: "uid-thief"
        stolen = await client.post("/auth/claim", json={"name": "Vatsal"})
        assert stolen.status_code == 409
    finally:
        app.dependency_overrides.clear()
```

Adjust `_seed_legacy_card` to CardRow's actual required columns (read the model; fill mandatory fields minimally).

- [ ] **Step 2: Run to verify failure** — Expected: 404 on /auth/claim.

- [ ] **Step 3: Implement**

`db.py`:

```python
class ClaimRow(Base):
    """Legacy display-name -> uid claims; first claim wins."""

    __tablename__ = "claims"

    name: Mapped[str] = mapped_column(String, primary_key=True)
    uid: Mapped[str] = mapped_column(String, nullable=False)


async def claim_owner(db_session: AsyncSession, *, name: str, uid: str) -> int | None:
    """Re-point every legacy row owned by `name` to `uid`. None = taken."""
    existing = await db_session.get(ClaimRow, name)
    if existing is not None:
        return 0 if existing.uid == uid else None
    db_session.add(ClaimRow(name=name, uid=uid))
    total = 0
    for model in (CardRow, CollectionRow, ConversationRow, ConnectionRow):
        res = await db_session.execute(
            update(model).where(model.owner_id == name).values(owner_id=uid)
        )
        total += res.rowcount or 0
    await db_session.commit()
    return total
```

`auth_routes.py`:

```python
"""Temporary migration endpoint (delete ~1 month after auth ships)."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.auth import OwnerDep
from app.store import db

router = APIRouter(prefix="/auth", tags=["auth"])


class ClaimRequest(BaseModel):
    name: str


@router.post("/claim")
async def claim(req: ClaimRequest, owner_id: OwnerDep) -> dict:
    """Adopt legacy rows keyed by the pre-auth display name. First claim wins."""
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="name required")
    async with db.session() as s:
        claimed = await db.claim_owner(s, name=name, uid=owner_id)
    if claimed is None:
        raise HTTPException(status_code=409, detail="name already claimed")
    return {"claimed": claimed}
```

- [ ] **Step 4: Run** — `cd backend && .venv/bin/pytest tests/test_claim.py -v` — Expected: PASS.

- [ ] **Step 5: Commit** — `feat: /auth/claim legacy library migration (first-claim-wins)`

---

### Task 7: Hardening — admin token, clean 500s, CORS

**Files:**
- Modify: `backend/app/main.py`, `backend/app/config.py`
- Create: `backend/tests/test_hardening.py`

**Interfaces:**
- Consumes: nothing new. Produces: `Settings.admin_token: str = ""`, `Settings.cors_origins: str = ""` (comma-separated).

- [ ] **Step 1: Write failing tests**

```python
"""Admin/debug gated; 500s never leak tracebacks."""

import pytest


@pytest.mark.asyncio
async def test_admin_requires_token(client, monkeypatch) -> None:
    monkeypatch.setenv("ADMIN_TOKEN", "s3cret")
    from app import config
    config.get_settings.cache_clear()
    assert (await client.get("/admin/stats")).status_code == 401
    assert (await client.get("/debug/jobs")).status_code == 401
    ok = await client.get("/admin/stats", headers={"x-admin-token": "s3cret"})
    assert ok.status_code == 200


@pytest.mark.asyncio
async def test_admin_disabled_when_unset(client, monkeypatch) -> None:
    monkeypatch.delenv("ADMIN_TOKEN", raising=False)
    from app import config
    config.get_settings.cache_clear()
    assert (await client.get("/debug/jobs")).status_code == 401
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL (currently 200 without token).

- [ ] **Step 3: Implement**

`config.py`: add `admin_token: str = ""` and `cors_origins: str = ""`.

`main.py`:

```python
from fastapi import Depends, Header, HTTPException

async def require_admin(x_admin_token: str | None = Header(None)) -> None:
    """Gate for owner-only endpoints; unset ADMIN_TOKEN disables them entirely."""
    expected = get_settings().admin_token
    if not expected or x_admin_token != expected:
        raise HTTPException(status_code=401, detail="admin token required")
```

Add `dependencies=[Depends(require_admin)]` to the `/admin/stats`, `/debug/jobs`, `/debug/kill_stuck` decorators. Replace the 500 handler body: keep the full-traceback `log.error`, return only `{"detail": "internal error"}` (no exception text, no traceback). CORS: `allow_origins=[o.strip() for o in get_settings().cors_origins.split(",") if o.strip()] or ["http://localhost:8000"]` — set the real Space origin via env in deployment. Import `get_settings` from `app.config` at top of main.py.

- [ ] **Step 4: Run full suite** — `cd backend && .venv/bin/pytest -v` — Expected: all PASS. Also verify: `grep -rn "traceback" backend/app/main.py` shows logging only, not response content.

- [ ] **Step 5: Commit** — `feat: admin token gate, clean 500s, restricted CORS`
