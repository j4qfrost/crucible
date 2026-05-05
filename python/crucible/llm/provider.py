"""Abstract LLM provider + mock implementation.

The concrete providers (AnthropicLLMProvider, LocalOpenAIProvider)
live in their own modules with their own optional deps. This module
has no third-party deps so the base interface always imports.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Optional

from ..spec import MDSpec


class LLMProviderError(RuntimeError):
    """Raised when a provider fails to produce a valid MDSpec.

    Providers should fail-soft on LLM-side issues (rate limit, bad
    completion, etc.) by returning a `TranspileResult` with
    `spec=None` and the error in `raw_response`. They should raise
    this only when the failure is structural (no API key, no network,
    schema file missing, etc.).
    """


@dataclass
class TranspileResult:
    """Mirror of the Julia-side `TranspileResult` (src/llm/Provider.jl).

    Fields kept structurally identical so the cross-language tests
    can validate either side's output through the same checks.
    """
    spec_json: str                  # raw JSON the provider emitted (may be empty)
    spec: Optional[MDSpec]          # parsed spec, or None on failure
    raw_response: str               # full provider response (for audit / debugging)
    provider_name: str              # e.g. "anthropic" / "local" / "mock"
    model: str                      # model id used
    cost_estimate_usd: float = 0.0  # provider-specific token-cost estimate
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return self.spec is not None


# Shared system prompt — mirrors the Julia-side `TRANSPILE_SYSTEM_PROMPT`
# in src/llm/Provider.jl (intentionally kept in sync; future schema
# bumps update both sides). Sourced here so all Python providers share
# one prompt without each one repeating it.
TRANSPILE_SYSTEM_PROMPT = """\
You are Crucible's molecular-dynamics paper transpiler. You read a chemistry or drug-discovery paper (or its Methods section) and emit a single JSON object that conforms exactly to the MDSpec v0.4.0 schema.

CONTRACT, NON-NEGOTIABLE:
1. Output ONLY a JSON object that validates against the MDSpec schema. No prose, no markdown, no code fences.
2. Never invent force-field parameters. If the paper does not state a force field, use the closest match from the allowlist and add a warning + provenance entry with source="assumed".
3. Every numeric field that came from the paper MUST have a provenance entry citing the section/figure/table. Fields you defaulted MUST have provenance with source="paper_default" (paper implied it but did not state it explicitly) or "assumed" (you guessed).
4. Use the protein/water/ligand FF allowlists exactly as written. If a paper says "Amber99", map it to "amber99sb_ildn" and add a warning explaining the mapping.
5. NEVER convert units. Emit values in the units named by the field (temperature_K, dt_fs, duration_ns, etc.). The downstream renderer is the only thing that converts.
6. If the paper describes a system you cannot represent (membranes, free-energy, REMD, plumed) emit an MDSpec for the closest reduced sub-protocol (typically: minimize → NVT → NPT → production) and add a warning describing what you dropped.
"""


class LLMProvider(ABC):
    """Abstract base. Concrete providers implement `transpile`.

    The constructor signature is provider-specific; the abstract base
    only fixes the `transpile` contract.
    """

    @property
    @abstractmethod
    def provider_name(self) -> str:
        """Short identifier — `anthropic`, `local`, `mock`, etc."""

    @abstractmethod
    def transpile(self, paper_text: str, **kwargs) -> TranspileResult:
        """Transpile paper text → MDSpec.

        Implementations must:
        - Catch LLM-side errors (rate limit, bad completion, network)
          and return a TranspileResult with spec=None + the error
          recorded in raw_response. Don't let those propagate.
        - Raise `LLMProviderError` for structural failures (missing
          API key, missing schema file, etc.) — those need attention,
          not graceful degradation.
        """


# -----------------------------------------------------------------------------
# Reference / smoke-test provider — no third-party deps, no network.

class MockLLMProvider(LLMProvider):
    """Deterministic provider for CI + offline smoke testing.

    Returns a pre-built MDSpec for every input; the input text is
    ignored. Useful to wire into pipelines that expect an
    `LLMProvider` instance but shouldn't pay LLM cost.

    Constructor takes a `template_name` (the spec to return). Defaults
    to "vanilla". Tests pin specific templates per scenario.
    """

    def __init__(self, *, template_name: str = "vanilla"):
        self.template_name = template_name

    @property
    def provider_name(self) -> str:
        return "mock"

    def transpile(self, paper_text: str, **kwargs) -> TranspileResult:
        from ..templates import init as init_template
        try:
            spec = init_template(self.template_name)
        except Exception as exc:
            return TranspileResult(
                spec_json="", spec=None,
                raw_response=f"MockLLMProvider: template lookup failed: {exc}",
                provider_name=self.provider_name,
                model=f"mock-template:{self.template_name}",
            )
        return TranspileResult(
            spec_json=spec.to_json(),
            spec=spec,
            raw_response=f"MockLLMProvider: returned {self.template_name!r} template",
            provider_name=self.provider_name,
            model=f"mock-template:{self.template_name}",
            metadata={"template_name": self.template_name},
        )
