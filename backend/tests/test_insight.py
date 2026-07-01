"""Insight validation (docs/14): the gated deep-analysis pass never trusts the
model. These cover the quiz parsing + the empty-layer gate."""

from __future__ import annotations

import json

from app.pipeline import insight


def _raw(**payload) -> str:
    return json.dumps(payload)


def test_quiz_parsed_and_bounds_checked():
    raw = _raw(
        rabbit_hole={"questions": ["Why does it compound?"]},
        quiz=[
            {
                "question": "What is compound interest?",
                "options": ["Interest on interest", "A flat fee", "A tax"],
                "answer_index": 0,
                "explanation": "It accrues on principal plus prior interest.",
            }
        ],
    )
    result = insight._validate(raw)
    assert result is not None
    assert len(result.quiz) == 1
    q = result.quiz[0]
    assert q.answer_index == 0
    assert len(q.options) == 3


def test_malformed_quiz_questions_are_dropped():
    raw = _raw(
        quiz=[
            {"question": "no options", "options": [], "answer_index": 0},  # too few
            {"question": "oob", "options": ["a", "b"], "answer_index": 5},  # bad index
            {"question": "", "options": ["a", "b"], "answer_index": 0},  # empty stem
            {  # the one valid question
                "question": "Pick a fruit",
                "options": ["Apple", "Rock"],
                "answer_index": 0,
                "explanation": "Apple is a fruit.",
            },
        ],
    )
    result = insight._validate(raw)
    assert result is not None
    assert [q.question for q in result.quiz] == ["Pick a fruit"]


def test_quiz_capped():
    many = [
        {"question": f"q{i}", "options": ["a", "b"], "answer_index": 0}
        for i in range(10)
    ]
    result = insight._validate(_raw(quiz=many))
    assert result is not None
    assert len(result.quiz) == insight._MAX["quiz"]


def test_quiz_only_still_produces_layer():
    """A card with just a quiz (no rabbit hole / research) still yields a layer."""
    raw = _raw(
        quiz=[{"question": "q", "options": ["a", "b"], "answer_index": 1}]
    )
    result = insight._validate(raw)
    assert result is not None
    assert result.rabbit_hole.is_empty()
    assert result.quiz


def test_empty_everything_yields_no_layer():
    result = insight._validate(_raw(rabbit_hole={}, quiz=[], deep_research_prompt=""))
    assert result is None


def test_topic_map_is_ignored_now():
    """Legacy topic_map in the model output must not resurrect a layer on its own."""
    result = insight._validate(
        _raw(topic_map={"center": "x", "nodes": ["a", "b"]}, quiz=[], rabbit_hole={})
    )
    assert result is None


def test_quiz_serializes_as_a_bare_list():
    """The client + feed consume `quiz` as a plain list — Insight must serialize it
    that way, not as a wrapped {"questions": [...]} object."""
    from app.models.card import Insight

    ins = Insight(**{"quiz": [{"question": "q", "options": ["a", "b"], "answer_index": 0}]})
    dumped = ins.model_dump()
    assert isinstance(dumped["quiz"], list)
    assert dumped["quiz"][0]["question"] == "q"


def test_legacy_wrapped_quiz_is_coerced():
    """Rows stored under the old {"questions": [...]} shape still load without error."""
    from app.models.card import Insight

    ins = Insight(**{"quiz": {"questions": [
        {"question": "q", "options": ["a", "b"], "answer_index": 1}
    ]}})
    assert isinstance(ins.model_dump()["quiz"], list)
    assert len(ins.quiz) == 1
