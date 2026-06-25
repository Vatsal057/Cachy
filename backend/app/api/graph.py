"""Knowledge graph (Obsidian-style): cards are nodes, similarity makes edges.

Read-only. An edge connects two READY cards when their semantic embeddings are
close (cosine) — boosted by shared auto-tags. To keep the graph readable instead
of a hairball, each node keeps only its top-K strongest neighbours above a
threshold; a card with nothing similar enough stays an isolated node (exactly the
"distinct notes float alone until something connects" behaviour).

Pure-Python over the small card corpus (same approach as search, no vector DB).
Degrades gracefully: cards without embeddings simply have no similarity edges
(they still appear as nodes), so the screen works even with no HF key."""

from __future__ import annotations

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.models.card import CardState
from app.services import embeddings
from app.store import db

router = APIRouter(prefix="/graph", tags=["graph"])

# Shared tags nudge two cards together even when embeddings are lukewarm; this is
# the cosine added per overlapping tag, capped so tags never dominate meaning.
_TAG_BOOST = 0.05
_TAG_BOOST_CAP = 0.15


class GraphNode(BaseModel):
    id: str
    label: str
    content_type: str
    thumbnail: str | None = None
    tags: list[str] = []
    degree: int = 0  # number of edges — drives node size on the client


class GraphEdge(BaseModel):
    source: str
    target: str
    weight: float  # similarity in (0, 1], drives edge opacity/strength


class GraphResponse(BaseModel):
    nodes: list[GraphNode]
    edges: list[GraphEdge]


def _pair_weight(
    a_vec: list | None, b_vec: list | None, a_tags: set[str], b_tags: set[str]
) -> float:
    """Similarity for one card pair: cosine over embeddings + a small shared-tag
    boost. Returns 0 when neither signal is present."""
    base = 0.0
    if a_vec and b_vec:
        base = embeddings.cosine(a_vec, b_vec)
    shared = len(a_tags & b_tags)
    boost = min(shared * _TAG_BOOST, _TAG_BOOST_CAP)
    return base + boost


@router.get("", response_model=GraphResponse)
async def get_graph(
    threshold: float = Query(0.55, ge=0.0, le=1.0),
    top_k: int = Query(4, ge=1, le=12),
) -> GraphResponse:
    """Build the card similarity graph. `threshold` is the minimum weight for an
    edge; `top_k` caps each node's strongest neighbours to keep it readable."""
    async with db.session() as session:
        rows = (
            await session.execute(
                select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
            )
        ).scalars().all()

    nodes = [
        GraphNode(
            id=r.id,
            label=(r.one_liner or r.caption or "Untitled").strip()[:80],
            content_type=r.content_type or "other",
            thumbnail=r.thumbnail,
            tags=list(r.tags or []),
        )
        for r in rows
    ]
    vecs = {r.id: (r.embedding or None) for r in rows}
    tags = {r.id: set(r.tags or []) for r in rows}

    # Candidate edges: every pair scored once, kept only above the threshold.
    # O(n^2) is fine for the small corpus; mirrors the search service's approach.
    candidates: dict[str, list[tuple[float, str]]] = {n.id: [] for n in nodes}
    ids = [n.id for n in nodes]
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = ids[i], ids[j]
            w = _pair_weight(vecs[a], vecs[b], tags[a], tags[b])
            if w >= threshold:
                candidates[a].append((w, b))
                candidates[b].append((w, a))

    # Keep each node's top-K neighbours, then dedupe to undirected edges. An edge
    # survives if it is in either endpoint's top-K (mutual-friendly).
    kept: set[tuple[str, str]] = set()
    weights: dict[tuple[str, str], float] = {}
    for node_id, neigh in candidates.items():
        neigh.sort(reverse=True)  # strongest first
        for w, other in neigh[:top_k]:
            key = (node_id, other) if node_id < other else (other, node_id)
            kept.add(key)
            weights[key] = round(w, 4)

    edges = [
        GraphEdge(source=s, target=t, weight=weights[(s, t)]) for (s, t) in kept
    ]

    degree: dict[str, int] = {n.id: 0 for n in nodes}
    for e in edges:
        degree[e.source] += 1
        degree[e.target] += 1
    for n in nodes:
        n.degree = degree[n.id]

    return GraphResponse(nodes=nodes, edges=edges)
