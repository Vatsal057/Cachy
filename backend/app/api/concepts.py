"""Concept endpoints: the aggregated, deduplicated view of every evergreen
idea extracted across all cards. Read-mostly; entries are created by the worker.
Mirrors api/catalog.py."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.auth import OwnerDep
from app.api.graph import invalidate_graph_cache
from app.models.concept import ConceptEntry
from app.services import llm_concept
from app.store import db

router = APIRouter(prefix="/concepts", tags=["concepts"])


class ConceptDetail(BaseModel):
    entry: ConceptEntry
    related: list[ConceptEntry]


@router.get("", response_model=list[ConceptEntry])
async def list_concepts(
    owner_id: OwnerDep,
    card_id: str | None = None,
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
) -> list[ConceptEntry]:
    async with db.session() as session:
        stmt = select(db.ConceptRow).order_by(db.ConceptRow.created_at.desc())
        rows = (await session.execute(stmt)).scalars().all()
        entries = [r.to_entry() for r in rows]
        owner_cards = set(
            (await session.execute(
                select(db.CardRow.id).where(db.CardRow.owner_id == owner_id)
            )).scalars().all()
        )
        entries = [e for e in entries if bool(set(e.source_card_ids) & owner_cards)]
    if card_id is not None:
        entries = [e for e in entries if card_id in e.source_card_ids]
    else:
        entries = [e for e in entries if len(e.source_card_ids) > 1]
    return entries[offset : offset + limit]


@router.get("/{concept_id}", response_model=ConceptDetail)
async def get_concept(
    concept_id: str,
    owner_id: OwnerDep,
) -> ConceptDetail:
    async with db.session() as session:
        row = await session.get(db.ConceptRow, concept_id)
        if row is None:
            raise HTTPException(status_code=404, detail="concept not found")
        entry = row.to_entry()
        mine = set(entry.source_card_ids)
        owner_cards = set(
            (await session.execute(
                select(db.CardRow.id).where(db.CardRow.owner_id == owner_id)
            )).scalars().all()
        )
        all_rows = (await session.execute(select(db.ConceptRow))).scalars().all()
        related = [
            r.to_entry()
            for r in all_rows
            if r.id != concept_id
            and len(r.source_card_ids or []) > 1
            and bool(set(r.source_card_ids or []) & mine)
            and bool(set(r.source_card_ids or []) & owner_cards)
        ]
    return ConceptDetail(entry=entry, related=related)


@router.post("/{concept_id}/define", response_model=ConceptEntry)
async def define_concept(concept_id: str) -> ConceptEntry:
    """Generate + persist an LLM definition for a concept."""
    async with db.session() as session:
        row = await session.get(db.ConceptRow, concept_id)
        if row is None:
            raise HTTPException(status_code=404, detail="concept not found")
        definition = await llm_concept.define_async(row.name)
        if not definition:
            raise HTTPException(
                status_code=503, detail="could not generate definition right now"
            )
        row = await db.set_concept_definition(session, concept_id, definition)
    invalidate_graph_cache()
    return row.to_entry()


@router.delete("/{concept_id}")
async def delete_concept(concept_id: str) -> dict:
    async with db.session() as session:
        row = await session.get(db.ConceptRow, concept_id)
        if row is None:
            raise HTTPException(status_code=404, detail="concept not found")
        await session.delete(row)
        await session.commit()
    invalidate_graph_cache()
    return {"removed": concept_id}
