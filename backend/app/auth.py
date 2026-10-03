"""Verified identity: Firebase ID token -> uid, or Cachy ID JWT -> uid.

The client sends `Authorization: Bearer <token>`; Firebase tokens are verified
against Google's public certs via `google-auth` (no service-account secret
needed — only the project id as audience). Cachy ID tokens (username +
password, see app/api/id_auth.py) are HS256 JWTs verified with CACHY_ID_SECRET.
Routing is by the token's `iss` claim; either way the uid returned IS the
backend owner_id.
firebase-admin is deliberately not used here: its client construction eagerly
loads Application Default Credentials, which we don't have in a free deploy.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Query
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.config import get_settings
from app.id_tokens import (
    is_cachy_id_token,
    verify_id_token as _verify_cachy_id_token,
)

log = logging.getLogger("app.auth")

# Shared HTTP transport; caches Google's public signing certs across requests.
_request = google_requests.Request()


def _verify(token: str) -> dict:
    """Verify a Firebase ID token against Google's public certs.

    Checks signature, expiry, and that `aud` == the Firebase project id. Blocking
    (cert fetch + crypto). Callers in async paths must run this via [verify_async]
    / to_thread so it never stalls the event loop (M3). Raises ValueError on any
    invalid/expired/wrong-audience token."""
    return google_id_token.verify_firebase_token(
        token, _request, audience=get_settings().firebase_project_id
    )


def uid_of(decoded: dict) -> str | None:
    """The Firebase uid from verified claims. google-auth exposes it as
    `sub`/`user_id`; firebase-admin (and test mocks) as `uid`."""
    uid = decoded.get("uid") or decoded.get("user_id") or decoded.get("sub")
    return str(uid) if uid else None


async def verify_async(token: str) -> dict:
    """Async wrapper: run the blocking Firebase verification off the event loop."""
    return await asyncio.to_thread(_verify, token)


class AuthNotConfigured(Exception):
    """The presented token type's auth backend has no credentials configured."""


async def verify_any_async(token: str) -> str:
    """uid from either a Firebase ID token or a Cachy ID token.

    Routing is by the unverified `iss` claim (cheap, local); the signature is
    always verified afterwards by the selected verifier. Raises
    AuthNotConfigured when that token type's backend isn't set up, ValueError
    on any invalid token."""
    settings = get_settings()
    if is_cachy_id_token(token):
        if not settings.cachy_id_enabled:
            raise AuthNotConfigured("cachy id auth not configured")
        claims = _verify_cachy_id_token(token, secret=settings.cachy_id_secret)
        return str(claims["sub"])
    if not settings.firebase_project_id:
        raise AuthNotConfigured("auth not configured")
    decoded = await verify_async(token)
    uid = uid_of(decoded)
    if not uid:
        raise ValueError("token missing subject")
    return uid


async def get_owner(authorization: str | None = Header(None)) -> str:
    """FastAPI dependency: the verified uid of the caller.

    Accepts Firebase ID tokens (Google/anonymous) AND Cachy ID tokens
    (username + password, see app/api/id_auth.py). Routing is by the token's
    `iss` claim; the uid returned IS the backend owner_id either way."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        return await verify_any_async(token)
    except AuthNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:
        log.info("token verification failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(status_code=401, detail="invalid or expired token")


OwnerDep = Annotated[str, Depends(get_owner)]


async def get_optional_owner(authorization: str | None = Header(None)) -> str | None:
    """Optional verified uid of caller if Bearer token is provided and valid, else None."""
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token = authorization.removeprefix("Bearer ").strip()
    try:
        return await verify_any_async(token)
    except Exception as exc:
        log.debug("optional token verification failed: %s: %s", type(exc).__name__, exc)
        return None


OptionalOwnerDep = Annotated[str | None, Depends(get_optional_owner)]


async def get_owner_query_or_header(
    authorization: str | None = Header(None),
    token: str | None = Query(None),
) -> str:
    """Like [get_owner] but also accepts the token as a `?token=` query param.

    Browser `<img>` tags can't send an Authorization header, so web thumbnails
    fetch the auth-gated /media proxy with the token in the query string."""
    raw: str | None = None
    if authorization and authorization.startswith("Bearer "):
        raw = authorization.removeprefix("Bearer ").strip()
    elif token:
        raw = token.strip()
    if not raw:
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        return await verify_any_async(raw)
    except AuthNotConfigured as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:
        log.info("token verification failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(status_code=401, detail="invalid or expired token")


MediaOwnerDep = Annotated[str, Depends(get_owner_query_or_header)]
