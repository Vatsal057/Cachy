"""Multi-entity knowledge graph: cards + catalog items as nodes, three edge types.

Cards are connected by semantic similarity (cosine over embeddings, boosted by
shared tags). Catalog items (artifacts saved to the user's catalog) are connected
to the cards that reference them via hard "reference" edges. The graph also
includes pure "tag" edges between cards that share tags but fall below the
semantic threshold.

Layout is computed CLIENT-SIDE via a live Obsidian-style force-directed physics
simulation (repulsion + spring + center + damping). The server only provides the
graph topology (nodes, edges) and cluster metadata. Community detection via label
propagation assigns each node a cluster_id with an auto-generated label.

Results are cached in-memory keyed by a fingerprint of the underlying data
(card count + latest updated_at + artifact count). The cache invalidates
automatically when cards or artifacts change.

Pure-Python, no external graph library (CLAUDE.md free-first). Degrades
gracefully: cards without embeddings have no similarity edges but still appear
as nodes; if no artifacts exist the graph is card-only."""

from __future__ import annotations

import hashlib
import logging
import math
import random
from typing import Literal

from fastapi import APIRouter, Header, Query
from pydantic import BaseModel
from sqlalchemy import func, select
from typing import Annotated

from app.models.card import CardState
from app.services import embeddings
from app.store import db
from app.store import media as media_store

log = logging.getLogger("api.graph")

router = APIRouter(prefix="/graph", tags=["graph"])

# --- Tuning constants ------------------------------------------------------ #

_TAG_BOOST = 0.05
_TAG_BOOST_CAP = 0.15

# Label propagation max iterations.
_LP_MAX_ITERS = 30

_GENERIC_TAGS = {
    "video", "videos", "reel", "reels", "instagram", "tiktok", "youtube",
    "short", "shorts", "clip", "clips", "post", "posts", "other", "general",
    "untitled", "article", "content", "media", "watch",
}



# --- Schemas ---------------------------------------------------------------- #


class GraphNode(BaseModel):
    id: str
    label: str
    node_type: Literal["card", "catalog", "folder", "concept"]
    content_type: str  # e.g. "recipe", "book", "product", "custom", "concept"
    thumbnail: str | None = None
    tags: list[str] = []
    degree: int = 0
    cluster_id: int = -1


class GraphEdge(BaseModel):
    source: str
    target: str
    weight: float
    kind: Literal["semantic", "reference", "tag", "membership", "concept_ref"]
    shared_topics: list[str] = []



class GraphCluster(BaseModel):
    id: int
    label: str
    count: int


class GraphResponse(BaseModel):
    nodes: list[GraphNode]
    edges: list[GraphEdge]
    clusters: list[GraphCluster]


# --- In-memory cache -------------------------------------------------------- #


class _GraphCache:
    """Per-owner fingerprint cache. Keyed by owner_id (empty string = no auth)."""

    def __init__(self) -> None:
        self._store: dict[str, tuple[str, GraphResponse]] = {}

    def get(self, owner_id: str | None, fingerprint: str) -> GraphResponse | None:
        entry = self._store.get(owner_id or "")
        if entry is not None and entry[0] == fingerprint:
            return entry[1]
        return None

    def set(self, owner_id: str | None, fingerprint: str, response: GraphResponse) -> None:
        self._store[owner_id or ""] = (fingerprint, response)

    def invalidate(self) -> None:
        self._store.clear()


_cache = _GraphCache()


async def _data_fingerprint(owner_id: str | None) -> str:
    """Hash of card/artifact counts + latest timestamps, scoped to owner."""
    async with db.session() as session:
        card_stmt = select(func.count(), func.max(db.CardRow.updated_at)).where(
            db.CardRow.state == CardState.READY.value
        )
        if owner_id is not None:
            card_stmt = card_stmt.where(db.CardRow.owner_id == owner_id)
        card_agg = (await session.execute(card_stmt)).one()
        art_agg = (
            await session.execute(
                select(func.count(), func.max(db.ArtifactRow.updated_at)).where(
                    db.ArtifactRow.saved.is_(True)
                )
            )
        ).one()
        col_count = (
            await session.execute(select(func.count(db.CollectionRow.id)))
        ).scalar() or 0
        concept_count = (
            await session.execute(select(func.count(db.ConceptRow.id)))
        ).scalar() or 0
    raw = f"{owner_id}:{card_agg[0]}:{card_agg[1]}:{art_agg[0]}:{art_agg[1]}:{col_count}:{concept_count}"
    return hashlib.md5(raw.encode()).hexdigest()


