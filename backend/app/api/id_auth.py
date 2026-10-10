"""Cachy ID auth: username + password accounts, no email (FOR NOW).

Issues HS256 JWTs (see app/id_tokens.py); app/auth.py accepts them alongside
Firebase ID tokens, and the uid they carry IS the backend owner_id — so
cards, jobs, quota and conversations need no changes.

Security notes:
- Passwords and recovery codes are argon2id-hashed (app/passwords.py).
- /register and /login are per-IP rate-limited (in-memory sliding window;
  single-process deploys only — fine for the HF Space).
- Failed logins are counted per account; 5 failures lock it for 15 minutes.
- Login failures return a generic 401 so usernames can't be enumerated by
  timing or message (a dummy argon2 verify keeps nonexistent-user attempts
  cost-similar).
- No email => no email reset. Registration returns a recovery code shown
  ONCE; the user must save it. /reset verifies it (argon2) to set a new
  password.
"""

from __future__ import annotations

import logging
import uuid
from collections import deque
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app import passwords
from app.auth import OwnerDep
from app.config import get_settings
from app.id_tokens import mint_id_token
from app.rate_limit import RateLimiter
from app.store import db

log = logging.getLogger("app.id_auth")
router = APIRouter(prefix="/id", tags=["id-auth"])

_MAX_FAILS = 5
_LOCK_MINUTES = 15
_id_limiter = RateLimiter(limit=20, window_seconds=60.0)
# Fixed hash so login attempts for nonexistent usernames cost ~the same as
# real verifications (timing-based username enumeration resistance).
_DUMMY_HASH = passwords.hash_secret("cachy-id-dummy-" + uuid.uuid4().hex)


def _require_enabled() -> None:
    if not get_settings().cachy_id_enabled:
        raise HTTPException(status_code=503, detail="cachy id auth not configured")


def _check_ip_rate(request: Request) -> None:
    _id_limiter.check(request)


def _mint(uid: str, username: str) -> str:
    s = get_settings()
    return mint_id_token(
        uid=uid, username=username, secret=s.cachy_id_secret, days=s.cachy_id_token_days
    )


def _locked_minutes(row: db.IdAccountRow) -> int | None:
    """Minutes remaining on the lockout, or None when not locked. Handles both
    naive (SQLite) and aware (Postgres) datetimes."""
    if not row.locked_until:
        return None
    lu = row.locked_until
    if lu.tzinfo is None:
        lu = lu.replace(tzinfo=timezone.utc)
    remaining = (lu - datetime.now(timezone.utc)).total_seconds() / 60
    return max(1, int(remaining)) if remaining > 0 else None


async def _apply_lockout(s, row: db.IdAccountRow) -> None:
    """Lock the account once failures reach the threshold."""
    await db.note_id_login_failure(s, row=row)
    if (row.failed_attempts or 0) >= _MAX_FAILS and not _locked_minutes(row):
        row.locked_until = datetime.now(timezone.utc) + timedelta(minutes=_LOCK_MINUTES)
        await s.commit()
        log.warning("cachy id locked: %s", row.username)


class RegisterRequest(BaseModel):
    username: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class LinkRequest(BaseModel):
    username: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class ResetRequest(BaseModel):
    username: str = Field(min_length=1, max_length=32)
    recovery_code: str = Field(min_length=1, max_length=64)
    new_password: str = Field(min_length=1, max_length=128)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=1, max_length=128)


@router.get("/available")
async def username_available(request: Request, username: str = "") -> dict:
    """Live availability check for the signup form."""
    _require_enabled()
    _check_ip_rate(request)
    uname = passwords.normalize_username(username)
    if (err := passwords.username_error(uname)) is not None:
        return {"available": False, "reason": err}
    async with db.session() as s:
        taken = await db.get_id_account_by_username(s, username=uname) is not None
    return {"available": not taken}


@router.post("/register", status_code=201)
async def register(req: RegisterRequest, request: Request) -> dict:
    _require_enabled()
    _check_ip_rate(request)
    uname = passwords.normalize_username(req.username)
    if (err := passwords.username_error(uname)) is not None:
        raise HTTPException(status_code=422, detail=err)
    if (err := passwords.password_error(req.password)) is not None:
        raise HTTPException(status_code=422, detail=err)
    async with db.session() as s:
        if await db.get_id_account_by_username(s, username=uname) is not None:
            raise HTTPException(status_code=409, detail="that ID is taken")
        uid = "id_" + uuid.uuid4().hex
        recovery_code = passwords.new_recovery_code()
        await db.create_id_account(
            s,
            uid=uid,
            username=uname,
            password_hash=passwords.hash_secret(req.password),
            recovery_hash=passwords.hash_secret(recovery_code),
        )
    log.info("cachy id registered: %s", uname)
    # The recovery code is returned exactly once — the client must display it
    # with a save-it-or-lose-it warning. It is never returned again.
    return {
        "uid": uid,
        "username": uname,
        "token": _mint(uid, uname),
        "recovery_code": recovery_code,
    }


