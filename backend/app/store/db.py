"""Async SQLAlchemy store (SQLite via aiosqlite). Blocks are stored as JSON on the
card row, not a table-per-block-type (docs/08). The jobs table is the queue."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
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
from app.models.artifact import ArtifactType, CatalogEntry
from app.models.card import (
    ActionItems,
    Base as CardBase,
    Card,
    CardState,
    ExtractionFlags,
    FailureReason,
    Insight,
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
    tags: Mapped[list | None] = mapped_column(JSON, nullable=True)  # auto-tags (docs/09)
    embedding: Mapped[list | None] = mapped_column(JSON, nullable=True)  # semantic search (docs/09)

    primary_action: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    # {followed: bool, items: [{id, text, done}]} — the to-do list (docs/13).
    action_items: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    blocks: Mapped[list] = mapped_column(JSON, default=list)
    # Deep-analysis layer (docs/14): null for simple cards, filled by the gated pass.
    insight: Mapped[dict | None] = mapped_column(JSON, nullable=True)
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
                tags=list(self.tags or []),
            ),
            primary_action=PrimaryAction(**(self.primary_action or {})),
            action_items=ActionItems(**(self.action_items or {})),
            blocks=self.blocks or [],
            insight=Insight(**self.insight) if self.insight else None,
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


class ArtifactRow(Base):
    """A deduplicated catalog item (docs/12): one referenced thing, many source
    cards. Dedupe key is (type, title_norm). Thumbnails are remote URLs."""

    __tablename__ = "artifacts"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    type: Mapped[str] = mapped_column(String, default="other", index=True)
    title: Mapped[str] = mapped_column(Text)
    title_norm: Mapped[str] = mapped_column(String, index=True)
    creator: Mapped[str | None] = mapped_column(String, nullable=True)
    year: Mapped[int | None] = mapped_column(Integer, nullable=True)
    thumbnail: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_card_ids: Mapped[list] = mapped_column(JSON, default=list)
    # Only saved rows show in the catalog tab; unsaved rows are card references only.
    saved: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    # On-demand LLM detail ("what is this"), filled via the Fetch info action.
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=_utcnow, onupdate=_utcnow
    )

    def to_entry(self) -> CatalogEntry:
        return CatalogEntry(
            id=self.id,
            type=ArtifactType(self.type) if self.type else ArtifactType.OTHER,
            title=self.title,
            creator=self.creator,
            year=self.year,
            thumbnail=self.thumbnail,
            source_card_ids=list(self.source_card_ids or []),
            created_at=(self.created_at or _utcnow()).isoformat(),
            saved=bool(self.saved),
            description=self.description,
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
        # Lightweight migration: backfill columns added after a table already
        # existed (create_all never ALTERs). HF deploys are ephemeral, but a
        # persisted dev DB needs these added so SELECTs don't break.
        await _add_missing_columns(
            conn,
            "artifacts",
            {
                "saved": "BOOLEAN DEFAULT 1",
                "description": "TEXT",
            },
        )
        await _add_missing_columns(
            conn,
            "cards",
            {
                "action_items": "JSON",  # docs/13 — added in schema 1.3
                "insight": "JSON",  # docs/14 — added in schema 1.4
            },
        )


async def _add_missing_columns(conn, table: str, columns: dict[str, str]) -> None:
    rows = await conn.exec_driver_sql(f"PRAGMA table_info({table})")
    existing = {r[1] for r in rows.fetchall()}
    for name, ddl in columns.items():
        if name not in existing:
            await conn.exec_driver_sql(
                f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"
            )


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


def _norm_title(title: str) -> str:
    return " ".join(title.lower().split())


async def upsert_artifact(
    db: AsyncSession,
    *,
    card_id: str,
    type_: str,
    title: str,
    creator: str | None,
    year: int | None,
    thumbnail: str | None,
) -> ArtifactRow:
    """Insert a catalog item or merge into the existing one (dedupe by type+title).
    Appends card_id to source_card_ids and backfills a missing thumbnail."""
    norm = _norm_title(title)
    res = await db.execute(
        select(ArtifactRow).where(
            ArtifactRow.type == type_, ArtifactRow.title_norm == norm
        )
    )
    row = res.scalar_one_or_none()
    if row is None:
        row = ArtifactRow(
            type=type_,
            title=title,
            title_norm=norm,
            creator=creator,
            year=year,
            thumbnail=thumbnail,
            source_card_ids=[card_id],
            saved=True,
        )
        db.add(row)
    else:
        if card_id not in (row.source_card_ids or []):
            row.source_card_ids = [*(row.source_card_ids or []), card_id]
        if not row.thumbnail and thumbnail:
            row.thumbnail = thumbnail
        if not row.creator and creator:
            row.creator = creator
        if not row.year and year:
            row.year = year
    await db.commit()
    return row


async def set_artifact_saved(
    db: AsyncSession, artifact_id: str, saved: bool
) -> ArtifactRow | None:
    """Toggle whether an artifact appears in the catalog tab. Unsaving keeps the
    row (it still backs per-card references); it just leaves the catalog."""
    row = await db.get(ArtifactRow, artifact_id)
    if row is None:
        return None
    row.saved = saved
    await db.commit()
    return row


async def set_artifact_description(
    db: AsyncSession, artifact_id: str, description: str
) -> ArtifactRow | None:
    """Persist the on-demand LLM detail for an artifact (Fetch info)."""
    row = await db.get(ArtifactRow, artifact_id)
    if row is None:
        return None
    row.description = description
    await db.commit()
    return row