def invalidate_graph_cache() -> None:
    """Call from card/artifact mutation endpoints to bust the cache."""
    _cache.invalidate()


# --- Similarity ------------------------------------------------------------- #


def _pair_weight(
    a_vec: list | None, b_vec: list | None, a_tags: set[str], b_tags: set[str]
) -> float:
    """Cosine over embeddings + small shared-tag boost. Returns 0 when neither
    signal is present."""
    base = 0.0
    if a_vec and b_vec:
        base = embeddings.cosine(a_vec, b_vec)
    meaningful_a = a_tags - _GENERIC_TAGS
    meaningful_b = b_tags - _GENERIC_TAGS
    shared = len(meaningful_a & meaningful_b)
    boost = min(shared * _TAG_BOOST, _TAG_BOOST_CAP)
    return base + boost


def _extract_shared_topics(
    node_a: GraphNode | None,
    node_b: GraphNode | None,
    tags_a: set[str],
    tags_b: set[str],
    kind: str,
) -> list[str]:
    if kind == "reference":
        return ["Saved in Catalog"]
    if kind == "concept_ref":
        if node_a and node_a.node_type == "concept":
            return [node_a.label]
        if node_b and node_b.node_type == "concept":
            return [node_b.label]
        return ["Shared concept"]

    # For semantic or tag edges:
    meaningful_shared = sorted((tags_a & tags_b) - _GENERIC_TAGS)
    if meaningful_shared:
        return meaningful_shared[:4]

    # Fallback: find overlapping meaningful words from labels
    if node_a and node_b:
        words_a = {w.lower().strip(".,!?\"'()[]{}") for w in node_a.label.split()}
        words_b = {w.lower().strip(".,!?\"'()[]{}") for w in node_b.label.split()}
        stopwords = _GENERIC_TAGS | {
            "about", "with", "from", "that", "this", "have", "will", "what", "how",
            "why", "when", "where", "into", "over", "under", "more", "most", "some",
            "their", "there", "then", "than", "make", "made", "like", "just", "best",
            "and", "for", "the", "are", "was", "were", "been", "being", "your",
        }
        overlap = sorted({w for w in words_a & words_b if len(w) >= 4 and w not in stopwords})
        if overlap:
            return overlap[:4]

    return ["Similar content"]



# --- Label propagation clustering ------------------------------------------- #


def _label_propagation(
    ids: list[str], adj: dict[str, list[tuple[str, float]]]
) -> dict[str, int]:
    """Weighted label propagation. Each node starts with its own label; on each
    iteration every node adopts the label with the highest summed edge weight
    among its neighbours. Converges when no label changes or after _LP_MAX_ITERS.
    Returns a mapping of node_id → cluster_id (int)."""
    labels: dict[str, str] = {nid: nid for nid in ids}
    order = list(ids)

    for _ in range(_LP_MAX_ITERS):
        random.shuffle(order)
        changed = False
        for nid in order:
            neighbours = adj.get(nid, [])
            if not neighbours:
                continue
            # Sum weights per neighbour label.
            scores: dict[str, float] = {}
            for other, w in neighbours:
                lbl = labels[other]
                scores[lbl] = scores.get(lbl, 0.0) + w
            best = max(scores, key=lambda k: scores[k])
            if best != labels[nid]:
                labels[nid] = best
                changed = True
        if not changed:
            break

    # Renumber labels to consecutive ints starting at 0.
    unique = sorted(set(labels.values()))
    remap = {lbl: idx for idx, lbl in enumerate(unique)}
    return {nid: remap[lbl] for nid, lbl in labels.items()}






