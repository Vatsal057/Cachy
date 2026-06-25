"""In-process pub/sub for the transparent-capture SSE stream (docs/01, docs/05).

The worker publishes a stage event per card_id; the SSE endpoint subscribes and
relays them to the client. Single-process only — fine for one HF Space; swap for
Redis pub/sub if the worker ever moves out of process."""

from __future__ import annotations

import asyncio
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class StageEvent:
    card_id: str
    stage: str          # downloading | extracting | structuring | persisting | done | failed
    state: str          # card state: queued | processing | ready | failed
    detail: str = ""
    reason: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "card_id": self.card_id,
            "stage": self.stage,
            "state": self.state,
            "detail": self.detail,
            "reason": self.reason,
        }


@dataclass
class _Bus:
    subscribers: dict[str, set[asyncio.Queue]] = field(
        default_factory=lambda: defaultdict(set)
    )

    def subscribe(self, card_id: str) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self.subscribers[card_id].add(q)
        return q

    def unsubscribe(self, card_id: str, q: asyncio.Queue) -> None:
        subs = self.subscribers.get(card_id)
        if subs:
            subs.discard(q)
            if not subs:
                self.subscribers.pop(card_id, None)

    def publish(self, event: StageEvent) -> None:
        for q in list(self.subscribers.get(event.card_id, ())):
            q.put_nowait(event)


_bus = _Bus()


def subscribe(card_id: str) -> asyncio.Queue:
    return _bus.subscribe(card_id)


def unsubscribe(card_id: str, q: asyncio.Queue) -> None:
    _bus.unsubscribe(card_id, q)


def publish(
    card_id: str, stage: str, state: str, detail: str = "", reason: str | None = None
) -> None:
    _bus.publish(StageEvent(card_id, stage, state, detail, reason))
