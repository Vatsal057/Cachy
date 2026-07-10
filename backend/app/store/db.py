"""Async SQLAlchemy store (SQLite via aiosqlite). Blocks are stored as JSON on the
card row, not a table-per-block-type (docs/08). The jobs table is the queue."""

from __future__ import annotations

import difflib
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
    inspect as sa_inspect,
    select,
    update,
)
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.orm.attributes import flag_modified

from app.config import get_settings
from app.store import media as media_store
from app.models.artifact import ArtifactType, CatalogEntry
from app.models.concept import ConceptEntry
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

_COLLECTION_NAMES: dict[str, str] = {
    "recipe": "Recipes",
    "workout": "Workouts",
    "tutorial": "Tutorials",
    "tip": "Tips",
    "product_list": "Products",
    "travel": "Travel",
    "news_explainer": "Explainers",
    "other": "Notes",
}


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_uuid() -> str:
    return str(uuid.uuid4())


class Base(DeclarativeBase):
    pass


class CollectionRow(Base):
    """User-visible folder. System collections auto-created per content_type;
    custom collections created by the user and manually populated."""

    __tablename__ = "collections"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    name: Mapped[str] = mapped_column(Text)
    # Wire value of ContentType (e.g. "recipe"). None for custom collections.
    system_type: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    is_custom: Mapped[bool] = mapped_column(Boolean, default=False)
    owner_id: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


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

    # Collection this card belongs to (auto-assigned by pipeline, user-overridable).
    collection_id: Mapped[str | None] = mapped_column(
        String, ForeignKey("collections.id", ondelete="SET NULL"), nullable=True, index=True
    )

    schema_version: Mapped[str] = mapped_column(String, default=SCHEMA_VERSION)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
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
            collection_id=self.collection_id,
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
    saved: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    # On-demand LLM detail ("what is this"), filled via the Fetch info action.
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
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


class ConceptRow(Base):
    """A deduplicated concept node: one evergreen idea, many source cards.
    Dedupe key is name_norm (no type axis). Mirrors ArtifactRow."""

    __tablename__ = "concepts"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    name: Mapped[str] = mapped_column(Text)
    name_norm: Mapped[str] = mapped_column(String, index=True)
    source_card_ids: Mapped[list] = mapped_column(JSON, default=list)
    definition: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )

    def to_entry(self) -> ConceptEntry:
        return ConceptEntry(
            id=self.id,
            name=self.name,
            source_card_ids=list(self.source_card_ids or []),
            definition=self.definition,
            created_at=(self.created_at or _utcnow()).isoformat(),
        )


class ConversationRow(Base):
    """A persisted AI-generated conversation log, scoped to an owner (docs/14).

    Preserves text that used to be stateless: single-card chat, rabbit-hole
    explorations, and library chat. Isolation is by `owner_id` (the name entered
    at onboarding, carried on the X-Owner-Id header) so one user never sees
    another's generations. Uniquely keyed by (owner_id, kind, card_id, thread):
      - chat:         card_id set, thread NULL
      - rabbit_hole:  card_id set, thread = the root topic the journey started from
      - library_chat: card_id NULL, thread NULL
    """

    __tablename__ = "conversations"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    owner_id: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    # "chat" | "rabbit_hole" | "library_chat"
    kind: Mapped[str] = mapped_column(String, index=True)
    card_id: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    # Rabbit-hole root topic; NULL for chat / library_chat.
    thread: Mapped[str | None] = mapped_column(String, nullable=True)
    # chat: [{role, content}]; rabbit_hole: [{topic, explanation, threads}].
    payload: Mapped[list] = mapped_column(JSON, default=list)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, onupdate=_utcnow
    )


class JobRow(Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    card_id: Mapped[str] = mapped_column(ForeignKey("cards.id"), index=True)
    state: Mapped[str] = mapped_column(String, default=JobState.QUEUED.value, index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Past-quota card creation: worker skips AI structuring, paragraph fallback.
    degraded: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ConnectionRow(Base):
    """A cached 'serendipity' link between two of an owner's cards — a surprising
    but real connection, explained once by the LLM and stored so the Knowledge
    Feed and Connections view can show it cheaply. Card ids are stored canonically
    (a < b) so a pair is deduped regardless of discovery order. Owner-scoped."""

    __tablename__ = "connections"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_new_uuid)
    owner_id: Mapped[str | None] = mapped_column(String, nullable=True, index=True)
    card_a_id: Mapped[str] = mapped_column(String, index=True)
    card_b_id: Mapped[str] = mapped_column(String, index=True)
    blurb: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow)


