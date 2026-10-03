"""Credential primitives for Cachy ID auth (username + password, no email).

Passwords AND recovery codes are hashed with argon2id. Nothing secret is ever
logged or returned — except the recovery code at the single moment of
account creation, when the user is told to save it.
"""

from __future__ import annotations

import re
import secrets

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

_ph = PasswordHasher()  # argon2id with OWASP-ish defaults

_USERNAME_RE = re.compile(r"^[a-z0-9_]{3,20}$")
_RESERVED = frozenset({
    "admin", "administrator", "root", "system", "support", "help",
    "cachy", "cachyapp", "official", "null", "undefined", "api",
    "webmaster", "security", "abuse", "postmaster", "info", "test",
})
MIN_PASSWORD_LEN = 8
# Unambiguous alphabet (no 0/O, 1/l/I) for human-transcribed recovery codes.
_CODE_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"


def normalize_username(raw: str) -> str:
    return raw.strip().lower()


def username_error(username: str) -> str | None:
    """None when the username is acceptable, else a human-readable reason."""
    if not _USERNAME_RE.match(username):
        return "use 3-20 characters: lowercase letters, numbers, underscore"
    if username in _RESERVED:
        return "that name is reserved"
    return None


def password_error(password: str) -> str | None:
    if len(password) < MIN_PASSWORD_LEN:
        return f"password must be at least {MIN_PASSWORD_LEN} characters"
    return None


def hash_secret(secret: str) -> str:
    return _ph.hash(secret)


def verify_secret(hash_: str, secret: str) -> bool:
    try:
        return _ph.verify(hash_, secret)
    except VerifyMismatchError:
        return False
    except Exception:
        # Malformed stored hash — treat as mismatch, never crash auth.
        return False


def new_recovery_code() -> str:
    """A human-transcribable recovery code, e.g. 'kx7q-m2za-9wbd'."""
    parts = [
        "".join(secrets.choice(_CODE_ALPHABET) for _ in range(4))
        for _ in range(3)
    ]
    return "-".join(parts)
