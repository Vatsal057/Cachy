"""Catalog endpoints (docs/12): the aggregated, deduplicated view of every
artifact referenced across all cards. Read-mostly; entries are created by the
worker, not by clients."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.auth import OwnerDep
from app.api.graph import invalidate_graph_cache
from app.models.artifact import ArtifactType, CatalogEntry
from app.services import llm_catalog
from app.store import db

router = APIRouter(prefix="/catalog", tags=["catalog"])


class CatalogDetail(BaseModel):
    entry: CatalogEntry
    source_card_ids: list[str]


@router.get("", response_model=list[CatalogEntry])
async def list_catalog(
    owner_id: OwnerDep,
    type: ArtifactType | None = None,
    card_id: str | None = None,
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
) -> list[CatalogEntry]:
    async with db.session() as session:
        stmt = select(db.ArtifactRow).order_by(db.ArtifactRow.created_at.desc())
        if type is not None:
            stmt = stmt.where(db.ArtifactRow.type == type.value)
        rows = (await session.execute(stmt)).scalars().all()
        owner_cards = set(
            (await session.execute(
                select(db.CardRow.id).where(db.CardRow.owner_id == owner_id)
            )).scalars().all()
        )
        saved_ids = await db.owner_saved_artifact_ids(session, owner_id)
        entries: list[CatalogEntry] = []
        for r in rows:
            source = set(r.source_card_ids or [])
            if not (source & owner_cards):
                continue  # not the caller's artifact
            if card_id is None and r.id not in saved_ids:
                continue  # catalog tab shows only what this owner saved
            if card_id is not None and card_id not in source:
                continue  # reference view for a specific card
            entry = r.to_entry()
            entry.saved = r.id in saved_ids
            entries.append(entry)
    return entries[offset : offset + limit]


@router.get("/{artifact_id}", response_model=CatalogDetail)
async def get_catalog_entry(artifact_id: str, owner_id: OwnerDep) -> CatalogDetail:
    async with db.session() as session:
        row = await session.get(db.ArtifactRow, artifact_id)
        # Membership implies ownership (it's only created after an ownership check),
        # and the detail view is for catalog items — so gate on the saved membership.
        if row is None or not await db.is_artifact_saved_by(
            session, artifact_id, owner_id
        ):
            raise HTTPException(status_code=404, detail="artifact not found")
        entry = row.to_entry()
        entry.saved = True
        return CatalogDetail(entry=entry, source_card_ids=entry.source_card_ids)


@router.post("/{artifact_id}/save", response_model=CatalogEntry)
async def save_catalog_entry(artifact_id: str, owner_id: OwnerDep) -> CatalogEntry:
    """Add a referenced artifact to the catalog tab (long-press to save)."""
    async with db.session() as session:
        row = await db.set_artifact_saved(session, artifact_id, True, owner_id=owner_id)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        invalidate_graph_cache()
        entry = row.to_entry()
        entry.saved = True
        return entry


@router.post("/{artifact_id}/fetch-info", response_model=CatalogEntry)
async def fetch_catalog_info(artifact_id: str, owner_id: OwnerDep) -> CatalogEntry:
    """Generate + persist an LLM detail for the artifact (Fetch info button)."""
    async with db.session() as session:
        row = await session.get(db.ArtifactRow, artifact_id)
        if row is None or not await db.owner_owns_any_card(
            session, owner_id, row.source_card_ids or []
        ):
            raise HTTPException(status_code=404, detail="artifact not found")
        type_ = ArtifactType(row.type) if row.type else ArtifactType.OTHER
        desc = await llm_catalog.describe_async(
            row.title, type_, row.creator, row.year
        )
        if not desc:
            raise HTTPException(
                status_code=502, detail="could not generate details right now"
            )
        row = await db.set_artifact_description(
            session, artifact_id, desc, owner_id=owner_id
        )
        entry = row.to_entry()
        entry.saved = await db.is_artifact_saved_by(session, artifact_id, owner_id)
        return entry


@router.delete("/{artifact_id}")
async def delete_catalog_entry(artifact_id: str, owner_id: OwnerDep) -> dict:
    """Remove an item from the catalog. Soft by default: the row stays so it still
    backs per-card references — it just leaves the catalog tab (saved=False)."""
    async with db.session() as session:
        row = await db.set_artifact_saved(session, artifact_id, False, owner_id=owner_id)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        await session.commit()
    invalidate_graph_cache()
    return {"removed": artifact_id}
