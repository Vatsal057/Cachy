"""The worker used to check the queue once a second forever.

On a managed Postgres that meters compute and suspends after five minutes idle,
that means it never suspends. These tests pin the two properties that fix
depends on: an empty queue has to stop generating traffic, and a real job still
has to start immediately.
"""

from __future__ import annotations

import asyncio
import time

import pytest

from app.config import get_settings
from app.pipeline import worker


@pytest.fixture(autouse=True)
def _reset_worker():
    worker.reset_stop()
    worker._wake.clear()
    yield
    worker.stop_worker()


async def _run_loop_for(seconds: float, monkeypatch, claim_impl) -> list[float]:
    """Run the real loop with the queue claim stubbed, and record when it asked."""
    asked: list[float] = []
    t0 = time.monotonic()

    async def fake_claim(session):
        asked.append(time.monotonic() - t0)
        return await claim_impl(session)

    class _NullSession:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

        async def rollback(self):
            return None

    monkeypatch.setattr(worker, "_claim_next_job", fake_claim)
    monkeypatch.setattr(worker.db, "session", lambda: _NullSession())

    task = asyncio.create_task(worker.run_worker_loop())
    await asyncio.sleep(seconds)
    worker.stop_worker()
    await asyncio.wait_for(task, timeout=5)
    return asked


@pytest.mark.asyncio
async def test_idle_queue_backs_off_instead_of_polling_every_second(monkeypatch):
    """Ten seconds of an empty queue must not cost ten queries."""
    settings = get_settings()
    monkeypatch.setattr(settings, "worker_poll_seconds", 0.05, raising=False)
    monkeypatch.setattr(settings, "worker_idle_max_seconds", 1.0, raising=False)

    async def always_empty(session):
        return None

    asked = await _run_loop_for(3.0, monkeypatch, always_empty)

    # Flat polling at 0.05s would be ~60 checks in 3s. Doubling to a 1s ceiling
    # is ~9. Allow slack for scheduling but keep the difference meaningful.
    assert len(asked) < 15, f"still polling hot: {len(asked)} checks in 3s"

    # And the gaps must actually be growing.
    gaps = [round(b - a, 3) for a, b in zip(asked, asked[1:])]
    assert gaps[-1] > gaps[0], f"interval never grew: {gaps}"


@pytest.mark.asyncio
async def test_idle_ceiling_actually_leaves_the_database_asleep():
    """Clearing the 5-minute suspend window is not enough on its own.

    Every query restarts the idle timer, so at poll interval P the compute is
    awake min(P, S)/P of the time. A 6-minute poll clears the window and still
    leaves it awake 83% of the month, which burns the allowance in ~20 days
    instead of ~17. The interval has to be big enough that the awake fraction
    fits the budget.
    """
    suspend_window_s = 5 * 60
    hours_in_month = 730
    # 100 CU-hours at the 0.25 CU floor.
    budget_hours = 400

    p = get_settings().worker_idle_max_seconds
    assert p > suspend_window_s, "poll never lets the compute suspend at all"

    awake_fraction = min(p, suspend_window_s) / p
    awake_hours = hours_in_month * awake_fraction
    assert awake_hours <= budget_hours, (
        f"idle poll of {p}s leaves the compute awake {awake_fraction:.0%} of the "
        f"month ({awake_hours:.0f}h) against a {budget_hours}h allowance"
    )


@pytest.mark.asyncio
async def test_notify_wakes_the_worker_without_waiting_out_the_backoff(monkeypatch):
    """Backing off is only acceptable if enqueueing still starts work at once."""
    settings = get_settings()
    monkeypatch.setattr(settings, "worker_poll_seconds", 0.05, raising=False)
    # Ceiling far longer than the test: if pickup waited for the timer, this fails.
    monkeypatch.setattr(settings, "worker_idle_max_seconds", 30.0, raising=False)

    seen: list[float] = []
    t0 = time.monotonic()

    async def empty_then_record(session):
        seen.append(time.monotonic() - t0)
        return None

    class _NullSession:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

    monkeypatch.setattr(worker, "_claim_next_job", empty_then_record)
    monkeypatch.setattr(worker.db, "session", lambda: _NullSession())

    task = asyncio.create_task(worker.run_worker_loop())
    # Let it settle into a long wait.
    await asyncio.sleep(0.9)
    checks_before = len(seen)

    worker.notify_new_job()
    await asyncio.sleep(0.15)
    checks_after = len(seen)

    worker.stop_worker()
    await asyncio.wait_for(task, timeout=5)

    assert checks_after > checks_before, (
        "notify_new_job did not wake the loop; a queued job would sit until the "
        "backoff expired"
    )


@pytest.mark.asyncio
async def test_stop_is_not_delayed_by_a_long_backoff(monkeypatch):
    """Shutdown must not block for the idle interval."""
    settings = get_settings()
    monkeypatch.setattr(settings, "worker_poll_seconds", 0.05, raising=False)
    monkeypatch.setattr(settings, "worker_idle_max_seconds", 30.0, raising=False)

    async def always_empty(session):
        return None

    class _NullSession:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *exc):
            return False

    monkeypatch.setattr(worker, "_claim_next_job", always_empty)
    monkeypatch.setattr(worker.db, "session", lambda: _NullSession())

    task = asyncio.create_task(worker.run_worker_loop())
    await asyncio.sleep(0.9)

    t0 = time.monotonic()
    worker.stop_worker()
    await asyncio.wait_for(task, timeout=5)
    assert time.monotonic() - t0 < 1.0, "stop waited for the backoff timer"