class ClaimRow(Base):
    """Legacy display-name -> uid claims; first claim wins."""

    __tablename__ = "claims"

    name: Mapped[str] = mapped_column(String, primary_key=True)
    uid: Mapped[str] = mapped_column(String, nullable=False)


class UsageRow(Base):
    """Daily metered usage. One row per (owner, UTC day, kind); owner_id also
    stores "ip:<addr>" rows for the anonymous-farming IP cap."""

    __tablename__ = "usage"

    owner_id: Mapped[str] = mapped_column(String, primary_key=True)
    day: Mapped[str] = mapped_column(String, primary_key=True)  # "YYYY-MM-DD" UTC
    kind: Mapped[str] = mapped_column(String, primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)


def _today() -> str:
    """Current UTC day key."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


async def spend_usage(
    db_session: AsyncSession, *, owner_id: str, kind: str, limit: int
) -> tuple[bool, int]:
    """Increment today's counter unless at limit. Returns (allowed, used_after)."""
    day = _today()
    row = await db_session.get(UsageRow, (owner_id, day, kind))
    if row is None:
        row = UsageRow(owner_id=owner_id, day=day, kind=kind, count=0)
        db_session.add(row)
    if row.count >= limit:
        return False, row.count
    row.count += 1
    await db_session.commit()
    return True, row.count


async def claim_owner(db_session: AsyncSession, *, name: str, uid: str) -> int | None:
    """Re-point every legacy row owned by `name` to `uid`. None = taken."""
    existing = await db_session.get(ClaimRow, name)
    if existing is not None:
        return 0 if existing.uid == uid else None
    db_session.add(ClaimRow(name=name, uid=uid))
    total = 0
    for model in (CardRow, CollectionRow, ConversationRow, ConnectionRow):
        res = await db_session.execute(
            update(model).where(model.owner_id == name).values(owner_id=uid)
        )
        total += res.rowcount or 0
    await db_session.commit()
    return total


# --------------------------------------------------------------------------- #
# Engine / session lifecycle
# --------------------------------------------------------------------------- #

_engine = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def _normalize_url(url: str) -> tuple[str, dict]:
    """Convert connection URL to asyncpg format.

    asyncpg rejects psycopg2-style query params (sslmode=); translate them to
    connect_args instead. Returns (normalized_url, connect_args)."""
    import re
    if url.startswith("postgresql://") or url.startswith("postgres://"):
        url = url.replace("://", "+asyncpg://", 1)
    connect_args: dict = {}
    if "sslmode=" in url:
        import ssl
        try:
            import certifi
            ctx = ssl.create_default_context(cafile=certifi.where())
        except ImportError:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        connect_args["ssl"] = ctx
        url = re.sub(r"[?&]sslmode=[^&]*", "", url).rstrip("?").rstrip("&")
    return url, connect_args


def _ensure_engine():
    global _engine, _sessionmaker
    if _engine is None:
        url, connect_args = _normalize_url(get_settings().database_url)
        _engine = create_async_engine(url, future=True, connect_args=connect_args)
        _sessionmaker = async_sessionmaker(_engine, expire_on_commit=False)
    return _engine, _sessionmaker


async def init_db() -> None:
    engine, _ = _ensure_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        if "postgresql" in str(conn.engine.url):
            for tbl, cols in {
                "collections": ["created_at"],
                "cards": ["created_at", "updated_at"],
                "artifacts": ["created_at", "updated_at"],
                "concepts": ["created_at", "updated_at"],
                "jobs": ["created_at", "started_at", "finished_at"],
            }.items():
                for col in cols:
                    try:
                        await conn.exec_driver_sql(
                            f"ALTER TABLE {tbl} ALTER COLUMN {col} TYPE TIMESTAMP WITH TIME ZONE USING {col} AT TIME ZONE 'UTC'"
                        )
                    except Exception:
                        pass
        # Lightweight migration: backfill columns added after a table already
        # existed (create_all never ALTERs). HF deploys are ephemeral, but a
        # persisted dev DB needs these added so SELECTs don't break.
        await _add_missing_columns(
            conn,
            "artifacts",
            {
                "saved": "BOOLEAN DEFAULT FALSE",
                "description": "TEXT",
            },
        )
        await _add_missing_columns(
            conn,
            "cards",
            {
                "action_items": "JSON",  # docs/13 — added in schema 1.3
                "insight": "JSON",  # docs/14 — added in schema 1.4
                "collection_id": "TEXT",  # schema 1.5 — collections FK
            },
        )
        await _add_missing_columns(
            conn,
            "collections",
            {
                "system_type": "TEXT",
                "owner_id": "TEXT",
            },
        )
        await _add_missing_columns(
            conn,
            "jobs",
            {
                "degraded": "BOOLEAN DEFAULT 0",  # quota-degraded card creation
            },
        )
        await _add_missing_columns(
            conn,
            "concepts",
            {
                "definition": "TEXT",
            },
        )


