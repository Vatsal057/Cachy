"""Push / badge notification hook (docs/05). Stub for Phase 1 — local notifications
are handled client-side; this is the seam for FCM if real push is added later."""

from __future__ import annotations

import logging

log = logging.getLogger("services.notify")


def notify_card_ready(card_id: str) -> None:
    # Phase 1: no-op (client polls / SSE-streams). Wire FCM here if PUSH_BACKEND=fcm.
    log.debug("card ready (notify stub): %s", card_id)


def notify_card_failed(card_id: str, reason: str) -> None:
    log.debug("card failed (notify stub): %s reason=%s", card_id, reason)
