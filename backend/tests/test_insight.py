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
    assert len(result.quiz.questions) == 1
    q = result.quiz.questions[0]
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
    assert [q.question for q in result.quiz.questions] == ["Pick a fruit"]


def test_quiz_capped():
    many = [
        {"question": f"q{i}", "options": ["a", "b"], "answer_index": 0}
        for i in range(10)
    ]
    result = insight._validate(_raw(quiz=many))
    assert result is not None
    assert len(result.quiz.questions) == insight._MAX["quiz"]


def test_quiz_only_still_produces_layer():
    """A card with just a quiz (no rabbit hole / research) still yields a layer."""
    raw = _raw(
        quiz=[{"question": "q", "options": ["a", "b"], "answer_index": 1}]
    )
    result = insight._validate(raw)
    assert result is not None
    assert result.rabbit_hole.is_empty()
    assert not result.quiz.is_empty()


def test_empty_everything_yields_no_layer():
    result = insight._validate(_raw(rabbit_hole={}, quiz=[], deep_research_prompt=""))
    assert result is None


def test_topic_map_is_ignored_now():
    """Legacy topic_map in the model output must not resurrect a layer on its own."""
    result = insight._validate(
        _raw(topic_map={"center": "x", "nodes": ["a", "b"]}, quiz=[], rabbit_hole={})
    )
    assert result is None
