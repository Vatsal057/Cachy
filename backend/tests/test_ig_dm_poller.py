"""Tests for Instagram DM poller and account linking."""

from __future__ import annotations

from unittest.mock import MagicMock
import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.auth import get_owner
from app.main import app
from app.models.card import CardState
from app.services.ig_dm_poller import InstagramDMPoller
from app.store import db


@pytest.fixture
def auth_owner():
    app.dependency_overrides[get_owner] = lambda: "test-user-123"
    yield "test-user-123"
    app.dependency_overrides.pop(get_owner, None)


async def test_link_instagram_endpoint(client: AsyncClient, auth_owner: str) -> None:
    # 1. Initially no link
    resp = await client.get("/me/instagram")
    assert resp.status_code == 200
    assert resp.json()["ig_username"] is None

    # 2. Link handle with @
    resp = await client.post("/me/instagram", json={"ig_username": "@Vatsal_Dev"})
    assert resp.status_code == 200
    assert resp.json()["ig_username"] == "vatsal_dev"

    # 3. Verify in DB
    async with db.session() as s:
        owner = await db.get_owner_by_instagram_username(s, ig_username="vatsal_dev")
        assert owner == auth_owner

    # 4. GET verifies link
    resp = await client.get("/me/instagram")
    assert resp.status_code == 200
    assert resp.json()["ig_username"] == "vatsal_dev"

    # 5. DELETE unlinks
    resp = await client.delete("/me/instagram")
    assert resp.status_code == 200
    assert resp.json()["unlinked"] is True

    # 6. Verify unlinked
    resp = await client.get("/me/instagram")
    assert resp.status_code == 200
    assert resp.json()["ig_username"] is None


def test_extract_reel_url() -> None:
    poller = InstagramDMPoller(username="bot", password="pwd")

    # Clip object
    msg_clip = MagicMock()
    msg_clip.clip.code = "CxY123abc"
    msg_clip.media_share = None
    msg_clip.text = None
    msg_clip.xma_share = None
    assert poller.extract_reel_url(msg_clip) == "https://www.instagram.com/reel/CxY123abc/"

    # Media share object
    msg_media = MagicMock()
    msg_media.clip = None
    msg_media.media_share.code = "post999"
    msg_media.text = None
    msg_media.xma_share = None
    assert poller.extract_reel_url(msg_media) == "https://www.instagram.com/p/post999/"

    # Text message with reel link
    msg_text = MagicMock()
    msg_text.clip = None
    msg_text.media_share = None
    msg_text.text = "Check this out https://www.instagram.com/reel/DDDfgh456/?igsh=123"
    msg_text.xma_share = None
    assert poller.extract_reel_url(msg_text) == "https://www.instagram.com/reel/DDDfgh456/"

    # Irrelevant text
    msg_plain = MagicMock()
    msg_plain.clip = None
    msg_plain.media_share = None
    msg_plain.text = "Hey how are you?"
    msg_plain.xma_share = None
    assert poller.extract_reel_url(msg_plain) is None


async def test_process_thread_enqueues_card_for_linked_owner(database) -> None:
    # Set up DB link
    owner_id = "test-uid-dm-owner"
    ig_user = "cool_creator"
    async with db.session() as s:
        await db.link_instagram_account(s, owner_id=owner_id, ig_username=ig_user)

    poller = InstagramDMPoller(username="bot_account", password="pwd")
    poller.cl = MagicMock()
    poller.cl.user_id = 99999999  # Bot user ID

    # Mock incoming thread
    thread = MagicMock()
    thread.id = 12345
    user_sender = MagicMock()
    user_sender.pk = 11111111
    user_sender.username = "cool_creator"
    thread.users = [user_sender]

    msg = MagicMock()
    msg.user_id = 11111111
    msg.clip.code = "ReelXYZ789"
    msg.media_share = None
    msg.text = None
    msg.xma_share = None
    thread.messages = [msg]

    enqueued = await poller._process_thread(thread)
    assert enqueued is True

    # Verify card created in DB with correct owner_id
    async with db.session() as s:
        card = (
            await s.execute(
                select(db.CardRow).where(
                    db.CardRow.source_url == "https://www.instagram.com/reel/ReelXYZ789/"
                )
            )
        ).scalar_one_or_none()
        assert card is not None
        assert card.owner_id == owner_id
        assert card.platform == "instagram"
        assert card.state == CardState.QUEUED.value

    # Verify reply and mark seen called
    poller.cl.direct_send.assert_called_once()
    poller.cl.direct_thread_mark_as_seen.assert_called_once_with("12345")


async def test_process_thread_replies_link_warning_for_unlinked_user(database) -> None:
    poller = InstagramDMPoller(username="bot_account", password="pwd")
    poller.cl = MagicMock()
    poller.cl.user_id = 99999999

    thread = MagicMock()
    thread.id = 54321
    user_sender = MagicMock()
    user_sender.pk = 22222222
    user_sender.username = "unlinked_stranger"
    thread.users = [user_sender]

    msg = MagicMock()
    msg.user_id = 22222222
    msg.clip.code = "ReelABC"
    msg.media_share = None
    msg.text = None
    msg.xma_share = None
    thread.messages = [msg]

    enqueued = await poller._process_thread(thread)
    assert enqueued is False

    # Bot should reply explaining how to link
    poller.cl.direct_send.assert_called_once()
    reply_text = poller.cl.direct_send.call_args[0][0]
    assert "link your instagram" in reply_text.lower()
    poller.cl.direct_thread_mark_as_seen.assert_called_once_with("54321")