def _cluster_labels(
    nodes: list[GraphNode], clusters: dict[str, int]
) -> list[GraphCluster]:
    """Generate a label per cluster from the most common content_type."""
    cluster_types: dict[int, dict[str, int]] = {}
    cluster_counts: dict[int, int] = {}
    for node in nodes:
        cid = clusters.get(node.id, -1)
        if cid < 0:
            continue
        cluster_counts[cid] = cluster_counts.get(cid, 0) + 1
        type_map = cluster_types.setdefault(cid, {})
        type_map[node.content_type] = type_map.get(node.content_type, 0) + 1

    _NICE_NAMES: dict[str, str] = {
        "recipe": "Recipes",
        "workout": "Fitness",
        "tutorial": "Tutorials",
        "tip": "Tips",
        "product_list": "Products",
        "travel": "Travel",
        "news_explainer": "News",
        "other": "General",
        "book": "Books",
        "movie": "Movies",
        "tv_show": "TV Shows",
        "podcast": "Podcasts",
        "music": "Music",
        "product": "Products",
        "place": "Places",
        "app": "Apps",
        "concept": "Concepts",
    }

    out: list[GraphCluster] = []
    for cid in sorted(cluster_types):
        best_type = max(cluster_types[cid], key=lambda t: cluster_types[cid][t])
        label = _NICE_NAMES.get(best_type, best_type.replace("_", " ").title())
        # Dedupe labels by appending count for collisions.
        existing_labels = [c.label for c in out]
        if label in existing_labels:
            label = f"{label} #{sum(1 for l in existing_labels if l.startswith(label)) + 1}"
        out.append(
            GraphCluster(id=cid, label=label, count=cluster_counts.get(cid, 0))
        )
    return out


# --- Endpoint --------------------------------------------------------------- #