async def _add_missing_columns(conn, table: str, columns: dict[str, str]) -> None:
    try:
        existing = await conn.run_sync(
            lambda sync_conn: {col["name"] for col in sa_inspect(sync_conn).get_columns(table)}
        )
    except Exception:
        return  # table not yet created; create_all handles it
    for name, ddl in columns.items():
        if name not in existing:
            await conn.exec_driver_sql(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")


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


async def find_card_by_url(
    db: AsyncSession, url: str, owner_id: str | None = None
) -> CardRow | None:
    stmt = select(CardRow).where(CardRow.source_url == url)
    if owner_id is not None:
        stmt = stmt.where(CardRow.owner_id == owner_id)
    res = await db.execute(stmt)
    return res.scalars().first()


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
    saved: bool = False,
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
            saved=saved,
        )
        db.add(row)
    else:
        if saved:
            row.saved = True
        if card_id not in (row.source_card_ids or []):
            row.source_card_ids = [*(row.source_card_ids or []), card_id]
            flag_modified(row, "source_card_ids")
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


# --------------------------------------------------------------------------- #
# Collections
# --------------------------------------------------------------------------- #

async def get_or_create_collection(
    db_session: AsyncSession,
    *,
    owner_id: str | None,
    system_type: str,
) -> CollectionRow:
    """Get the system collection for this owner+type, creating it if absent."""
    res = await db_session.execute(
        select(CollectionRow).where(
            CollectionRow.owner_id == owner_id,
            CollectionRow.system_type == system_type,
            CollectionRow.is_custom.is_(False),
        )
    )
    row = res.scalar_one_or_none()
    if row is None:
        row = CollectionRow(
            name=_COLLECTION_NAMES.get(system_type, system_type.capitalize()),
            system_type=system_type,
            is_custom=False,
            owner_id=owner_id,
        )
        db_session.add(row)
        await db_session.commit()
    return row


async def list_collections(
    db_session: AsyncSession, owner_id: str | None
) -> list[tuple[CollectionRow, int]]:
    """Return all collections for this owner with card counts."""
    res = await db_session.execute(
        select(CollectionRow)
        .where(CollectionRow.owner_id == owner_id)
        .order_by(CollectionRow.is_custom, CollectionRow.created_at)
    )
    rows = res.scalars().all()
    result: list[tuple[CollectionRow, int]] = []
    for row in rows:
        count_res = await db_session.execute(
            select(func.count()).select_from(CardRow).where(
                CardRow.collection_id == row.id
            )
        )
        count = count_res.scalar_one() or 0
        result.append((row, count))
    return result


async def create_custom_collection(
    db_session: AsyncSession, *, name: str, owner_id: str | None
) -> CollectionRow:
    row = CollectionRow(
        name=name.strip(),
        system_type=None,
        is_custom=True,
        owner_id=owner_id,
    )
    db_session.add(row)
    await db_session.commit()
    return row


async def rename_collection(
    db_session: AsyncSession, collection_id: str, name: str
) -> CollectionRow | None:
    row = await db_session.get(CollectionRow, collection_id)
    if row is None:
        return None
    row.name = name.strip()
    await db_session.commit()
    return row


