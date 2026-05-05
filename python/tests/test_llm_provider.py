"""Tests for the native Python LLM provider tier (v1.79).

Two surfaces:

- `MockLLMProvider` — no deps; tests run unconditionally.
- `AnthropicLLMProvider` — uses an injected mock client; the
  anthropic SDK is required to construct (skipped if absent).
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from crucible.llm import (
    LLMProvider,
    LLMProviderError,
    MockLLMProvider,
    TranspileResult,
)


# -----------------------------------------------------------------------------
# MockLLMProvider — no third-party deps, runs everywhere.

def test_mock_provider_returns_named_template():
    p = MockLLMProvider(template_name="kinase_inhibitor_fep")
    out = p.transpile("any paper text")
    assert out.ok
    assert out.spec is not None
    assert out.spec.system.source.pdb_id == "2HYY"
    assert out.provider_name == "mock"


def test_mock_provider_default_is_vanilla():
    p = MockLLMProvider()
    out = p.transpile("...")
    assert out.spec.notes.startswith("vanilla MD template")


def test_mock_provider_unknown_template_returns_failure_result():
    p = MockLLMProvider(template_name="not_a_real_template")
    out = p.transpile("text")
    assert not out.ok
    assert out.spec is None
    assert "template lookup failed" in out.raw_response


def test_mock_provider_implements_abstract_interface():
    # Sanity check: MockLLMProvider satisfies the ABC.
    assert isinstance(MockLLMProvider(), LLMProvider)


def test_transpile_result_ok_property():
    p = MockLLMProvider()
    ok_result = p.transpile("text")
    assert ok_result.ok is True

    # Manually construct a failure result.
    failure = TranspileResult(spec_json="", spec=None, raw_response="boom",
                              provider_name="mock", model="x")
    assert failure.ok is False


# -----------------------------------------------------------------------------
# AnthropicLLMProvider — skip individual tests when the SDK is absent.

try:
    import anthropic   # noqa: F401
    _HAS_ANTHROPIC = True
except ImportError:
    _HAS_ANTHROPIC = False

if _HAS_ANTHROPIC:
    from crucible.llm.anthropic import AnthropicLLMProvider, _extract_tool_use_input

_skip_no_anthropic = pytest.mark.skipif(
    not _HAS_ANTHROPIC, reason="anthropic SDK not installed"
)


def _mock_anthropic_client_with_spec(spec_dict: dict) -> MagicMock:
    """Build an injectable client whose `messages.create` returns one
    tool_use block with the given input."""
    tool_block = MagicMock()
    tool_block.type = "tool_use"
    tool_block.name = "emit_mdspec"
    tool_block.input = spec_dict
    response = MagicMock()
    response.content = [tool_block]
    response.usage = MagicMock(input_tokens=1234, output_tokens=567)
    response.stop_reason = "tool_use"
    client = MagicMock()
    client.messages.create.return_value = response
    return client


def _vanilla_spec_dict() -> dict:
    """A minimal valid v0.4.0 spec dict for round-tripping."""
    from crucible import templates
    import json as _json
    return _json.loads(templates.init("vanilla").to_json())


def test_anthropic_provider_requires_api_key_or_client():
    # No API key in env, no client passed → structural failure.
    import os
    saved = os.environ.pop("ANTHROPIC_API_KEY", None)
    try:
        with pytest.raises(LLMProviderError):
            AnthropicLLMProvider()
    finally:
        if saved is not None:
            os.environ["ANTHROPIC_API_KEY"] = saved


def test_anthropic_provider_transpile_round_trips_spec():
    spec_dict = _vanilla_spec_dict()
    client = _mock_anthropic_client_with_spec(spec_dict)
    p = AnthropicLLMProvider(api_key="test-key", client=client)
    out = p.transpile("Methods: AMBER ff14SB + TIP3P, NPT 310 K, 2 fs.")
    assert out.ok
    assert out.spec is not None
    assert out.provider_name == "anthropic"
    # The mock injected token counts; metadata should surface them.
    assert out.metadata["input_tokens"] == 1234
    assert out.metadata["output_tokens"] == 567


def test_anthropic_provider_handles_no_tool_use_block():
    """If the model declines to call the tool, the provider returns a
    fail-soft result (spec=None) with a clear raw_response."""
    response = MagicMock()
    response.content = []   # no blocks at all
    response.stop_reason = "end_turn"
    client = MagicMock()
    client.messages.create.return_value = response

    p = AnthropicLLMProvider(api_key="test-key", client=client)
    out = p.transpile("Methods: …")
    assert not out.ok
    assert "no tool_use block" in out.raw_response


def test_anthropic_provider_handles_invalid_spec_dict():
    """If the model emits a tool_use whose input isn't a valid MDSpec,
    fail-soft with the validation error."""
    bad_dict = {"schema_version": "0.4.0", "wrong_shape": True}
    client = _mock_anthropic_client_with_spec(bad_dict)
    p = AnthropicLLMProvider(api_key="test-key", client=client)
    out = p.transpile("...")
    assert not out.ok
    assert "validation failed" in out.raw_response.lower()


def test_anthropic_provider_handles_api_exception():
    """Network errors / rate limits surface as fail-soft results,
    not raised exceptions."""
    client = MagicMock()
    client.messages.create.side_effect = RuntimeError("rate limit")
    p = AnthropicLLMProvider(api_key="test-key", client=client)
    out = p.transpile("...")
    assert not out.ok
    assert "rate limit" in out.raw_response


def test_extract_tool_use_helper_skips_text_blocks():
    """Helper picks the right block from a mixed-content response."""
    text_block = MagicMock()
    text_block.type = "text"
    text_block.text = "preamble text"
    tool_block = MagicMock()
    tool_block.type = "tool_use"
    tool_block.name = "emit_mdspec"
    tool_block.input = {"x": 1}
    response = MagicMock()
    response.content = [text_block, tool_block]
    out = _extract_tool_use_input(response)
    assert out == {"x": 1}


def test_extract_tool_use_helper_filters_by_tool_name():
    """If the model called a different tool (shouldn't happen given
    tool_choice, but defensive), return None."""
    tool_block = MagicMock()
    tool_block.type = "tool_use"
    tool_block.name = "some_other_tool"
    tool_block.input = {"x": 1}
    response = MagicMock()
    response.content = [tool_block]
    assert _extract_tool_use_input(response) is None


# -----------------------------------------------------------------------------
# LocalOpenAIProvider — stdlib-only; no SDK to skip.

import json as _json

from crucible.llm.local import LocalOpenAIProvider


def _vanilla_envelope() -> dict:
    """Build an OpenAI-compatible response envelope with the vanilla
    template as the assistant message content."""
    spec_dict = _vanilla_spec_dict()
    return {
        "id": "chat-test",
        "object": "chat.completion",
        "model": "test-model",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": _json.dumps(spec_dict),
                },
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": 200,
            "completion_tokens": 800,
            "total_tokens": 1000,
        },
    }


def _make_local_post(body_str: str):
    """Build an http_post= callable that always returns body_str."""
    def fake_post(url, body, headers, timeout_s):
        return body_str
    return fake_post


def test_local_provider_round_trips_spec():
    fake = _make_local_post(_json.dumps(_vanilla_envelope()))
    p = LocalOpenAIProvider(
        endpoint="http://localhost:11434/v1",
        model="qwen-test",
        api_key="ollama",
        http_post=fake,
    )
    out = p.transpile("Methods: …")
    assert out.ok
    assert out.spec is not None
    assert out.provider_name == "local"
    assert out.metadata["prompt_tokens"] == 200
    assert out.metadata["completion_tokens"] == 800


def test_local_provider_handles_connection_error():
    """Network failures return a fail-soft TranspileResult."""
    def boom(url, body, headers, timeout_s):
        raise ConnectionRefusedError("connection refused")
    p = LocalOpenAIProvider(http_post=boom)
    out = p.transpile("...")
    assert not out.ok
    assert "connection refused" in out.raw_response.lower()


def test_local_provider_handles_non_json_response():
    """Bad gateway / HTML error pages should fail-soft, not crash."""
    fake = _make_local_post("<html>502 Bad Gateway</html>")
    p = LocalOpenAIProvider(http_post=fake)
    out = p.transpile("...")
    assert not out.ok
    assert "non-JSON" in out.raw_response or "non-json" in out.raw_response.lower()


def test_local_provider_handles_empty_choices():
    fake = _make_local_post(_json.dumps({"choices": []}))
    p = LocalOpenAIProvider(http_post=fake)
    out = p.transpile("...")
    assert not out.ok
    assert "no choices" in out.raw_response


def test_local_provider_handles_invalid_spec_content():
    """If the model emits content that doesn't validate as MDSpec,
    fail-soft with the validation error."""
    bad_envelope = {
        "choices": [
            {"message": {"content": _json.dumps({"wrong_shape": True})}}
        ]
    }
    fake = _make_local_post(_json.dumps(bad_envelope))
    p = LocalOpenAIProvider(http_post=fake)
    out = p.transpile("...")
    assert not out.ok
    assert "validation failed" in out.raw_response.lower()


def test_local_provider_env_var_defaults(monkeypatch):
    """Constructor falls back to CRUCIBLE_LOCAL_* env vars."""
    monkeypatch.setenv("CRUCIBLE_LOCAL_ENDPOINT", "http://test:8080/v1")
    monkeypatch.setenv("CRUCIBLE_LOCAL_MODEL", "test-from-env")
    monkeypatch.setenv("CRUCIBLE_LOCAL_API_KEY", "envkey")
    p = LocalOpenAIProvider(http_post=lambda *a, **kw: "{}")
    assert p.endpoint == "http://test:8080/v1"
    assert p.model == "test-from-env"
    assert p.api_key == "envkey"


def test_local_provider_url_assembly(monkeypatch):
    """The endpoint's trailing slash must not double up."""
    captured = {}
    def capture(url, body, headers, timeout_s):
        captured["url"] = url
        return _json.dumps(_vanilla_envelope())
    p = LocalOpenAIProvider(
        endpoint="http://localhost:8000/v1/",   # trailing slash
        http_post=capture,
    )
    p.transpile("...")
    assert captured["url"] == "http://localhost:8000/v1/chat/completions"


def test_local_provider_implements_abstract_interface():
    p = LocalOpenAIProvider(http_post=lambda *a, **kw: "{}")
    assert isinstance(p, LLMProvider)
