"""Signed session tokens for Cachy ID logins.

HS256 JWTs minted with the server secret (CACHY_ID_SECRET). The `iss` claim
lets app/auth.py route a token to the right verifier without a network round
trip: Firebase tokens carry a Google `iss`, ours carries "cachy-id".
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt

ISSUER = "cachy-id"
_ALG = "HS256"


def mint_id_token(*, uid: str, username: str, secret: str, days: int) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "iss": ISSUER,
        "sub": uid,
        "username": username,
        "iat": now,
        "exp": now + timedelta(days=days),
    }
    return jwt.encode(payload, secret, algorithm=_ALG)


def verify_id_token(token: str, *, secret: str) -> dict:
    """Returns the claims, or raises ValueError on any problem (bad signature,
    wrong issuer, expired, ...)."""
    try:
        claims = jwt.decode(
            token,
            secret,
            algorithms=[_ALG],
            issuer=ISSUER,
            options={"require": ["iss", "sub", "exp"]},
        )
    except jwt.PyJWTError as exc:
        raise ValueError(f"bad id token: {exc}") from exc
    return claims


def is_cachy_id_token(token: str) -> bool:
    """Unverified `iss` peek, used ONLY to route to the right verifier — the
    signature is always verified afterwards by verify_id_token."""
    try:
        claims = jwt.decode(token, options={"verify_signature": False})
    except jwt.PyJWTError:
        return False
    return isinstance(claims, dict) and claims.get("iss") == ISSUER
