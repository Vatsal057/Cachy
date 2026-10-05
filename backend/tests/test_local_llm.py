"""Tests for the local fallback LLM service (Qwen 2.5 0.5B via llama-cpp-python)

and the structuring fallback chain.
"""

from unittest.mock import patch
import pytest

from app.config import get_settings
from app.pipeline import structuring
from app.services import llm_local


def test_llm_local_enabled_by_default():
    settings = get_settings()
    assert settings.local_llm_enabled is True
    assert "qwen" in settings.local_llm_repo.lower()


def test_complete_falls_back_to_local_when_cloud_keys_empty():
    """Verify that complete() routes to complete_local when cloud services are disabled."""
    with patch("app.pipeline.structuring.get_settings") as mock_settings:
        mock_settings.return_value.gemini_structuring_keys = []
        mock_settings.return_value.cerebras_enabled = False
        mock_settings.return_value.groq_api_key = ""
        mock_settings.return_value.local_llm_enabled = True

        mock_card_json = '{"base": {"one_liner": "Test line", "tldr": "Test summary", "content_type": "tip", "type_confidence": 0.9, "tags": ["test"]}, "blocks": [{"type": "heading", "text": "Header", "level": 1}, {"type": "paragraph", "text": "Body text"}]}'

        with patch("app.services.llm_local.complete_local", return_value=mock_card_json) as mock_complete_local:
            result = structuring.complete("Test prompt", system="Test system")
            assert result == mock_card_json
            mock_complete_local.assert_called_once()


def test_complete_local_returns_none_when_disabled():
    with patch("app.services.llm_local.get_settings") as mock_settings:
        mock_settings.return_value.local_llm_enabled = False
        result = llm_local.complete_local("test prompt")
        assert result is None


def test_structure_card_with_local_fallback():
    """Verify that structure_card produces a valid StructuredCard when using local output."""
    mock_json = """{
      "base": {
        "one_liner": "Cook pasta cleanly",
        "tldr": "Boil pasta in salted water and finish in the pan.",
        "content_type": "recipe",
        "type_confidence": 0.95,
        "tags": ["cooking", "pasta"]
      },
      "blocks": [
        {"type": "heading", "text": "Pasta Recipe", "level": 1},
        {"type": "paragraph", "text": "Boil in salted water."}
      ],
      "artifacts": [],
      "action_items": ["Salt the water"],
      "concepts": ["emulsion"],
      "depth": "shallow"
    }"""

    with patch("app.pipeline.structuring._call_llm", return_value=mock_json):
        card = structuring.structure("dummy bundle")
        assert card.degraded is False
        assert card.base.one_liner == "Cook pasta cleanly"
        assert len(card.blocks) == 2
        assert card.blocks[0]["type"] == "heading"
        assert card.blocks[1]["type"] == "paragraph"