async def delete_collection(
    db_session: AsyncSession, collection_id: str
) -> bool:
    """Delete a custom collection; returns False if not found or not custom."""
    row = await db_session.get(CollectionRow, collection_id)
    if row is None or not row.is_custom:
        return False
    # Detach cards from this collection before deleting.
    from sqlalchemy import update as sa_update
    await db_session.execute(
        sa_update(CardRow)
        .where(CardRow.collection_id == collection_id)
        .values(collection_id=None)
    )
    await db_session.delete(row)
    await db_session.commit()
    return True


async def move_card_to_collection(
    db_session: AsyncSession, card_id: str, collection_id: str | None
) -> CardRow | None:
    row = await db_session.get(CardRow, card_id)
    if row is None:
        return None
    row.collection_id = collection_id
    await db_session.commit()
    return row


# --------------------------------------------------------------------------- #
# Concepts
# --------------------------------------------------------------------------- #

def _norm_name(name: str) -> str:
    return " ".join(name.lower().split())


def _is_similar_concept(norm1: str, norm2: str) -> bool:
    if norm1 == norm2:
        return True
    words1 = set(norm1.split())
    words2 = set(norm2.split())
    if len(words1) >= 2 and len(words2) >= 2:
        if words1 <= words2 or words2 <= words1:
            return True
        intersection = words1 & words2
        union = words1 | words2
        if len(intersection) / len(union) >= 0.65:
            return True
    ratio = difflib.SequenceMatcher(None, norm1, norm2).ratio()
    return ratio >= 0.78


async def upsert_concept(
    db: AsyncSession,
    *,
    card_id: str,
    name: str,
) -> ConceptRow:
    """Insert a concept or merge into the existing one (dedupe by exact or fuzzy similarity).
    Appends card_id to source_card_ids."""
    norm = _norm_name(name)
    res = await db.execute(
        select(ConceptRow).where(ConceptRow.name_norm == norm)
    )
    row = res.scalar_one_or_none()
    if row is None:
        all_rows = (await db.execute(select(ConceptRow))).scalars().all()
        for c in all_rows:
            if _is_similar_concept(norm, c.name_norm):
                row = c
                break
    if row is None:
        row = ConceptRow(
            name=name,
            name_norm=norm,
            source_card_ids=[card_id],
        )
        db.add(row)
    else:
        if card_id not in (row.source_card_ids or []):
            row.source_card_ids = [*(row.source_card_ids or []), card_id]
            flag_modified(row, "source_card_ids")
    await db.commit()
    return row


async def set_concept_definition(
    db: AsyncSession, concept_id: str, definition: str
) -> ConceptRow | None:
    """Persist the on-demand LLM definition for a concept."""
    row = await db.get(ConceptRow, concept_id)
    if row is None:
        return None
    row.definition = definition
    await db.commit()
    return row


async def cleanup_after_card_deletion(
    db: AsyncSession, card_id: str
) -> None:
    """Clean up orphaned collections, concepts, and catalog artifacts after a card is deleted."""
    # 0. Drop persisted AI conversations + cached connections for this card.
    await delete_card_conversations(db, card_id)
    await delete_card_connections(db, card_id)

    # 1. Clean up concepts referencing this card
    concepts = (await db.execute(select(ConceptRow))).scalars().all()
    for concept in concepts:
        current_ids = list(concept.source_card_ids or [])
        if card_id in current_ids:
            new_ids = [c for c in current_ids if c != card_id]
            if not new_ids:
                await db.delete(concept)
            else:
                concept.source_card_ids = new_ids
                flag_modified(concept, "source_card_ids")

    # 2. Clean up catalog artifacts referencing this card
    artifacts = (await db.execute(select(ArtifactRow))).scalars().all()
    for art in artifacts:
        current_ids = list(art.source_card_ids or [])
        if card_id in current_ids:
            new_ids = [c for c in current_ids if c != card_id]
            if not new_ids:
                await db.delete(art)
            else:
                art.source_card_ids = new_ids
                flag_modified(art, "source_card_ids")

    # 3. Clean up empty custom collections
    cols = (
        await db.execute(
            select(CollectionRow).where(CollectionRow.is_custom.is_(True))
        )
    ).scalars().all()
    for col in cols:
        count_res = await db.execute(
            select(func.count())
            .select_from(CardRow)
            .where(CardRow.collection_id == col.id)
        )
        if (count_res.scalar_one() or 0) == 0:
            await db.delete(col)


# --------------------------------------------------------------------------- #
# Conversations — persisted AI text, owner-scoped (docs/14)
# --------------------------------------------------------------------------- #

