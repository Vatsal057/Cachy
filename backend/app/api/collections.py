"""Collections API: folder management for the card library."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel

from app.auth import OwnerDep
from app.store import db

router = APIRouter(prefix="/collections", tags=["collections"])


class CollectionOut(BaseModel):
    id: str
    name: str
    system_type: str | None
    is_custom: bool
    card_count: int
    created_at: str


class CreateCollectionRequest(BaseModel):
    name: str


class RenameCollectionRequest(BaseModel):
    name: str


class MoveCardRequest(BaseModel):
    collection_id: str | None  # None = remove from all collections


def _out(row: db.CollectionRow, count: int) -> CollectionOut:
    return CollectionOut(
        id=row.id,
        name=row.name,
        system_type=row.system_type,
        is_custom=row.is_custom,
        card_count=count,
        created_at=(row.created_at or db._utcnow()).isoformat(),
    )


@router.get("", response_model=list[CollectionOut])
async def list_collections(
    owner_id: OwnerDep,
) -> list[CollectionOut]:
    async with db.session() as session:
        pairs = await db.list_collections(session, owner_id=owner_id)
        return [_out(row, count) for row, count in pairs]


@router.post("", response_model=CollectionOut, status_code=201)
async def create_collection(
    req: CreateCollectionRequest,
    owner_id: OwnerDep,
) -> CollectionOut:
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="name is required")
    async with db.session() as session:
        row = await db.create_custom_collection(session, name=name, owner_id=owner_id)
        return _out(row, 0)


@router.patch("/{collection_id}", response_model=CollectionOut)
async def rename_collection(
    collection_id: str, req: RenameCollectionRequest
) -> CollectionOut:
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="name is required")
    async with db.session() as session:
        row = await db.rename_collection(session, collection_id, name)
        if row is None:
            raise HTTPException(status_code=404, detail="collection not found")
        pairs = await db.list_collections(session, owner_id=row.owner_id)
        count = next((c for r, c in pairs if r.id == collection_id), 0)
        return _out(row, count)


@router.delete("/{collection_id}", response_class=Response, status_code=204)
async def delete_collection(collection_id: str) -> Response:
    async with db.session() as session:
        ok = await db.delete_collection(session, collection_id)
        if not ok:
            raise HTTPException(
                status_code=404,
                detail="collection not found or is a system collection",
            )
    return Response(status_code=204)


@router.post("/cards/{card_id}/move", response_model=dict)
async def move_card(card_id: str, req: MoveCardRequest) -> dict:
    async with db.session() as session:
        row = await db.move_card_to_collection(session, card_id, req.collection_id)
        if row is None:
            raise HTTPException(status_code=404, detail="card not found")
        return {"card_id": card_id, "collection_id": row.collection_id}
