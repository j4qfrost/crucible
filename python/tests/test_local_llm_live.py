"""Live smoke test for `LocalOpenAIProvider` against a running
OpenAI-API-compatible local LLM server (Ollama / vLLM / llama.cpp).

Opt-in only — set `CRUCIBLE_LIVE_LOCAL_LLM=1` to run; otherwise the
whole module is skipped. The unit-test suite in
`test_llm_provider.py` covers the wire format with injected
`http_post=`; this module asserts the *real* HTTP path.

Why we want this:

- The v1.79/v1.80 unit tests stub HTTP. They prove our parser is
  right; they prove nothing about whether the actual Ollama
  `response_format=json_schema` contract works on the model
  someone actually deployed.
- snowman has Ollama + GPU + the qwen2.5-coder family already
  cached. That makes this test cheap to run there, and the
  natural place to wire it into Woodpecker as a gated step.
- The fail-soft contract means a "model declined / produced
  garbage" response should still surface as `out.spec is None`
  with a meaningful `raw_response`, never as a raised exception.

Configure via env (matching the Julia-side names so one config
drives both surfaces):

    CRUCIBLE_LIVE_LOCAL_LLM=1                # opt-in
    CRUCIBLE_LOCAL_ENDPOINT=http://localhost:11434/v1
    CRUCIBLE_LOCAL_MODEL=qwen2.5-coder:3b    # default if unset
"""

from __future__ import annotations

import os
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from crucible.llm.local import LocalOpenAIProvider


_LIVE = os.environ.get("CRUCIBLE_LIVE_LOCAL_LLM") == "1"
_ENDPOINT = os.environ.get("CRUCIBLE_LOCAL_ENDPOINT", "http://localhost:11434/v1")
_MODEL = os.environ.get("CRUCIBLE_LOCAL_MODEL", "qwen2.5-coder:3b")
_TIMEOUT_S = int(os.environ.get("CRUCIBLE_LIVE_LLM_TIMEOUT_S", "120"))

pytestmark = pytest.mark.skipif(
    not _LIVE,
    reason="set CRUCIBLE_LIVE_LOCAL_LLM=1 to run live local-LLM smoke",
)


def _server_reachable() -> bool:
    """Quick liveness probe — the endpoint root or /v1/models should
    respond, even if the model isn't pulled yet."""
    probe = _ENDPOINT.rstrip("/") + "/models"
    try:
        with urllib.request.urlopen(probe, timeout=5) as resp:
            return 200 <= resp.status < 500
    except (urllib.error.URLError, OSError):
        return False


@pytest.fixture(scope="module", autouse=True)
def _require_server():
    if not _server_reachable():
        pytest.skip(f"local-LLM endpoint unreachable at {_ENDPOINT}")


def _read_sample_methods() -> str:
    """Resolve the canonical fixture path. The Python tests run from
    `python/`; the fixture lives at the repo root under `test/`."""
    here = Path(__file__).resolve().parent
    fixture = here.parent.parent / "test" / "fixtures" / "sample_md_methods.txt"
    return fixture.read_text()


def test_local_provider_round_trips_real_methods_paragraph():
    """Feed a real MD Methods section through a real Ollama server.
    Either the model produces a schema-valid MDSpec (success path)
    OR the provider fails soft with `spec is None` + a
    meaningful raw_response. *Never* raise."""
    p = LocalOpenAIProvider(
        endpoint=_ENDPOINT,
        model=_MODEL,
        timeout_s=_TIMEOUT_S,
    )
    out = p.transpile(_read_sample_methods())
    assert out.provider_name == "local"
    assert out.model == _MODEL

    if out.ok:
        # Sanity: the spec parses, has the schema_version, and
        # picked up *something* from the explicit Methods values.
        assert out.spec is not None
        assert out.spec.schema_version == "0.4.0"
        # The Methods text mentions T=300, NVT/NPT, ff14SB. We don't
        # require all of these — small models often miss one — but we
        # require at least one to land somewhere in the spec to prove
        # the model is actually reading the input.
        spec_repr = out.spec.to_json()
        hits = sum(
            needle.lower() in spec_repr.lower()
            for needle in ("ff14sb", "tip3p", "300", "amber", "nvt", "npt")
        )
        assert hits >= 1, (
            f"model output doesn't reference any explicit Methods value;\n"
            f"spec_repr (first 500 chars):\n{spec_repr[:500]}"
        )
        # Token usage should be surfaced when Ollama reports it.
        if out.metadata:
            assert isinstance(out.metadata.get("prompt_tokens", 0), int)
    else:
        # Fail-soft path is also a valid outcome — small models
        # frequently fail schema validation. Just assert the failure
        # is reported cleanly, not as an exception.
        assert out.spec is None
        assert isinstance(out.raw_response, str)
        assert len(out.raw_response) > 0


def test_local_provider_handles_unknown_model_fail_soft():
    """If the configured model isn't pulled, Ollama returns an HTTP
    error — provider should fail-soft with a clear raw_response,
    not raise."""
    p = LocalOpenAIProvider(
        endpoint=_ENDPOINT,
        model="this-model-definitely-does-not-exist:0.0.1",
        timeout_s=10,
    )
    out = p.transpile("Methods: anything.")
    assert not out.ok
    assert out.spec is None
    # Either an HTTPError ("model not found") or some other clear
    # error message — but it must mention either the URL or the
    # missing model.
    assert (_ENDPOINT in out.raw_response
            or "model" in out.raw_response.lower()
            or "not found" in out.raw_response.lower()), (
        f"unhelpful raw_response on unknown model: {out.raw_response!r}"
    )
