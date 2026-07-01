"""Shared Gemini text-completion helper, used by every pipeline task that has
a Gemini key configured. Free tier on gemini-2.5-flash is ~20 requests/day per
key, so low-volume tasks share a pool of spare-account keys (settings.gemini_key_pool)
instead of each getting a dedicated key."""

from __future__ import annotations

import logging

log = logging.getLogger("services.llm_gemini")


def complete(
    api_key: str, model: str, prompt: str, *, system_instruction: str | None = None
) -> str | None:
    """Single-prompt Gemini completion. None on any failure (quota, network, etc).

    When `system_instruction` is set, the static instructions are sent as the
    model's system instruction and only the variable `prompt` as contents. This
    keeps a stable prefix across calls, which lets Gemini 2.5's implicit context
    caching reuse (and discount) the instruction tokens automatically — no cache
    lifecycle to manage."""
    try:
        from google import genai as google_genai
        from google.genai import types

        client = google_genai.Client(api_key=api_key)
        config = (
            types.GenerateContentConfig(system_instruction=system_instruction)
            if system_instruction
            else None
        )
        resp = client.models.generate_content(
            model=model, contents=prompt, config=config
        )
        return (resp.text or "").strip() or None
    except Exception as e:  # noqa: BLE001
        log.warning("gemini call (%s) failed: %s", model, e)
        return None


def complete_with_keys(
    api_keys: list[str], model: str, prompt: str, *, system_instruction: str | None = None
) -> str | None:
    """Try each key in the pool in order (e.g. once one hits its daily quota,
    the next is used); None if every key fails."""
    for key in api_keys:
        result = complete(key, model, prompt, system_instruction=system_instruction)
        if result is not None:
            return result
    return None


def messages_to_prompt(messages: list[dict]) -> str:
    """Flatten a system+history chat message list into a single prompt string."""
    parts = [f"{m.get('role', 'user').upper()}: {m.get('content', '')}" for m in messages]
    parts.append("ASSISTANT:")
    return "\n\n".join(parts)
