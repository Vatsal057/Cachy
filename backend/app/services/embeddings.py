"""Text embeddings for semantic search (docs/09).

Free-first: reuses the existing HuggingFace Inference key via
feature-extraction — no extra service, no local model, no torch. Any miss
(no key, network error, bad shape) returns None, and the caller degrades to
full-text search. Cosine similarity is computed in pure Python over the small
card corpus — no vector DB, no numpy.
"""

from __future__ import annotations

import logging
import math

from app.config import get_settings

log = logging.getLogger("services.embeddings")


def embeddings_enabled() -> bool:
    settings = get_settings()
    return bool(settings.hf_api_key.strip())


def embed(text: str) -> list[float] | None:
    """Embed text via HF feature-extraction. None on any failure (graceful)."""
    text = (text or "").strip()
    if not text or not embeddings_enabled():
        return None
    settings = get_settings()
    try:
        from huggingface_hub import InferenceClient

        client = InferenceClient(api_key=settings.hf_api_key)
        # Cap length: embedding models truncate anyway, and it keeps calls cheap.
        out = client.feature_extraction(text[:4000], model=settings.embedding_model)
        return _flatten(out)
    except Exception as e:  # noqa: BLE001 — semantic search is best-effort
        log.warning("embedding call failed: %s", e)
        return None


def _flatten(out) -> list[float] | None:
    """Normalise HF feature_extraction output to a flat float vector.

    Returns either a 1-D vector or a 2-D token matrix (which we mean-pool)."""
    vec = _to_list(out)
    if not vec:
        return None
    # Token matrix [tokens][dims] -> mean-pool to a single sentence vector.
    if isinstance(vec[0], list):
        rows = [r for r in vec if isinstance(r, list) and r]
        if not rows:
            return None
        dims = len(rows[0])
        pooled = [0.0] * dims
        for r in rows:
            for i in range(dims):
                pooled[i] += float(r[i])
        return [v / len(rows) for v in pooled]
    return [float(v) for v in vec]


def _to_list(out):
    """Coerce numpy arrays / nested sequences to plain Python lists."""
    if hasattr(out, "tolist"):
        return out.tolist()
    if isinstance(out, list):
        return out
    return None


def cosine(a: list[float], b: list[float]) -> float:
    """Cosine similarity of two equal-length vectors. 0.0 on bad input."""
    if not a or not b or len(a) != len(b):
        return 0.0
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (na * nb)