async def get_conversation(
    db: AsyncSession,
    *,
    owner_id: str | None,
    kind: str,
    card_id: str | None = None,
    thread: str | None = None,
) -> ConversationRow | None:
    """Fetch the stored conversation for this owner + key, or None. NULL keys
    match with IS NULL so the anonymous (no-name) owner is handled too."""
    stmt = select(ConversationRow).where(
        ConversationRow.owner_id.is_(None) if owner_id is None
        else ConversationRow.owner_id == owner_id,
        ConversationRow.kind == kind,
        ConversationRow.card_id.is_(None) if card_id is None
        else ConversationRow.card_id == card_id,
        ConversationRow.thread.is_(None) if thread is None
        else ConversationRow.thread == thread,
    )
    res = await db.execute(stmt)
    return res.scalars().first()


async def save_conversation(
    db: AsyncSession,
    *,
    owner_id: str | None,
    kind: str,
    payload: list,
    card_id: str | None = None,
    thread: str | None = None,
) -> ConversationRow:
    """Upsert the conversation log for this owner + key. Replaces the payload
    wholesale — callers pass the full, current message/step list."""
    row = await get_conversation(
        db, owner_id=owner_id, kind=kind, card_id=card_id, thread=thread
    )
    if row is None:
        row = ConversationRow(
            owner_id=owner_id,
            kind=kind,
            card_id=card_id,
            thread=thread,
            payload=payload,
        )
        db.add(row)
    else:
        row.payload = payload
        flag_modified(row, "payload")
    await db.commit()
    return row


async def delete_card_conversations(db: AsyncSession, card_id: str) -> None:
    """Drop all persisted conversations tied to a card (called on card delete)."""
    from sqlalchemy import delete as sa_delete

    await db.execute(
        sa_delete(ConversationRow).where(ConversationRow.card_id == card_id)
    )


# --------------------------------------------------------------------------- #
# Connections — cached serendipity links (Knowledge Feed / Connections view)
# --------------------------------------------------------------------------- #

def _canonical_pair(a: str, b: str) -> tuple[str, str]:
    """Order two card ids so a pair keys the same regardless of arg order."""
    return (a, b) if a <= b else (b, a)


async def get_connection(
    db: AsyncSession, *, owner_id: str | None, card_a: str, card_b: str
) -> ConnectionRow | None:
    a, b = _canonical_pair(card_a, card_b)
    stmt = select(ConnectionRow).where(
        ConnectionRow.owner_id.is_(None) if owner_id is None
        else ConnectionRow.owner_id == owner_id,
        ConnectionRow.card_a_id == a,
        ConnectionRow.card_b_id == b,
    )
    return (await db.execute(stmt)).scalars().first()


async def save_connection(
    db: AsyncSession, *, owner_id: str | None, card_a: str, card_b: str, blurb: str
) -> ConnectionRow:
    a, b = _canonical_pair(card_a, card_b)
    row = await get_connection(db, owner_id=owner_id, card_a=a, card_b=b)
    if row is None:
        row = ConnectionRow(owner_id=owner_id, card_a_id=a, card_b_id=b, blurb=blurb)
        db.add(row)
    else:
        row.blurb = blurb
    await db.commit()
    return row


async def list_connections(
    db: AsyncSession, *, owner_id: str | None, limit: int = 50
) -> list[ConnectionRow]:
    stmt = (
        select(ConnectionRow)
        .where(
            ConnectionRow.owner_id.is_(None) if owner_id is None
            else ConnectionRow.owner_id == owner_id
        )
        .order_by(ConnectionRow.created_at.desc())
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())


async def delete_card_connections(db: AsyncSession, card_id: str) -> None:
    """Drop cached connections that reference a deleted card."""
    from sqlalchemy import delete as sa_delete, or_

    await db.execute(
        sa_delete(ConnectionRow).where(
            or_(
                ConnectionRow.card_a_id == card_id,
                ConnectionRow.card_b_id == card_id,
            )
        )
    )


async def reset_orphaned_processing_jobs(db: AsyncSession) -> int:
    """Reset jobs stuck in PROCESSING back to QUEUED on startup."""
    res = await db.execute(
        update(JobRow)
        .where(JobRow.state == "processing")
        .values(state="queued")
    )
    await db.commit()
    return res.rowcount
