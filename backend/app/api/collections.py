"""Collection endpoints (docs/09): user-created groups of cards. A collection is
just a named list of card ids — no block-schema change. Client-created, unlike
the worker-populated catalog."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlalchemy import delete, select

from app.models.card import Card
from app.models.collection import Collection
from app.store import db

router = APIRouter(prefix="/collections", tags=["collections"])


class CreateCollectionRequest(BaseModel):
    name: str


class AddCardRequest(BaseModel):
    card_id: str


class CollectionDetail(BaseModel):
    collection: Collection
    cards: list[Card]


@router.post("", response_model=Collection)
async def create_collection(req: CreateCollectionRequest) -> Collection:
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="name is required")
    async with db.session() as session:
        row = db.CollectionRow(name=name, card_ids=[])
        session.add(row)
        await session.commit()
        await session.refresh(row)
        return row.to_collection()


@router.get("", response_model=list[Collection])
async def list_collections() -> list[Collection]:
    async with db.session() as session:
        stmt = select(db.CollectionRow).order_by(db.CollectionRow.created_at.desc())
        rows = (await session.execute(stmt)).scalars().all()
        return [r.to_collection() for r in rows]


@router.get("/{collection_id}", response_model=CollectionDetail)
async def get_collection(collection_id: str) -> CollectionDetail:
    async with db.session() as session:
        row = await session.get(db.CollectionRow, collection_id)
        if row is None:
            raise HTTPException(status_code=404, detail="collection not found")
        collection = row.to_collection()
        # Resolve member cards, preserving membership order; skip any deleted ids.
        cards: list[Card] = []
        for cid in collection.card_ids:
            card_row = await db.get_card_row(session, cid)
            if card_row is not None:
                cards.append(card_row.to_card())
        return CollectionDetail(collection=collection, cards=cards)


@router.delete("/{collection_id}")
async def delete_collection(collection_id: str) -> dict:
    async with db.session() as session:
        row = await session.get(db.CollectionRow, collection_id)
        if row is None:
            raise HTTPException(status_code=404, detail="collection not found")
        await session.execute(
            delete(db.CollectionRow).where(db.CollectionRow.id == collection_id)
        )
        await session.commit()
    return {"deleted": collection_id}


@router.post("/{collection_id}/cards", response_model=Collection)
async def add_card(collection_id: str, req: AddCardRequest) -> Collection:
    async with db.session() as session:
        row = await session.get(db.CollectionRow, collection_id)
        if row is None:
            raise HTTPException(status_code=404, detail="collection not found")
        if req.card_id not in (row.card_ids or []):
            row.card_ids = [*(row.card_ids or []), req.card_id]
        await session.commit()
        await session.refresh(row)
        return row.to_collection()


@router.delete("/{collection_id}/cards/{card_id}", response_model=Collection)
async def remove_card(collection_id: str, card_id: str) -> Collection:
    async with db.session() as session:
        row = await session.get(db.CollectionRow, collection_id)
        if row is None:
            raise HTTPException(status_code=404, detail="collection not found")
        row.card_ids = [c for c in (row.card_ids or []) if c != card_id]
        await session.commit()
        await session.refresh(row)
        return row.to_collection()
