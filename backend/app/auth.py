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
