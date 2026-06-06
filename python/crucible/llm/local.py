"""LocalOpenAIProvider — pure-Python client for OpenAI-API-compatible
local LLM servers (Ollama, vLLM, llama.cpp, LM Studio, etc.).

Mirrors the Julia-side `LocalProvider` (`src/llm/LocalProvider.jl`):
hits `/v1/chat/completions` with `response_format={"type":
"json_schema", "json_schema": {…}}` to bind the canonical MDSpec
schema. The structured-output approach is more universal for
OpenAI-compatible servers than tool-use is.

No third-party HTTP deps — uses stdlib `urllib.request` (same
pattern as `corpus/openalex.py`). Fail-soft on every failure mode
(connection refused, malformed response, schema-violating output) —
returns `TranspileResult(spec=None, raw_response=…)` rather than
raising.

Configure via constructor or env:

    LocalOpenAIProvider(endpoint="http://localhost:11434/v1",
                       model="qwen3:14b")

    # or via env (these match the Julia-side env-var names so the
    # same configuration drives both):
    CRUCIBLE_LOCAL_ENDPOINT=http://localhost:11434/v1
    CRUCIBLE_LOCAL_MODEL=qwen3:14b
    CRUCIBLE_LOCAL_API_KEY=ollama
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Callable, Optional

from .provider import (
    LLMProvider,
    LLMProviderError,
    TRANSPILE_SYSTEM_PROMPT,
    TranspileResult,
)
from ..spec import MDSpec


_DEFAULT_ENDPOINT = "http://localhost:8000/v1"
_DEFAULT_MODEL = "qwen3:14b"
_DEFAULT_TIMEOUT_S = 120


def _load_schema() -> dict:
    """Load the canonical schema. Same path-fallback as the
    AnthropicLLMProvider variant."""
    try:
        from importlib.resources import files
        ref = files("crucible").joinpath("_data/schema.json")
        if ref.is_file():
            with ref.open("r") as fh:
                return json.load(fh)
    except (ModuleNotFoundError, FileNotFoundError):
        pass
    here = Path(__file__).resolve().parent
    schema_path = here.parent.parent.parent / "src" / "spec" / "schema.json"
    with schema_path.open("r") as fh:
        return json.load(fh)


# Type alias for an injectable HTTP poster (for tests). Callable takes
# (url, body_str, headers, timeout_s) and returns a string body.
HttpPostFn = Callable[[str, str, dict, int], str]


class LocalOpenAIProvider(LLMProvider):
    """OpenAI-API-compatible client for local LLM servers.

    The contract:

    - POST `/v1/chat/completions` with `response_format` binding the
      MDSpec schema. The content of the assistant message is expected
      to be the schema-validated JSON object as a string.
    - Parse the content; validate via `MDSpec.from_json`.
    - Fail-soft on every failure mode.

    Tests inject `http_post=` to mock the HTTP layer; production
    callers leave it `None` to use the stdlib path.
    """

    def __init__(
        self,
        *,
        endpoint: Optional[str] = None,
        model: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout_s: int = _DEFAULT_TIMEOUT_S,
        http_post: Optional[HttpPostFn] = None,
    ):
        self.endpoint = (
            endpoint
            or os.environ.get("CRUCIBLE_LOCAL_ENDPOINT")
            or _DEFAULT_ENDPOINT
        )
        self.model = (
            model
            or os.environ.get("CRUCIBLE_LOCAL_MODEL")
            or _DEFAULT_MODEL
        )
        self.api_key = (
            api_key
            or os.environ.get("CRUCIBLE_LOCAL_API_KEY")
            or "EMPTY"     # vLLM / llama.cpp default sentinel
        )
        self.timeout_s = timeout_s
        # Injectable transport seam for tests.
        self._http_post = http_post or _stdlib_http_post
        self._schema_cache: Optional[dict] = None

    @property
    def provider_name(self) -> str:
        return "local"

    @property
    def schema(self) -> dict:
        if self._schema_cache is None:
            self._schema_cache = _load_schema()
        return self._schema_cache

    def transpile(self, paper_text: str, **kwargs) -> TranspileResult:
        body = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": TRANSPILE_SYSTEM_PROMPT},
                {"role": "user", "content": "Paper text:\n\n" + paper_text},
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "mdspec",
                    "schema": self.schema,
                    "strict": True,
                },
            },
            "temperature": 0.0,
            "max_tokens": 8192,
        }
        url = self.endpoint.rstrip("/") + "/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        try:
            response_str = self._http_post(
                url, json.dumps(body), headers, self.timeout_s
            )
        except Exception as exc:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=f"local provider request to {url} failed: {exc}",
                provider_name=self.provider_name,
                model=self.model,
            )

        # Parse the OpenAI-style envelope.
        try:
            envelope = json.loads(response_str)
        except json.JSONDecodeError as exc:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=f"non-JSON response from {url}: {exc}\nbody: {response_str[:500]}",
                provider_name=self.provider_name,
                model=self.model,
            )

        choices = envelope.get("choices") or []
        if not choices:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=f"local provider response had no choices: {response_str[:500]}",
                provider_name=self.provider_name,
                model=self.model,
            )
        message = choices[0].get("message") or {}
        spec_json = str(message.get("content") or "")
        if not spec_json:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=f"empty content in choices[0].message: {response_str[:500]}",
                provider_name=self.provider_name,
                model=self.model,
            )
        try:
            spec = MDSpec.from_json(spec_json)
        except Exception as exc:
            return TranspileResult(
                spec_json=spec_json, spec=None,
                raw_response=f"MDSpec validation failed: {exc}",
                provider_name=self.provider_name,
                model=self.model,
            )

        # Surface usage if the server reports it (Ollama + vLLM both do).
        usage = envelope.get("usage") or {}
        metadata = {}
        for k in ("prompt_tokens", "completion_tokens", "total_tokens"):
            if k in usage:
                metadata[k] = usage[k]
        return TranspileResult(
            spec_json=spec_json,
            spec=spec,
            raw_response=f"local provider {url} succeeded",
            provider_name=self.provider_name,
            model=self.model,
            metadata=metadata,
        )


def _stdlib_http_post(url: str, body: str, headers: dict, timeout_s: int) -> str:
    """Default HTTP transport — stdlib urllib. No third-party deps.

    Tests pass an alternative; the only reason this is its own
    function is to keep the production path single-line and the
    mock seam explicit.
    """
    req = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            return resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        # Read the error body and bubble it through — useful for
        # rate-limit + auth-error diagnosis.
        body_str = ""
        try:
            body_str = exc.read().decode("utf-8")
        except Exception:
            pass
        raise LLMProviderError(
            f"HTTP {exc.code} from {url}: {body_str[:500]}"
        ) from exc
