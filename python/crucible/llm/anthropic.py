"""AnthropicLLMProvider — native Python; uses the `anthropic` SDK with
structured-output tool-use to bind the canonical MDSpec schema.

Requires `pip install crucible[llm-anthropic]`. The base
`LLMProvider` interface (in `provider.py`) has no third-party deps;
this module's `anthropic` import is guarded so the rest of the
package loads fine without it.

Mirrors the Julia-side `AnthropicProvider` in `src/llm/AnthropicProvider.jl` —
same contract, same prompt, same schema binding. Cross-language
consistency tests in `python/tests/test_cross_language_consistency.py`
exercise the IR; this module's tests use a mocked `anthropic.Anthropic`
client.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Optional

from .provider import (
    LLMProvider,
    LLMProviderError,
    TRANSPILE_SYSTEM_PROMPT,
    TranspileResult,
)
from ..spec import MDSpec


_TOOL_NAME = "emit_mdspec"
_DEFAULT_MODEL = "claude-opus-4-7"
_DEFAULT_MAX_TOKENS = 8192


def _load_schema() -> dict:
    """Load the canonical schema. Mirrors `crucible.validate._load_schema`."""
    try:
        from importlib.resources import files
        ref = files("crucible").joinpath("_data/schema.json")
        if ref.is_file():
            with ref.open("r") as fh:
                return json.load(fh)
    except (ModuleNotFoundError, FileNotFoundError):
        pass
    # Dev-tree fallback.
    here = Path(__file__).resolve().parent
    schema_path = here.parent.parent.parent / "src" / "spec" / "schema.json"
    with schema_path.open("r") as fh:
        return json.load(fh)


class AnthropicLLMProvider(LLMProvider):
    """Anthropic Messages API client with MDSpec schema bound as a tool.

    The structured-output approach: declare a single tool `emit_mdspec`
    whose `input_schema` is the canonical MDSpec JSON Schema, then
    force-call it via `tool_choice={"type": "tool", "name": "emit_mdspec"}`.
    The model's response is one tool-use block whose `input` is a
    schema-validated JSON object — the same object the Julia
    AnthropicProvider extracts.

    Constructor:
        AnthropicLLMProvider(api_key=..., model="claude-opus-4-7")

    Defaults: api_key from `ANTHROPIC_API_KEY`; model from
    `CRUCIBLE_ANTHROPIC_MODEL` if set, else
    `claude-opus-4-7`.
    """

    def __init__(
        self,
        *,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        max_tokens: int = _DEFAULT_MAX_TOKENS,
        client: Any = None,
    ):
        try:
            import anthropic   # noqa: F401
        except ImportError as exc:
            raise LLMProviderError(
                "AnthropicLLMProvider requires the anthropic SDK. "
                "Install with `pip install crucible[llm-anthropic]`."
            ) from exc
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not self.api_key and client is None:
            raise LLMProviderError(
                "AnthropicLLMProvider: no API key. Set ANTHROPIC_API_KEY "
                "or pass api_key=… explicitly."
            )
        self.model = model or os.environ.get("CRUCIBLE_ANTHROPIC_MODEL", _DEFAULT_MODEL)
        self.max_tokens = max_tokens
        # Client is injectable for tests (we never want pytest hitting
        # the real API).
        if client is not None:
            self._client = client
        else:
            import anthropic
            self._client = anthropic.Anthropic(api_key=self.api_key)
        self._schema_cache: Optional[dict] = None

    @property
    def provider_name(self) -> str:
        return "anthropic"

    @property
    def schema(self) -> dict:
        if self._schema_cache is None:
            self._schema_cache = _load_schema()
        return self._schema_cache

    def transpile(self, paper_text: str, **kwargs) -> TranspileResult:
        tools = [{
            "name": _TOOL_NAME,
            "description": "Emit a MDSpec JSON object describing the "
                           "molecular-dynamics protocol from the paper.",
            "input_schema": self.schema,
        }]
        try:
            response = self._client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                system=TRANSPILE_SYSTEM_PROMPT,
                tools=tools,
                tool_choice={"type": "tool", "name": _TOOL_NAME},
                messages=[{
                    "role": "user",
                    "content": "Paper text:\n\n" + paper_text,
                }],
            )
        except Exception as exc:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=f"anthropic.messages.create failed: {exc}",
                provider_name=self.provider_name,
                model=self.model,
            )

        # Extract the tool_use block.
        spec_dict = _extract_tool_use_input(response)
        if spec_dict is None:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=(
                    "anthropic response had no tool_use block — "
                    "the model declined to call emit_mdspec. "
                    f"Stop reason: {getattr(response, 'stop_reason', '?')}"
                ),
                provider_name=self.provider_name,
                model=self.model,
            )
        spec_json = json.dumps(spec_dict)
        spec: Optional[MDSpec] = None
        try:
            spec = MDSpec.from_dict(spec_dict)
        except Exception as exc:
            return TranspileResult(
                spec_json=spec_json, spec=None,
                raw_response=f"MDSpec validation failed: {exc}",
                provider_name=self.provider_name,
                model=self.model,
            )
        # Cost estimate is provider-specific; we expose token usage as
        # metadata so the caller can compute it themselves.
        usage = getattr(response, "usage", None)
        metadata = {}
        if usage is not None:
            metadata["input_tokens"] = getattr(usage, "input_tokens", None)
            metadata["output_tokens"] = getattr(usage, "output_tokens", None)
        return TranspileResult(
            spec_json=spec_json,
            spec=spec,
            raw_response="anthropic tool_use call succeeded",
            provider_name=self.provider_name,
            model=self.model,
            metadata=metadata,
        )


def _extract_tool_use_input(response: Any) -> Optional[dict]:
    """Walk the response's content blocks; return the input of the
    first `tool_use` block whose name matches `emit_mdspec`. None if
    there isn't one (the model didn't call the tool)."""
    content = getattr(response, "content", [])
    for block in content:
        # Block is a TextBlock or ToolUseBlock; type tag is `type`.
        if getattr(block, "type", None) == "tool_use":
            if getattr(block, "name", None) == _TOOL_NAME:
                input_obj = getattr(block, "input", None)
                if isinstance(input_obj, dict):
                    return input_obj
    return None
