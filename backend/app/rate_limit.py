"""In-memory per-IP sliding-window rate limiter.

Single-process only (state lives in this process) — fine for the HF Space
deploy. Each limiter instance has its own bucket table so different features
(/id/*, /share/*) don't share a budget.
"""

from __future__ import annotations

import time
from collections import deque

from fastapi import HTTPException, Request


class RateLimiter:
    def __init__(self, limit: int, window_seconds: float = 60.0):
        self._limit = limit
        self._window = window_seconds
        self._hits: dict[str, deque[float]] = {}

    def check(self, request: Request) -> None:
        """Raise 429 when this IP exceeded the budget."""
        ip = request.client.host if request.client else "unknown"
        now = time.monotonic()
        hits = self._hits.get(ip)
        if hits is None:
            hits = self._hits[ip] = deque()
        while hits and hits[0] <= now - self._window:
            hits.popleft()
        if len(hits) >= self._limit:
            raise HTTPException(
                status_code=429, detail="too many attempts, slow down"
            )
        hits.append(now)
        # Bound the table: sweep idle IPs once it gets large.
        if len(self._hits) > 5000:
            cutoff = now - self._window
            for key in [
                k for k, dq in self._hits.items() if not dq or dq[-1] <= cutoff
            ]:
                del self._hits[key]
