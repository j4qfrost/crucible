"""Native Python LLM providers — companion to `cli_bridge` (v1.24).

The cli_bridge shells out to the Julia CLI's `transpile` subcommand
for the LLM call. That works but pays a Julia-startup cost per call
+ requires a Julia install. The providers in this module are
**pure-Python** alternatives — useful when:

- A Python service wants to call the transpile in-process (e.g. a
  FastAPI service rendering benchmark runs).
- A headless CI cell doesn't have Julia available.
- A user wants to integrate Crucible's IR + validation into a
  larger Python LLM pipeline (LangChain, LlamaIndex, etc.).

Three providers ship:

- **`MockLLMProvider`** — deterministic; no network. Returns a
  named template for any input. Useful for CI smoke tests.
- **`AnthropicLLMProvider`** — uses the `anthropic` Python SDK
  with structured-output tool-use binding the canonical MDSpec
  schema. Requires `pip install crucible[llm-anthropic]`.
- **`LocalOpenAIProvider`** — OpenAI-API-compatible client for
  Ollama / vLLM / llama.cpp local servers. Requires
  `pip install crucible[llm-local]`.

The shared contract is `LLMProvider.transpile(paper_text) ->
TranspileResult`. Same shape as the Julia-side
`Crucible.LLMProvider` interface; cross-language consistency is
covered by the schema, not by the provider class.
"""

from __future__ import annotations

from .provider import (
    LLMProvider,
    LLMProviderError,
    MockLLMProvider,
    TranspileResult,
)

__all__ = [
    "LLMProvider",
    "LLMProviderError",
    "MockLLMProvider",
    "TranspileResult",
]
