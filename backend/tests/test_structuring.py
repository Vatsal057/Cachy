"""Structuring validation + fallback (docs/04). No Gemini key in tests, so the
real call is never made; we exercise validation paths directly and via structure()."""

from app.models.card import ContentType, PrimaryActionKind
from app.pipeline import structuring


def test_no_key_falls_back_to_paragraph():
    sc = structuring.structure(
        bundle="CAPTION:\nTRANSCRIPT: Mix flour and water.\nON-SCREEN TEXT:\nSOURCE: x",
        transcript="Mix flour and water.",
        caption="",
    )
    assert sc.base.one_liner  # always non-empty
    assert sc.base.tldr
    assert any(b["type"] == "paragraph" for b in sc.blocks)


def test_valid_gemini_json_is_accepted():
    raw = (
        '{"base": {"one_liner": "3 ways to cut AWS bill", "tldr": "Cut costs.",'
        ' "content_type": "tip", "type_confidence": 0.8},'
        ' "blocks": [{"type": "bullet_list", "items": ["a", "b"]}]}'
    )
    sc = structuring._validate(raw, bundle="", transcript="", caption="")
    assert sc.base.content_type == ContentType.TIP
    assert sc.base.one_liner == "3 ways to cut AWS bill"
    assert sc.blocks[0]["type"] == "bullet_list"
    assert sc.primary_action.kind == PrimaryActionKind.REMINDER


def test_bad_json_falls_back():
    sc = structuring._validate(
        "not json at all", bundle="", transcript="some words here", caption=""
    )
    assert sc.base.one_liner
    assert any(b["type"] == "paragraph" for b in sc.blocks)


def test_fenced_json_is_stripped():
    raw = '```json\n{"base": {"one_liner": "x", "tldr": "y"}, "blocks": [{"type":"paragraph","text":"z"}]}\n```'
    sc = structuring._validate(raw, bundle="", transcript="", caption="")
    assert sc.base.one_liner == "x"
    assert sc.blocks[0]["text"] == "z"


def test_one_liner_synthesized_when_omitted():
    raw = '{"base": {"content_type": "other"}, "blocks": [{"type":"paragraph","text":"body"}]}'
    sc = structuring._validate(raw, bundle="", transcript="A useful fact. More.", caption="")
    assert sc.base.one_liner
    assert sc.base.tldr


def test_hf_backend_no_key_falls_back():
    # default LLM_BACKEND=huggingface but no HF_API_KEY in tests -> dispatch must not
    # crash and must degrade to the paragraph fallback.
    sc = structuring.structure(
        bundle="TRANSCRIPT: Mix flour and water.",
        transcript="Mix flour and water.",
        caption="",
    )
    assert sc.base.one_liner
    assert any(b["type"] == "paragraph" for b in sc.blocks)


def test_primary_action_mapping():
    raw_recipe = '{"base":{"one_liner":"a","tldr":"b","content_type":"recipe"},"blocks":[{"type":"paragraph","text":"x"}]}'
    sc = structuring._validate(raw_recipe, bundle="", transcript="", caption="")
    assert sc.primary_action.kind == PrimaryActionKind.SHOPPING_LIST


def test_artifacts_extracted_and_validated():
    raw = (
        '{"base":{"one_liner":"5 books","tldr":"reading list","content_type":"tip"},'
        '"blocks":[{"type":"bullet_list","items":["a"]}],'
        '"artifacts":['
        '{"type":"book","title":"Atomic Habits","creator":"James Clear","year":2018},'
        '{"type":"bogus","title":"Dune"},'
        '{"title":""},'
        '"not a dict",'
        '{"type":"book","title":"atomic habits"}]}'  # dup of first (case-insensitive)
    )
    sc = structuring._validate(raw, bundle="", transcript="", caption="")
    titles = [(a.type.value, a.title) for a in sc.artifacts]
    assert ("book", "Atomic Habits") in titles
    assert ("other", "Dune") in titles  # bad type coerced to other
    assert len(sc.artifacts) == 2  # empty-title, non-dict, and dup dropped


def test_artifacts_kept_even_when_blocks_empty():
    raw = '{"base":{"one_liner":"x","tldr":"y"},"blocks":[],"artifacts":[{"type":"movie","title":"Inception"}]}'
    sc = structuring._validate(raw, bundle="", transcript="body text", caption="")
    assert any(b["type"] == "paragraph" for b in sc.blocks)  # fallback body
    assert [a.title for a in sc.artifacts] == ["Inception"]


def test_no_artifacts_is_normal():
    raw = '{"base":{"one_liner":"x","tldr":"y","content_type":"tip"},"blocks":[{"type":"paragraph","text":"z"}]}'
    sc = structuring._validate(raw, bundle="", transcript="", caption="")
    assert sc.artifacts == []


# ---------------------------------------------------------------------------
# _coerce_tags
# ---------------------------------------------------------------------------

def test_tags_coerced_lowercase_deduped():
    from app.pipeline.structuring import _coerce_tags
    result = _coerce_tags(["AWS", "cost-optimization", "AWS", "cloud"])
    assert result == ["aws", "cost-optimization", "cloud"]


def test_tags_non_string_entries_dropped():
    from app.pipeline.structuring import _coerce_tags
    result = _coerce_tags(["valid", 42, None, True, "also-valid"])
    assert result == ["valid", "also-valid"]


def test_tags_capped_at_six():
    from app.pipeline.structuring import _coerce_tags
    result = _coerce_tags([f"tag{i}" for i in range(10)])
    assert len(result) == 6


def test_tags_over_40_chars_dropped():
    from app.pipeline.structuring import _coerce_tags
    long_tag = "a" * 41
    result = _coerce_tags([long_tag, "short"])
    assert result == ["short"]


def test_tags_empty_list_accepted():
    from app.pipeline.structuring import _coerce_tags
    assert _coerce_tags([]) == []


def test_tags_non_list_returns_empty():
    from app.pipeline.structuring import _coerce_tags
    assert _coerce_tags("not-a-list") == []
    assert _coerce_tags(None) == []


def test_tags_present_in_validated_card():
    raw = (
        '{"base":{"one_liner":"x","tldr":"y","content_type":"tip",'
        '"tags":["Python","python","machine learning"]},'
        '"blocks":[{"type":"paragraph","text":"z"}]}'
    )
    sc = structuring._validate(raw, bundle="", transcript="", caption="")
    assert sc.base.tags == ["python", "machine learning"]  # deduped


def test_tags_absent_defaults_to_empty():
    raw = '{"base":{"one_liner":"x","tldr":"y"},"blocks":[{"type":"paragraph","text":"z"}]}'
    sc = structuring._validate(raw, bundle="", transcript="", caption="")
    assert sc.base.tags == []
