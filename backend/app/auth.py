"""Verified identity: Firebase ID token -> uid.

The client sends `Authorization: Bearer <ID token>`; we verify the signature
against Google's public certs via `google-auth`. No service-account secret is
needed for verification — only the project id (the token's expected audience).
firebase-admin is deliberately not used here: its client construction eagerly
loads Application Default Credentials, which we don't have in a free deploy.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Annotated

from fastapi import Depends, Header, HTTPException
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.config import get_settings

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


async def get_owner(authorization: str | None = Header(None)) -> str:
    """FastAPI dependency: the verified Firebase uid of the caller."""
    if not get_settings().firebase_project_id:
        raise HTTPException(status_code=503, detail="auth not configured")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    try:
        decoded = await verify_async(token)
    except Exception as exc:  # firebase raises several exc types; all mean 401
        log.info("token verification failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(status_code=401, detail="invalid or expired token")
    uid = uid_of(decoded)
    if not uid:
        raise HTTPException(status_code=401, detail="token missing subject")
    return uid


OwnerDep = Annotated[str, Depends(get_owner)]
