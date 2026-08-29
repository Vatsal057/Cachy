"""Turning raw ASR text into something safe to show as a title.

The degraded path used to build a card's title with ``source.split(".")[0]``.
Speech-to-text output has no sentence punctuation, so that expression returns
the entire transcript, and the same string then landed in the title, the TL;DR
and the body block. A one minute clip produced a 120 character "title" repeated
three times.

Two jobs here, kept apart on purpose:

``headline`` shortens text for a title without lying about what it is.
``promotable`` answers whether a fragment of somebody else's speech belongs in
a title at all, which is a different question from whether it can be stored.
"""
from __future__ import annotations

import re

# Sentence enders, then clause-ish boundaries. ASR gives us question marks and
# commas far more often than full stops, so those have to count as breaks or
# there is nothing to split on.
_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")
_CLAUSE_BREAK = re.compile(r"\s*[,;:]\s*|\s+(?:and|but|so|then|because)\s+", re.I)

# "You call this fat? You call this fat? You call this fat?" -> one copy.
# Matches a 2+ word phrase repeated back to back, allowing punctuation drift.
#
# The trailing boundary is a lookahead over whitespace/punctuation/end-of-string
# rather than \b, because the repeated phrase usually ends in "?" and \b after a
# non-word character demands a word character next, which fails at end of input.
_IMMEDIATE_REPEAT = re.compile(
    r"\b((?:\w+[\s,]+){1,7}?\w+)([?!.]?)(?:\s*\1\2?(?=\s|$|[^\w]))+", re.I
)

# Filler that ASR emits constantly and that reads badly at the front of a title.
_LEADING_FILLER = re.compile(
    r"^(?:oh|uh|um|ah|so|and|but|like|okay|ok|yeah|yo|hey|well|i mean)\b[\s,]*",
    re.I,
)


def collapse_repeats(text: str) -> str:
    """Collapse back-to-back duplicate phrases produced by speech or captions."""
    out = text or ""
    # A phrase can repeat in a nested way, so run until it settles.
    for _ in range(4):
        nxt = _IMMEDIATE_REPEAT.sub(r"\1\2", out)
        if nxt == out:
            break
        out = nxt
    return re.sub(r"\s{2,}", " ", out).strip()


def truncate_words(text: str, limit: int) -> str:
    """Cut to `limit` characters on a word boundary, adding an ellipsis.

    Never splits mid-word, because a title ending in "sk" reads like a bug
    rather than a summary.
    """
    text = (text or "").strip()
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(" ,;:.!?-")
    # A single very long word leaves nothing after rsplit; fall back to a hard cut.
    if not cut:
        cut = text[:limit].rstrip()
    return cut + "\u2026"


#: Past this length a title reads as a run-on, so try a clause break even though
#: the text would still fit inside the hard limit.
_SOFT_TARGET = 45


def first_clause(text: str, limit: int = 70) -> str:
    """The first sentence, or failing that the first clause, of `text`.

    Falls back through sentence break, then clause break, then a word-boundary
    truncation, so punctuation-free input still yields something short.
    """
    cleaned = collapse_repeats(text)
    if not cleaned:
        return ""
    candidate = _LEADING_FILLER.sub("", _SENTENCE_END.split(cleaned)[0].strip()).strip()
    if len(candidate) > _SOFT_TARGET:
        head = _CLAUSE_BREAK.split(candidate)[0].strip()
        # Only accept the shorter version if it still reads as a phrase.
        if len(head.split()) >= 3:
            candidate = head
    return truncate_words(candidate, limit)


def headline(*sources: str, limit: int = 70) -> str:
    """Best short headline from the given sources, in order of preference.

    Callers pass caption before transcript: a caption is written by a person
    and is usually already short, while a transcript is raw speech.
    """
    for src in sources:
        got = first_clause(src or "", limit=limit)
        # Two words is the floor for something to read as a title rather than
        # a stray interjection.
        if got and len(got.split()) >= 2:
            return got
    return ""


# --------------------------------------------------------------------------- #
# Promotion guard
# --------------------------------------------------------------------------- #
# Slurs, matched with tolerance for the usual obfuscations and for whatever
# spelling speech-to-text lands on. Deliberately narrow: this gates what may be
# copied into a title, so a broad profanity list would suppress ordinary
# content. Ordinary swearing is not in scope and passes through untouched.
_SLUR_PATTERNS = [
    r"n+[i1!*]+[g9]+[g9]+(?:[e3]+r+|a+h?)",     # n-word and variants
    r"f+[a@4]+[g9]+(?:[o0]+t+)?s?\b",           # f-slur
    r"k+[i1]+k+[e3]+s?\b",                       # anti-Jewish slur
    r"[ck]+h+[i1]+n+k+s?\b",                     # anti-Asian slur
    r"s+p+[i1]+[ck]+s?\b(?!\s*(?:and\s*span))",  # anti-Hispanic slur
    r"t+r+[a@4]+n+n+[i1y]+e?s?\b",               # anti-trans slur
    r"r+[e3]+t+[a@4]+r+d+(?:s|ed)?\b",           # ableist slur
]
_SLUR_RE = re.compile("|".join(f"(?:{p})" for p in _SLUR_PATTERNS), re.I)


def contains_slur(text: str) -> bool:
    """True when `text` contains a slur, allowing for leetspeak substitutions."""
    if not text:
        return False
    # Strip separators used to evade filters: n-i-g, n.i.g, n_i_g.
    flattened = re.sub(r"[\s._\-*]+", "", text)
    return bool(_SLUR_RE.search(text) or _SLUR_RE.search(flattened))


def promotable(text: str) -> bool:
    """Whether `text` may be copied into a title or summary.

    Storing a transcript verbatim is fine: it is what the person said, and the
    body block is understood to be raw source material. Promoting a fragment of
    it into a headline is an editorial act, and the pipeline should not make
    that choice on a slur's behalf.
    """
    return bool(text) and not contains_slur(text)
