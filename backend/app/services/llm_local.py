"""Local fallback LLM running directly inside the backend / Hugging Face Space.

Uses llama-cpp-python to run a quantized GGUF model (default: Qwen 2.5 0.5B Instruct)
on server CPU/RAM. Provides 100% free, keyless structuring fallback when cloud APIs
(Gemini, Cerebras, Groq) exhaust their free-tier quotas.
"""

from __future__ import annotations

import logging
import threading
from typing import Any

from app.config import get_settings

log = logging.getLogger("services.llm_local")

_lock = threading.Lock()
_llama_instance: Any = None
_load_failed: bool = False


def _get_model():
    """Lazy-load the local Llama model singleton."""
    global _llama_instance, _load_failed
    if _load_failed:
        return None
    if _llama_instance is not None:
        return _llama_instance

    with _lock:
        if _llama_instance is not None:
            return _llama_instance
        if _load_failed:
            return None

        settings = get_settings()
        if not settings.local_llm_enabled:
            return None

        try:
            from huggingface_hub import hf_hub_download
            from llama_cpp import Llama
        except ImportError as exc:
            log.warning("local_llm: llama-cpp-python or huggingface_hub not installed: %s", exc)
            _load_failed = True
            return None

        try:
            log.info(
                "local_llm: fetching model %s (%s)...",
                settings.local_llm_repo,
                settings.local_llm_file,
            )
            model_path = hf_hub_download(
                repo_id=settings.local_llm_repo,
                filename=settings.local_llm_file,
            )
            log.info("local_llm: loading model from %s (threads=%d)...", model_path, settings.local_llm_threads)
            _llama_instance = Llama(
                model_path=model_path,
                n_ctx=settings.local_llm_ctx,
                n_threads=settings.local_llm_threads,
                verbose=False,
            )
            log.info("local_llm: model initialized successfully")
            return _llama_instance
        except Exception as exc:
            log.error("local_llm: failed to load model: %s", exc)
            _load_failed = True
            return None


def complete_local(
    prompt: str,
    *,
    system: str | None = None,
    max_tokens: int = 2048,
    temperature: float = 0.2,
) -> str | None:
    """Generate completion using the local server-side model."""
    model = _get_model()
    if model is None:
        return None

    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})

    try:
        with _lock:
            # Enforce JSON object format in grammar if prompt requests JSON
            is_json = "json" in prompt.lower() or (system and "json" in system.lower())
            kwargs = {
                "messages": messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
            }
            if is_json:
                kwargs["response_format"] = {"type": "json_object"}

            response = model.create_chat_completion(**kwargs)
            choice = response.get("choices", [{}])[0]
            msg = choice.get("message", {})
            content = msg.get("content", "").strip()
            return content or None
    except Exception as exc:
        log.warning("local_llm: generation error: %s", exc)
        return None


def is_available() -> bool:
    """Check if local LLM is enabled and runnable."""
    settings = get_settings()
    return settings.local_llm_enabled and not _load_failed


def reset() -> None:
    """Reset the singleton instance (for testing)."""
    global _llama_instance, _load_failed
    with _lock:
        _llama_instance = None
        _load_failed = False
