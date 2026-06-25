"""Async SQLAlchemy store (SQLite via aiosqlite). Blocks are stored as JSON on the
card row, not a table-per-block-type (docs/08). The jobs table is the queue."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    func,
    select,
)
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.config import get_settings
from app.store import media as media_store
from app.models.card import (
    Base as CardBase,
    Card,
    CardState,
    ExtractionFlags,
    FailureReason,
    Media,
    Meta,
    PrimaryAction,
    SCHEMA_VERSION,
    Source,
)
from app.models.job import JobState


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_uuid() -> str:
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class CardRow(Base):
    __tablename__ = "cards"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    state: Mapped[str] = mapped_column(String, default=CardState.QUEUED.value, index=True)
    failure_reason: Mapped[str | None] = mapped_column(String, nullable=True)

    source_url: Mapped[str] = mapped_column(String, index=True)
    platform: Mapped[str | None] = mapped_column(String, nullable=True)
    creator: Mapped[str | None] = mapped_column(String, nullable=True)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    resolver: Mapped[str | None] = mapped_column(String, nullable=True)

    content_type: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    type_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    one_liner: Mapped[str | None] = mapped_column(Text, nullable=True)
    tldr: Mapped[str | None] = mapped_column(Text, nullable=True)

    primary_action: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    blocks: Mapped[list] = mapped_column(JSON, default=list)
    thumbnail: Mapped[str | None] = mapped_column(String, nullable=True)
    keyframes: Mapped[list | None] = mapped_column(JSON, nullable=True)
    extraction: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    schema_version: Mapped[str] = mapped_column(String, default=SCHEMA_VERSION)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_utcnow, onupdate=_utcnow
    )
    owner_id: Mapped[str | None] = mapped_column(String, nullable=True)

    def to_card(self) -> Card:
        return Card(
            schema_version=self.schema_version or SCHEMA_VERSION,
            card_id=self.id,
            state=CardState(self.state),
            failure_reason=FailureReason(self.failure_reason)
            if self.failure_reason
            else None,
            source=Source(
                url=self.source_url,
                platform=self.platform,
                creator=self.creator,
                caption=self.caption or "",
                duration_seconds=self.duration_seconds,
                resolver=self.resolver,
            ),
            base=CardBase(
                one_liner=self.one_liner or "",
                tldr=self.tldr or "",
                content_type=self.content_type or "other",
                type_confidence=self.type_confidence or 0.0,
            ),
            primary_action=PrimaryAction(**(self.primary_action or {})),
            blocks=self.blocks or [],
            media=Media(
                thumbnail=media_store.to_media_url(self.thumbnail),
                keyframes=[
                    u
                    for f in (self.keyframes or [])
                    if (u := media_store.to_media_url(f)) is not None
                ],
            ),
            meta=Meta(
                created_at=(self.created_at or _utcnow()).isoformat(),
                extraction=ExtractionFlags(**(self.extraction or {})),
            ),
        )


class JobRow(Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    state: Mapped[str] = mapped_column(String, default=JobState.QUEUED.value, index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


# --------------------------------------------------------------------------- #
# Engine / session lifecycle
# --------------------------------------------------------------------------- #

_engine = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def _ensure_engine():
    global _engine, _sessionmaker
    if _engine is None:
        _engine = create_async_engine(get_settings().database_url, future=True)
        _sessionmaker = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine, _sessionmaker


async def init_db() -> None:
    engine, _ = _ensure_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def dispose_db() -> None:
    global _engine, _sessionmaker
    if _engine is not None:
        await _engine.dispose()
        _engine = None
        _sessionmaker = None


def session() -> AsyncSession:
    _, maker = _ensure_engine()
    assert maker is not None
    return maker()


# --------------------------------------------------------------------------- #
# Convenience queries used across the app
# --------------------------------------------------------------------------- #

async def get_card_row(db: AsyncSession, card_id: str) -> CardRow | None:
    return await db.get(CardRow, card_id)


async def find_card_by_url(db: AsyncSession, url: str) -> CardRow | None:
    res = await db.execute(select(CardRow).where(CardRow.source_url == url))
    return res.scalar_one_or_none()
