"""Schema contract (docs/04): block union round-trips; validation drops unknown
types and required-field-less blocks."""

from app.models.card import VOCAB
from app.pipeline.structuring import _coerce_blocks


def test_all_vocab_blocks_round_trip():
    raw = [
        {"type": "heading", "text": "Ingredients", "level": 2},
        {"type": "paragraph", "text": "Plain prose."},
        {"type": "bullet_list", "items": ["a", "b"]},
        {"type": "step_list", "steps": [{"text": "Preheat", "checkable": True}]},
        {"type": "key_value", "pairs": [{"key": "Serves", "value": "4"}]},
        {"type": "checklist", "items": [{"text": "Olive oil", "checked": False}]},
        {"type": "callout", "variant": "caveat", "text": "note", "confidence": "low"},
        {"type": "link", "url": "https://x.com", "label": "src"},
    ]
    out = _coerce_blocks(raw)
    assert len(out) == len(raw)
    assert {b["type"] for b in out} <= VOCAB
    assert all("id" in b for b in out)


def test_unknown_type_dropped():
    out = _coerce_blocks([{"type": "video_embed", "url": "x"},
                          {"type": "paragraph", "text": "keep"}])
    assert [b["type"] for b in out] == ["paragraph"]


def test_missing_required_field_dropped():
    # paragraph without text, bullet_list without items -> both dropped
    out = _coerce_blocks([
        {"type": "paragraph"},
        {"type": "bullet_list", "items": []},
        {"type": "heading", "text": "ok"},
    ])
    assert [b["type"] for b in out] == ["heading"]


def test_missing_id_assigned():
    out = _coerce_blocks([{"type": "paragraph", "text": "hi"}])
    assert out[0]["id"]
