"""Instagram DM poller service (instagrapi).

Listens for incoming reels shared to the bot's Instagram account via DMs,
resolves the sender to a registered Cachy owner_id, and enqueues the card
in the processing pipeline.
"""

from __future__ import annotations

import asyncio
from io import BytesIO
import logging
import random
import re
import time
from pathlib import Path
from typing import Any

from instagrapi import Client
from instagrapi.exceptions import (
    ChallengeRequired,
    ClientError,
    FeedbackRequired,
    LoginRequired,
)
from requests.adapters import HTTPAdapter
from urllib3.response import HTTPResponse

from app import quota
from app.models.card import CardState
from app.models.job import JobState
from app.pipeline import worker
from app.services import cache
from app.store import db

log = logging.getLogger("services.ig_dm_poller")

_REEL_URL_REGEX = re.compile(
    r"https?://(?:www\.)?instagram\.com/(?:share/)?(?:reel|reels|p)/([a-zA-Z0-9_\-]+)"
)


class ChromeCurlAdapter(HTTPAdapter):
    """Adapter that routes HTTP requests through curl_cffi with Chrome TLS impersonation.

    Bypasses datacenter TLS fingerprint blocking on Instagram endpoints by
    matching genuine Google Chrome BoringSSL ClientHello handshakes.
    """

    def __init__(self, impersonate: str = "chrome124", proxy: str = "") -> None:
        super().__init__()
        try:
            from curl_cffi.requests import Session as CurlSession

            proxies = {"http": proxy, "https": proxy} if proxy else None
            self.session: CurlSession | None = CurlSession(impersonate=impersonate, proxies=proxies)
        except Exception as e:
            log.warning("curl_cffi not available for ChromeCurlAdapter: %s", e)
            self.session = None

    def send(self, request, **kwargs):
        if self.session is None:
            return super().send(request, **kwargs)

        headers = dict(request.headers)
        headers.pop("Host", None)
        headers.pop("host", None)

        resp = self.session.request(
            method=request.method,
            url=request.url,
            headers=headers,
            data=request.body,
            timeout=kwargs.get("timeout", 30),
            allow_redirects=False,
        )

        res_headers = dict(resp.headers)
        res_headers.pop("content-encoding", None)
        res_headers.pop("Content-Encoding", None)

        return self.build_response(
            request,
            HTTPResponse(
                body=BytesIO(resp.content),
                status=resp.status_code,
                headers=res_headers,
                reason=resp.reason,
                preload_content=False,
            ),
        )


