"""Catalog endpoints (docs/12): the aggregated, deduplicated view of every
artifact referenced across all cards. Read-mostly; entries are created by the
worker, not by clients."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.models.artifact import ArtifactType, CatalogEntry
from app.services import llm_catalog
from app.store import db

router = APIRouter(prefix="/catalog", tags=["catalog"])


class CatalogDetail(BaseModel):
    entry: CatalogEntry
    source_card_ids: list[str]


@router.get("", response_model=list[CatalogEntry])
async def list_catalog(
    type: ArtifactType | None = None,
    card_id: str | None = None,
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
) -> list[CatalogEntry]:
    async with db.session() as session:
        stmt = select(db.ArtifactRow).order_by(db.ArtifactRow.created_at.desc())
        if type is not None:
            stmt = stmt.where(db.ArtifactRow.type == type.value)
        # Catalog tab (no card_id) shows only user-saved items. A card_id filter
        # is the reader's References strip, which lists every referenced artifact.
        if card_id is None:
            stmt = stmt.where(db.ArtifactRow.saved.is_(True))
        rows = (await session.execute(stmt)).scalars().all()
        entries = [r.to_entry() for r in rows]
    if card_id is not None:
        entries = [e for e in entries if card_id in e.source_card_ids]
    return entries[offset : offset + limit]


@router.get("/{artifact_id}", response_model=CatalogDetail)
async def get_catalog_entry(artifact_id: str) -> CatalogDetail:
    async with db.session() as session:
        row = await session.get(db.ArtifactRow, artifact_id)
        if row is None or not row.saved:
            raise HTTPException(status_code=404, detail="artifact not found")
        entry = row.to_entry()
        return CatalogDetail(entry=entry, source_card_ids=entry.source_card_ids)


@router.post("/{artifact_id}/save", response_model=CatalogEntry)
async def save_catalog_entry(artifact_id: str) -> CatalogEntry:
    """Add a referenced artifact to the catalog tab (long-press to save)."""
    async with db.session() as session:
        row = await db.set_artifact_saved(session, artifact_id, True)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        return row.to_entry()


@router.post("/{artifact_id}/fetch-info", response_model=CatalogEntry)
async def fetch_catalog_info(artifact_id: str) -> CatalogEntry:
    """Generate + persist an LLM detail for the artifact (Fetch info button)."""
    async with db.session() as session:
        row = await session.get(db.ArtifactRow, artifact_id)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        type_ = ArtifactType(row.type) if row.type else ArtifactType.OTHER
        desc = await llm_catalog.describe_async(
            row.title, type_, row.creator, row.year
        )
        if not desc:
            raise HTTPException(
                status_code=502, detail="could not generate details right now"
            )
        row = await db.set_artifact_description(session, artifact_id, desc)
        return row.to_entry()


@router.delete("/{artifact_id}")
async def delete_catalog_entry(artifact_id: str) -> dict:
    """Remove an item from the catalog. Soft by default: the row stays so it still
    backs per-card references — it just leaves the catalog tab (saved=False)."""
    async with db.session() as session:
        row = await db.set_artifact_saved(session, artifact_id, False)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        await session.commit()
    return {"removed": artifact_id}
