"""Catalog endpoints (docs/12): the aggregated, deduplicated view of every
artifact referenced across all cards. Read-mostly; entries are created by the
worker, not by clients."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import delete, select

from app.models.artifact import ArtifactType, CatalogEntry
from app.store import db

router = APIRouter(prefix="/catalog", tags=["catalog"])


class CatalogDetail(BaseModel):
    entry: CatalogEntry
    source_card_ids: list[str]


@router.get("", response_model=list[CatalogEntry])
async def list_catalog(
    type: ArtifactType | None = None,
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
) -> list[CatalogEntry]:
    async with db.session() as session:
        stmt = select(db.ArtifactRow).order_by(db.ArtifactRow.created_at.desc())
        if type is not None:
            stmt = stmt.where(db.ArtifactRow.type == type.value)
        stmt = stmt.limit(limit).offset(offset)
        rows = (await session.execute(stmt)).scalars().all()
        return [r.to_entry() for r in rows]


@router.get("/{artifact_id}", response_model=CatalogDetail)
async def get_catalog_entry(artifact_id: str) -> CatalogDetail:
    async with db.session() as session:
        row = await session.get(db.ArtifactRow, artifact_id)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        entry = row.to_entry()
        return CatalogDetail(entry=entry, source_card_ids=entry.source_card_ids)


@router.delete("/{artifact_id}")
async def delete_catalog_entry(artifact_id: str) -> dict:
    async with db.session() as session:
        row = await session.get(db.ArtifactRow, artifact_id)
        if row is None:
            raise HTTPException(status_code=404, detail="artifact not found")
        await session.execute(
            delete(db.ArtifactRow).where(db.ArtifactRow.id == artifact_id)
        )
        await session.commit()
    return {"deleted": artifact_id}