@router.post("/login")
async def login(req: LoginRequest, request: Request) -> dict:
    _require_enabled()
    _check_ip_rate(request)
    uname = passwords.normalize_username(req.username)
    async with db.session() as s:
        row = await db.get_id_account_by_username(s, username=uname)
        if row is None:
            passwords.verify_secret(_DUMMY_HASH, req.password)
            raise HTTPException(status_code=401, detail="wrong ID or password")
        if (mins := _locked_minutes(row)) is not None:
            raise HTTPException(
                status_code=423,
                detail=f"too many attempts — try again in ~{mins} min",
            )
        if not passwords.verify_secret(row.password_hash, req.password):
            await _apply_lockout(s, row)
            raise HTTPException(status_code=401, detail="wrong ID or password")
        await db.clear_id_login_failures(s, row=row)
        uid, username = row.uid, row.username
    return {"uid": uid, "username": username, "token": _mint(uid, username)}


@router.post("/demo")
async def demo_login() -> dict:
    """1-click authentication for hackathon judges into the curated pre-verified shelf."""
    _require_enabled()
    uid = "judge_hackathon_2026"
    username = "judge"
    return {"uid": uid, "username": username, "token": _mint(uid, username)}


@router.post("/link")
async def link_id_to_firebase(req: LinkRequest, request: Request, owner_id: OwnerDep) -> dict:
    """Claim a Cachy ID onto the caller's Firebase account (Google/anonymous).

    Afterwards the same library is reachable via Google sign-in OR the ID's
    username + password — both resolve to the Firebase uid as owner_id.
    """
    _require_enabled()
    _check_ip_rate(request)
    uname = passwords.normalize_username(req.username)
    if (err := passwords.username_error(uname)) is not None:
        raise HTTPException(status_code=422, detail=err)
    if (err := passwords.password_error(req.password)) is not None:
        raise HTTPException(status_code=422, detail=err)
    async with db.session() as s:
        if await db.get_id_account_by_uid(s, uid=owner_id) is not None:
            raise HTTPException(
                status_code=409, detail="this account already signs in with a Cachy ID"
            )
        if await db.get_id_account_by_firebase_uid(s, firebase_uid=owner_id) is not None:
            raise HTTPException(status_code=409, detail="this account already has a Cachy ID")
        if await db.get_id_account_by_username(s, username=uname) is not None:
            raise HTTPException(status_code=409, detail="that ID is taken")
        recovery_code = passwords.new_recovery_code()
        await db.create_id_account(
            s,
            uid=owner_id,
            username=uname,
            password_hash=passwords.hash_secret(req.password),
            recovery_hash=passwords.hash_secret(recovery_code),
            firebase_uid=owner_id,
        )
    log.info("cachy id linked: %s -> %s", uname, owner_id)
    return {
        "uid": owner_id,
        "username": uname,
        "token": _mint(owner_id, uname),
        "recovery_code": recovery_code,
    }


@router.post("/reset")
async def reset_password(req: ResetRequest, request: Request) -> dict:
    """Set a new password using the recovery code (no email)."""
    _require_enabled()
    _check_ip_rate(request)
    uname = passwords.normalize_username(req.username)
    if (err := passwords.password_error(req.new_password)) is not None:
        raise HTTPException(status_code=422, detail=err)
    async with db.session() as s:
        row = await db.get_id_account_by_username(s, username=uname)
        if row is None or not passwords.verify_secret(
            row.recovery_hash, req.recovery_code.strip()
        ):
            # Generic: don't reveal whether the username exists.
            raise HTTPException(status_code=401, detail="wrong ID or recovery code")
        await db.set_id_password(s, row=row, password_hash=passwords.hash_secret(req.new_password))
        uid, username = row.uid, row.username
    log.info("cachy id password reset: %s", uname)
    return {"uid": uid, "username": username, "token": _mint(uid, username)}


@router.post("/change-password")
async def change_password(req: ChangePasswordRequest, owner_id: OwnerDep) -> dict:
    async with db.session() as s:
        row = await db.get_id_account_by_uid(s, uid=owner_id)
        if row is None:
            raise HTTPException(status_code=404, detail="no Cachy ID on this account")
        if not passwords.verify_secret(row.password_hash, req.current_password):
            raise HTTPException(status_code=401, detail="current password is wrong")
        if (err := passwords.password_error(req.new_password)) is not None:
            raise HTTPException(status_code=422, detail=err)
        await db.set_id_password(s, row=row, password_hash=passwords.hash_secret(req.new_password))
    return {"ok": True}


@router.get("/me")
async def id_me(owner_id: OwnerDep) -> dict:
    """The caller's uid and Cachy ID username (null when the account — e.g. a
    plain Firebase login — has none)."""
    async with db.session() as s:
        row = await db.get_id_account_by_uid(s, uid=owner_id)
    return {"uid": owner_id, "username": row.username if row else None}
