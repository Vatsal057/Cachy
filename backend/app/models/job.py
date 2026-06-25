"""Job + state machine (docs/01, docs/08). With a DB-backed queue, the jobs table
*is* the queue; this enum is its lifecycle."""

from __future__ import annotations

from enum import Enum


class JobState(str, Enum):
    QUEUED = "queued"
    PROCESSING = "processing"
    DONE = "done"
    FAILED = "failed"  # failed this attempt; eligible for retry
    DEAD = "dead"      # exhausted retries (dead-letter)
