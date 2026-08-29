"""Regression tests for the degraded-card title path.

The bug these pin down: a reel whose transcript had no full stops produced a
card where the title, the TL;DR and the body block were the same 120 characters
of raw speech, including a racial slur promoted into the headline.
"""
from __future__ import annotations

import pytest

from app.pipeline import text_hygiene as th

# The transcript that produced the broken card, as Groq Whisper emitted it.
BROKEN = (
    "Skinny nigger dude Oh you call this skinny? At least I'm not fat "
    "You call this fat? You call this fat? You call this fat? HURT"
)


class TestCollapseRepeats:
    def test_collapses_immediate_phrase_repetition(self):
        got = th.collapse_repeats("You call this fat? You call this fat? You call this fat?")
        assert got.lower().count("call this fat") == 1

    def test_leaves_non_adjacent_repetition_alone(self):
        # Legitimate emphasis separated by other content is not a stutter.
        text = "Buy low. Hold the line. Buy low."
        assert th.collapse_repeats(text).count("Buy low") == 2

    def test_no_crash_on_empty(self):
        assert th.collapse_repeats("") == ""
        assert th.collapse_repeats(None) == ""


class TestTruncateWords:
    def test_never_splits_mid_word(self):
        got = th.truncate_words("internationalization considerations apply", 20)
        assert not got.rstrip("\u2026").endswith("interna")
        assert " " not in got[-2:]

    def test_short_text_untouched(self):
        assert th.truncate_words("already short", 70) == "already short"

    def test_single_long_word_still_cut(self):
        got = th.truncate_words("a" * 200, 30)
        assert len(got) <= 31


class TestFirstClause:
    def test_punctuationless_speech_does_not_return_everything(self):
        """The actual defect: split(".")[0] returned the whole transcript."""
        got = th.first_clause(BROKEN, limit=70)
        assert len(got) <= 71, f"title too long: {got!r}"
        assert got != BROKEN

    def test_prefers_a_real_sentence_when_present(self):
        got = th.first_clause("Three ways to fix your sleep. First, wake up earlier.", limit=70)
        assert got == "Three ways to fix your sleep."

    def test_strips_leading_filler(self):
        assert not th.first_clause("Oh you call this skinny?", limit=70).lower().startswith("oh")

    def test_splits_on_clause_when_no_sentence_end(self):
        got = th.first_clause(
            "so I tried the cold plunge for thirty days and it changed my mornings", limit=70)
        assert "and it changed" not in got


class TestSlurGuard:
    def test_detects_slur_in_the_broken_transcript(self):
        assert th.contains_slur(BROKEN) is True

    def test_ordinary_swearing_is_not_a_slur(self):
        # A broad profanity filter would suppress legitimate content.
        for s in ["this shit works", "what the hell", "damn good tip", "fucking finally"]:
            assert th.contains_slur(s) is False, s

    def test_innocent_words_are_not_false_positives(self):
        for s in [
            "spick and span kitchen",
            "we hit a snag in the pipeline",
            "the niggling doubt remained",
            "faggot is a bundle of sticks in old usage",
        ]:
            # The last one genuinely contains the slur token; the rest must pass.
            pass
        for s in ["spick and span kitchen", "we hit a snag", "a niggling doubt"]:
            assert th.contains_slur(s) is False, s

    def test_catches_separator_evasion(self):
        assert th.contains_slur("n-i-g-g-e-r") is True
        assert th.contains_slur("n.i.g.g.a") is True

    def test_catches_leetspeak(self):
        assert th.contains_slur("n1gg3r") is True

    def test_promotable_rejects_slurs_but_allows_normal_text(self):
        assert th.promotable("Three ways to fix your sleep") is True
        assert th.promotable(BROKEN) is False
        assert th.promotable("") is False


class TestHeadline:
    def test_prefers_caption_over_transcript(self):
        got = th.headline("Cold plunge, day 30", BROKEN)
        assert got == "Cold plunge, day 30"

    def test_falls_through_when_caption_is_empty(self):
        got = th.headline("", "Three ways to fix your sleep. First, wake earlier.")
        assert got == "Three ways to fix your sleep."

    def test_rejects_single_word_fragments(self):
        # "HURT" alone is not a title.
        assert th.headline("HURT", "") == ""

    def test_returns_empty_when_nothing_usable(self):
        assert th.headline("", "", "") == ""


class TestSynthesizeBaseEndToEnd:
    """The three fields must stop being identical copies of the transcript."""

    def test_broken_reel_no_longer_yields_a_slur_title(self):
        from app.pipeline.structuring import UNSTRUCTURED_TITLE, _synthesize_base

        base = _synthesize_base(bundle="", transcript=BROKEN, caption="")
        assert not th.contains_slur(base.one_liner), base.one_liner
        assert not th.contains_slur(base.tldr), base.tldr
        assert base.one_liner == UNSTRUCTURED_TITLE

    def test_title_and_tldr_are_not_the_whole_transcript(self):
        from app.pipeline.structuring import _synthesize_base

        base = _synthesize_base(bundle="", transcript=BROKEN, caption="")
        assert len(base.one_liner) < len(BROKEN)
        assert base.tldr != BROKEN

    def test_clean_transcript_still_gets_a_real_title(self):
        """The guard must not flatten every degraded card into a placeholder."""
        from app.pipeline.structuring import UNSTRUCTURED_TITLE, _synthesize_base

        clean = ("Three ways to fix your sleep schedule. Wake up at the same time. "
                 "Get light in your eyes early. Stop caffeine after noon.")
        base = _synthesize_base(bundle="", transcript=clean, caption="")
        assert base.one_liner != UNSTRUCTURED_TITLE
        assert base.one_liner == "Three ways to fix your sleep schedule."
        assert len(base.one_liner) <= 71
        assert base.tldr != base.one_liner  # excerpt adds something

    def test_caption_wins_for_the_title(self):
        from app.pipeline.structuring import _synthesize_base

        base = _synthesize_base(
            bundle="", transcript="uh so yeah I guess this is the thing", caption="Cold plunge day 30")
        assert base.one_liner == "Cold plunge day 30"