class InstagramDMPoller:
    """Polls Instagram direct messages using an instagrapi client."""

    def __init__(
        self,
        username: str,
        password: str,
        session_file: Path | str = "ig_session.json",
        session_data: str = "",
        proxy: str = "",
        poll_interval_seconds: float = 20.0,
    ) -> None:
        self.username: str = username.strip()
        self.password: str = password.strip()
        self.session_file: Path = (
            Path(session_file) if isinstance(session_file, str) else session_file
        )
        self.session_data: str = session_data.strip()
        self.proxy: str = proxy.strip()
        self.poll_interval_seconds: float = poll_interval_seconds
        self.cl: Client = Client()
        self._mount_transports()
        if self.proxy:
            try:
                self.cl.set_proxy(self.proxy)
                log.info("Configured Instagram proxy: %s", self.proxy.split("@")[-1])
            except Exception as e:
                log.warning("Could not set proxy %s: %s", self.proxy, e)
        self._last_checked_timestamp: int = 0
        self._is_logged_in: bool = False

        # Outgoing DM rate limiting & anti-ban protection
        self._dm_timestamps: list[float] = []
        self._dm_hourly_limit: int = 35
        self._dm_cooldown_until: float = 0.0
        self._last_send_time: float = 0.0

        if self.session_data:
            try:
                self.session_file.parent.mkdir(parents=True, exist_ok=True)
                self.session_file.write_text(self.session_data, encoding="utf-8")
                log.info("Initialized Instagram session file from session_data secret (%s)", self.session_file)
            except Exception as e:
                log.warning("Could not write session_data to %s: %s", self.session_file, e)

    def _mount_transports(self) -> None:
        """Mount Chrome TLS impersonation adapter across private & public sessions."""
        try:
            adapter = ChromeCurlAdapter(impersonate="chrome124", proxy=self.proxy)
            if adapter.session is not None:
                self.cl.private.mount("https://", adapter)
                self.cl.private.mount("http://", adapter)
                self.cl.public.mount("https://", adapter)
                self.cl.public.mount("http://", adapter)
                log.debug("Mounted Chrome TLS impersonation adapter on instagrapi")
        except Exception as e:
            log.warning("Could not mount ChromeCurlAdapter: %s", e)

    def login(self) -> bool:
        """Authenticate with Instagram using stored session file or credentials.

        Dumps session settings to disk upon successful authentication to reuse
        cookies and avoid triggering repeated 2FA or checkpoint challenges.
        """
        # Discover alternative session file locations if default does not exist
        if not self.session_file.exists():
            for candidate in (
                Path("ig_session.json"),
                Path("backend/ig_session.json"),
                Path("/app/ig_session.json"),
                Path("/data/ig_session.json"),
            ):
                if candidate.exists():
                    self.session_file = candidate
                    log.info("Discovered Instagram session file at %s", candidate)
                    break

        self._mount_transports()

        if self.session_file.exists():
            try:
                log.info("Loading Instagram session from %s", self.session_file)
                self.cl.load_settings(self.session_file)
                self._mount_transports()
                if self.proxy:
                    try:
                        self.cl.set_proxy(self.proxy)
                    except Exception:
                        pass
                self.cl.account_info()
                self._is_logged_in = True
                log.info("Logged into Instagram using saved session (%s)", self.cl.user_id)
                return True
            except LoginRequired:
                log.warning("Instagram session file expired; logging in with password")
            except ChallengeRequired as e:
                log.error("Instagram checkpoint challenge required: %s", e)
                return False
            except Exception as e:
                log.warning("Could not restore Instagram session (%s); retrying with Chrome TLS transport...", e)
                try:
                    self._mount_transports()
                    self.cl.account_info()
                    self._is_logged_in = True
                    log.info("Logged into Instagram using saved session after retry (%s)", self.cl.user_id)
                    return True
                except Exception as retry_err:
                    log.warning("Could not restore session: %s", retry_err)

        if not self.username or not self.password:
            log.warning("Instagram bot credentials missing; skipping DM poller login")
            return False

        try:
            log.info("Logging into Instagram as @%s with password...", self.username)
            self._mount_transports()
            self.cl.login(self.username, self.password)
            self.session_file.parent.mkdir(parents=True, exist_ok=True)
            self.cl.dump_settings(self.session_file)
            self._mount_transports()
            self._is_logged_in = True
            log.info("Successfully logged into Instagram and dumped session to %s", self.session_file)
            return True
        except ChallengeRequired as e:
            log.error(
                "Instagram checkpoint challenge triggered for @%s: %s. "
                "Log into Instagram from a browser/mobile app to solve the challenge.",
                self.username,
                e,
            )
            return False
        except FeedbackRequired as e:
            log.error("Instagram rate-limit / action block for @%s: %s", self.username, e)
            return False
        except Exception as e:
            log.error("Instagram login failed for @%s: %s", self.username, e)
            return False

    def extract_reel_url(self, msg: Any) -> str | None:
        """Extract an Instagram reel or post permalink from a DirectMessage object."""
        # 1. Direct clip attachment (Reels shared in DM)
        clip = getattr(msg, "clip", None)
        if clip is not None:
            code = getattr(clip, "code", None)
            if code:
                return f"https://www.instagram.com/reel/{code}/"

        # 2. Direct media share (Standard posts/reels shared in DM)
        media_share = getattr(msg, "media_share", None)
        if media_share is not None:
            code = getattr(media_share, "code", None)
            if code:
                return f"https://www.instagram.com/p/{code}/"

        # 3. Plain text message containing a reel or post link
        text = getattr(msg, "text", None)
        if text:
            match = _REEL_URL_REGEX.search(text)
            if match:
                shortcode = match.group(1)
                return f"https://www.instagram.com/reel/{shortcode}/"

        # 4. Check xma_share or fallback links
        xma_share = getattr(msg, "xma_share", None)
        if xma_share is not None:
            if isinstance(xma_share, dict):
                raw_url = (
                    xma_share.get("video_url")
                    or xma_share.get("target_url")
                    or xma_share.get("preview_url")
                )
            else:
                raw_url = (
                    getattr(xma_share, "video_url", None)
                    or getattr(xma_share, "target_url", None)
                    or getattr(xma_share, "preview_url", None)
                )
            if raw_url:
                match = _REEL_URL_REGEX.search(str(raw_url))
                if match:
                    return f"https://www.instagram.com/reel/{match.group(1)}/"

        return None

    async def poll_once(self) -> int:
        """Poll direct message threads and pending requests for new reel shares.

        Returns the number of reels successfully enqueued.
        """
        if not self._is_logged_in:
            if not await asyncio.to_thread(self.login):
                return 0

        threads: list[Any] = []

        # 1. Fetch pending message requests (from new/unapproved senders)
        try:
            pending = await asyncio.to_thread(self.cl.direct_pending_inbox, amount=20)
            for pt in pending:
                tid = getattr(pt, "id", None)
                if tid:
                    try:
                        await asyncio.to_thread(self.cl.direct_pending_approve, int(tid))
                        log.info("Approved pending message request thread %s", tid)
                    except Exception as e:
                        log.debug("Failed to approve pending thread %s: %s", tid, e)
                threads.append(pt)
        except Exception as e:
            log.debug("Error checking pending direct inbox: %s", e)

        # 2. Fetch main direct threads
        try:
            inbox_threads = await asyncio.to_thread(
                self.cl.direct_threads,
                amount=20,
            )
            threads.extend(inbox_threads)
        except LoginRequired:
            log.warning("Instagram session became invalid during polling; re-authenticating")
            self._is_logged_in = False
            return 0
        except ClientError as e:
            log.warning("Instagram client error while fetching direct threads: %s", e)
            return 0
        except Exception as e:
            log.warning("Unexpected error fetching direct threads: %s", e)
            return 0

        # Deduplicate threads
        seen_tids: set[Any] = set()
        unique_threads: list[Any] = []
        for t in threads:
            tid = getattr(t, "id", None)
            if tid and tid not in seen_tids:
                seen_tids.add(tid)
                unique_threads.append(t)

        enqueued_count = 0
        for thread in unique_threads:
            try:
                enqueued = await self._process_thread(thread)
                if enqueued:
                    enqueued_count += 1
            except Exception as e:
                log.error("Failed to process direct thread %s: %s", getattr(thread, "id", "?"), e)

        return enqueued_count

    async def _process_thread(self, thread: Any) -> bool:
        """Process a single direct message thread.
        
        Handles individual reels and batches of reels sent in consecutive messages
        prior to the bot's reply. Respects user card quotas.
        """
        messages = getattr(thread, "messages", [])
        if not messages:
            return False

        bot_user_id = str(getattr(self.cl, "user_id", ""))

        # Collect all consecutive un-replied user messages (newest first)
        user_messages: list[Any] = []
        for msg in messages:
            msg_user_id = str(getattr(msg, "user_id", ""))
            if msg_user_id and bot_user_id and msg_user_id == bot_user_id:
                break
            user_messages.append(msg)
            if len(user_messages) >= 10:
                break

        if not user_messages:
            return False

        thread_id = getattr(thread, "id", None)
        if not thread_id:
            return False

        # Identify sender username from newest user message
        sender_id = str(getattr(user_messages[0], "user_id", ""))
        users = getattr(thread, "users", [])
        sender_username: str | None = None
        for u in users:
            if str(getattr(u, "pk", "")) == sender_id or str(getattr(u, "id", "")) == sender_id:
                sender_username = getattr(u, "username", None)
                break
        if not sender_username and users:
            sender_username = getattr(users[0], "username", None)

        if not sender_username:
            log.warning("Thread %s has no identifiable sender username", thread_id)
            return False

        sender_username = sender_username.lower().strip()

        # 1. Resolve Cachy owner_id from database
        async with db.session() as s:
            owner_id = await db.get_owner_by_instagram_username(s, ig_username=sender_username)

        if not owner_id:
            log.info("Direct message from unlinked Instagram user @%s", sender_username)
            reply = (
                "Welcome to Cachy! ✨\n\n"
                "To auto-save reels sent here, link your Instagram handle "
                f"(@{sender_username}) in the Cachy app under Profile."
            )
            await asyncio.to_thread(self._send_reply, thread_id, reply)
            await asyncio.to_thread(self._mark_seen, thread_id)
            return False

        # 2. Extract reel URLs from all un-replied messages
        urls: list[str] = []
        for msg in user_messages:
            url = self.extract_reel_url(msg)
            if url and url not in urls:
                urls.append(url)

        if not urls:
            log.debug("No reel URLs found in messages from @%s", sender_username)
            await asyncio.to_thread(self._mark_seen, thread_id)
            return False

        # 3. Enqueue cards in pipeline for this owner
        new_count = 0
        degraded_count = 0
        for url in urls:
            is_new, is_degraded = await self._enqueue_card(url, owner_id)
            if is_new:
                new_count += 1
                if is_degraded:
                    degraded_count += 1

        # 4. Reply with tailored confirmation (varied phrasing to prevent hash spam filters)
        if new_count == 1:
            if degraded_count > 0:
                reply = "Got it! Building your Cachy card (daily AI quota reached — saving basic summary)... ⚡"
            else:
                reply = random.choice([
                    "Got it! Building your Cachy card... ⚡",
                    "On it! Building your Cachy card... ⚡",
                    "Received! Adding this reel to your Cachy shelf... ⚡",
                    "Got your reel! Building your summary card... ⚡",
                ])
        elif new_count > 1:
            if degraded_count > 0:
                reply = f"Got it! Building {new_count} Cachy cards ({degraded_count} basic due to daily AI quota)... ⚡"
            else:
                reply = random.choice([
                    f"Got it! Building {new_count} Cachy cards... ⚡",
                    f"On it! Building {new_count} Cachy cards... ⚡",
                    f"Received! Adding {new_count} reels to your Cachy shelf... ⚡",
                ])
        else:
            if len(urls) == 1:
                reply = "This reel is already saved on your Cachy shelf! 📚"
            else:
                reply = "All these reels are already saved on your Cachy shelf! 📚"

        await asyncio.to_thread(self._send_reply, thread_id, reply)
        await asyncio.to_thread(self._mark_seen, thread_id)
        return new_count > 0

    async def _enqueue_card(self, url: str, owner_id: str) -> tuple[bool, bool]:
        """Enqueue the reel URL as a card for owner_id. Returns (is_new, is_degraded)."""
        async with db.session() as s:
            existing = await cache.existing_card_for_url(s, url, owner_id=owner_id)
            if existing is not None:
                log.info("Reel %s already exists for owner %s (deduped)", url, owner_id)
                return False, False

            # Check daily card budget
            within_budget = await quota.card_budget(owner_id, None)
            degraded = not within_budget

            card = db.CardRow(
                source_url=url,
                platform="instagram",
                state=CardState.QUEUED.value,
                blocks=[],
                owner_id=owner_id,
            )
            s.add(card)
            await s.flush()
            job = db.JobRow(card_id=card.id, state=JobState.QUEUED.value, degraded=degraded)
            s.add(job)
            await s.commit()
            worker.notify_new_job()
            log.info("Queued reel %s for owner %s (degraded=%s) via Instagram DM", url, owner_id, degraded)
            return True, degraded

    def _send_reply(self, thread_id: str | int, text: str) -> bool:
        """Send a direct message reply in thread with rate-limiting and anti-ban safeguards.

        Returns True if sent, False if dropped due to rate limit, circuit breaker, or error.
        """
        now = time.monotonic()

        # 1. Circuit breaker check (e.g. following FeedbackRequired or action block)
        if now < self._dm_cooldown_until:
            remaining = int(self._dm_cooldown_until - now)
            log.warning(
                "Instagram DM circuit breaker active (%ds remaining); skipping reply to thread %s",
                remaining,
                thread_id,
            )
            return False

        # 2. Hourly volume limit check (rolling 3600s window)
        self._dm_timestamps = [t for t in self._dm_timestamps if now - t < 3600.0]
        if len(self._dm_timestamps) >= self._dm_hourly_limit:
            log.warning(
                "Hourly Instagram DM limit reached (%d/%d); skipping reply to thread %s to protect account",
                len(self._dm_timestamps),
                self._dm_hourly_limit,
                thread_id,
            )
            return False

        # 3. Pacing: enforce minimum delay between consecutive outgoing DMs
        elapsed = now - self._last_send_time
        target_gap = random.uniform(1.5, 3.0)
        if self._last_send_time > 0 and elapsed < target_gap:
            time.sleep(target_gap - elapsed)

        # 4. Attempt send with exception handling
        try:
            self.cl.direct_send(text, thread_ids=[int(thread_id)])
            now_sent = time.monotonic()
            self._dm_timestamps.append(now_sent)
            self._last_send_time = now_sent
            return True
        except (FeedbackRequired, ClientError) as e:
            err_str = str(e).lower()
            if "feedback" in err_str or isinstance(e, FeedbackRequired) or "action blocked" in err_str:
                self._dm_cooldown_until = time.monotonic() + 1800.0  # 30-min backoff
                log.error(
                    "Instagram action block (FeedbackRequired) triggered. Pausing outgoing DMs for 30m to protect account: %s",
                    e,
                )
            else:
                log.warning("ClientError sending DM in thread %s: %s", thread_id, e)
            return False
        except Exception as e:
            log.warning("Failed to send DM reply in thread %s: %s", thread_id, e)
            return False

    def _mark_seen(self, thread_id: str | int) -> None:
        """Mark a thread as seen so it leaves the unread inbox filter."""
        try:
            self.cl.direct_thread_mark_as_seen(str(thread_id))
        except Exception as e:
            log.debug("Failed to mark thread %s as seen: %s", thread_id, e)


async def run_ig_poller_loop(poller: InstagramDMPoller, stop_event: asyncio.Event) -> None:
    """Run the Instagram DM poller loop continuously with anti-ban jitter and backoff."""
    log.info("Starting Instagram DM poller loop (interval: %ss)", poller.poll_interval_seconds)
    consecutive_errors = 0
    while not stop_event.is_set():
        try:
            await poller.poll_once()
            consecutive_errors = 0
        except asyncio.CancelledError:
            break
        except Exception as e:
            consecutive_errors = min(consecutive_errors + 1, 5)
            log.error("Unhandled error in Instagram DM poller loop: %s", e)

        # Base interval with jitter ±3s to avoid mechanical periodic request patterns
        delay = max(10.0, poller.poll_interval_seconds + random.uniform(-3.0, 3.0))
        if consecutive_errors > 0:
            delay = min(180.0, delay * (1.5 ** consecutive_errors))

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=delay)
        except asyncio.TimeoutError:
            pass
        except asyncio.CancelledError:
            break
    log.info("Instagram DM poller loop stopped")