@router.get("", response_model=GraphResponse)
async def get_graph(
    threshold: float = Query(0.62, ge=0.0, le=1.0),
    top_k: int = Query(2, ge=1, le=12),
    x_owner_id: Annotated[str | None, Header()] = None,
) -> GraphResponse:
    """Build the multi-entity card + catalog similarity graph. Cached until the
    underlying data changes (card/artifact create/update/delete)."""

    fingerprint = await _data_fingerprint(x_owner_id)
    cached = _cache.get(x_owner_id, fingerprint)
    if cached is not None:
        log.debug("graph cache hit (%s)", fingerprint[:8])
        return cached

    log.debug("graph cache miss — rebuilding (%s)", fingerprint[:8])

    # ---- Fetch data -------------------------------------------------------- #

    async with db.session() as session:
        card_stmt = select(db.CardRow).where(db.CardRow.state == CardState.READY.value)
        if x_owner_id is not None:
            card_stmt = card_stmt.where(db.CardRow.owner_id == x_owner_id)
        card_rows = (await session.execute(card_stmt)).scalars().all()

        user_card_ids = {r.id for r in card_rows}

        all_artifact_rows = (
            await session.execute(
                select(db.ArtifactRow).where(db.ArtifactRow.saved.is_(True))
            )
        ).scalars().all()
        artifact_rows = [
            a for a in all_artifact_rows
            if x_owner_id is None or bool(set(a.source_card_ids or []) & user_card_ids)
        ]

        all_concept_rows = (await session.execute(select(db.ConceptRow))).scalars().all()
        concept_rows = [
            c for c in all_concept_rows
            if len(c.source_card_ids or []) > 1
            and (x_owner_id is None or bool(set(c.source_card_ids or []) & user_card_ids))
        ]

    # ---- Build nodes ------------------------------------------------------- #

    nodes: list[GraphNode] = []
    card_ids: set[str] = set()

    for r in card_rows:
        card_ids.add(r.id)
        nodes.append(
            GraphNode(
                id=r.id,
                label=(r.one_liner or r.caption or "Untitled").strip()[:80],
                node_type="card",
                content_type=r.content_type or "other",
                thumbnail=media_store.to_media_url(r.thumbnail),
                tags=list(r.tags or []),
            )
        )

    for a in artifact_rows:
        nodes.append(
            GraphNode(
                id=a.id,
                label=a.title.strip()[:80],
                node_type="catalog",
                content_type=a.type or "other",
                thumbnail=a.thumbnail,
                tags=[],
            )
        )

    # Folders are NOT nodes — they're navigation, not knowledge links. Cards are
    # already coloured by content_type client-side; system folders map 1:1 to
    # content_type so the grouping comes for free without folder spoke-chains.

    concept_ids: set[str] = set()
    for c in concept_rows:
        concept_ids.add(c.id)
        nodes.append(
            GraphNode(
                id=c.id,
                label=c.name,
                node_type="concept",
                content_type="concept",
                tags=[],
            )
        )

    if not nodes:
        resp = GraphResponse(nodes=[], edges=[], clusters=[])
        _cache.set(x_owner_id, fingerprint, resp)
        return resp

    # ---- Build edges ------------------------------------------------------- #

    vecs = {r.id: (r.embedding or None) for r in card_rows}
    tags = {r.id: set(r.tags or []) for r in card_rows}
    all_ids = [n.id for n in nodes]

    # Adjacency for layout + clustering (weighted).
    adj: dict[str, list[tuple[str, float]]] = {nid: [] for nid in all_ids}

    edges: list[GraphEdge] = []

    # 1) Card-card semantic + tag edges.
    card_id_list = [r.id for r in card_rows]
    candidates: dict[str, list[tuple[float, str]]] = {cid: [] for cid in card_id_list}

    for i in range(len(card_id_list)):
        for j in range(i + 1, len(card_id_list)):
            a, b = card_id_list[i], card_id_list[j]
            w = _pair_weight(vecs[a], vecs[b], tags[a], tags[b])
            if w >= threshold:
                candidates[a].append((w, b))
                candidates[b].append((w, a))

    # Keep each card's top-K neighbours, dedupe to undirected edges.
    kept: set[tuple[str, str]] = set()
    weights: dict[tuple[str, str], float] = {}
    for node_id, neigh in candidates.items():
        neigh.sort(reverse=True)
        for w, other in neigh[:top_k]:
            key = (node_id, other) if node_id < other else (other, node_id)
            kept.add(key)
            weights[key] = round(w, 4)

    nodes_by_id = {n.id: n for n in nodes}

    for (s, t) in kept:
        w = weights[(s, t)]
        # Classify: if weight is purely from tags (no embedding), mark as "tag".
        a_vec, b_vec = vecs.get(s), vecs.get(t)
        has_semantic = bool(a_vec and b_vec and embeddings.cosine(a_vec, b_vec) > 0.1)
        kind: Literal["semantic", "reference", "tag"] = "semantic" if has_semantic else "tag"
        topics = _extract_shared_topics(
            nodes_by_id.get(s), nodes_by_id.get(t), tags.get(s, set()), tags.get(t, set()), kind
        )
        edges.append(GraphEdge(source=s, target=t, weight=w, kind=kind, shared_topics=topics))
        adj[s].append((t, w))
        adj[t].append((s, w))

    # 2) Catalog-card reference edges (hard links from artifact.source_card_ids).
    for a in artifact_rows:
        for card_id in (a.source_card_ids or []):
            if card_id in card_ids:
                topics = _extract_shared_topics(nodes_by_id.get(a.id), nodes_by_id.get(card_id), set(), set(), "reference")
                edges.append(
                    GraphEdge(source=a.id, target=card_id, weight=1.0, kind="reference", shared_topics=topics)
                )
                adj[a.id].append((card_id, 1.0))
                adj[card_id].append((a.id, 1.0))

    # 3) Concept-card reference edges (concept → each source card).
    for c in concept_rows:
        for cid in (c.source_card_ids or []):
            if cid in card_ids:
                topics = _extract_shared_topics(nodes_by_id.get(c.id), nodes_by_id.get(cid), set(), set(), "concept_ref")
                edges.append(
                    GraphEdge(source=c.id, target=cid, weight=0.9, kind="concept_ref", shared_topics=topics)
                )
                adj[c.id].append((cid, 0.9))
                adj[cid].append((c.id, 0.9))

    # ---- Degree ------------------------------------------------------------ #

    degree: dict[str, int] = {n.id: 0 for n in nodes}
    for e in edges:
        degree[e.source] = degree.get(e.source, 0) + 1
        degree[e.target] = degree.get(e.target, 0) + 1
    for n in nodes:
        n.degree = degree.get(n.id, 0)

    # ---- Clustering -------------------------------------------------------- #

    cluster_map = _label_propagation(all_ids, adj)
    for n in nodes:
        n.cluster_id = cluster_map.get(n.id, -1)

    # ---- Cluster metadata -------------------------------------------------- #

    cluster_meta = _cluster_labels(nodes, cluster_map)

    resp = GraphResponse(nodes=nodes, edges=edges, clusters=cluster_meta)
    _cache.set(x_owner_id, fingerprint, resp)
    return resp
