"""Cross-language consistency: Python emits → Julia parses → Julia re-emits → Python parses → assert equal.

Pins the invariant the IR-as-contract design (`musings/why_ir_as_contract.md`)
depends on: a `MDSpec` emitted by the Python `pydantic` models must
round-trip byte-equivalent (after JSON normalization) through the Julia
loader. The polyglot story collapses without it.

Single Julia subprocess per pytest run amortizes the ~3s startup over
N specs — each new template adds ~milliseconds, not seconds.

Skipped automatically when `julia` isn't on PATH (e.g. CI cells that
only run the Python suite). The Julia CI matrix has its own
`Pkg.test()` which exercises the parse path; this test is the
specifically *cross-language* check, only meaningful when both
runtimes are available.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from crucible import templates


REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ROUNDTRIP_SCRIPT = REPO_ROOT / "tools" / "cross_lang_roundtrip.jl"


pytestmark = pytest.mark.skipif(
    shutil.which("julia") is None or not ROUNDTRIP_SCRIPT.exists(),
    reason="julia not on PATH or cross_lang_roundtrip.jl missing",
)


# Representative templates spanning the discriminated `Stage` union and
# the optional system fields. If any of these drifts the cross-language
# contract, the failure should be loud.
_TEMPLATES_TO_ROUNDTRIP = (
    "vanilla",
    "smiles",
    "protein_ligand_fep",
    "remd",
    "membrane",
    "metadynamics",
)


def _normalize_for_compare(obj):
    """Drop key-order sensitivity from dict comparison; sort lists where order
    isn't part of the contract (concept_ids on a Work has no canonical order)."""
    if isinstance(obj, dict):
        return {k: _normalize_for_compare(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_normalize_for_compare(v) for v in obj]
    return obj


@pytest.fixture(scope="module")
def roundtripped() -> dict[str, dict]:
    """Run all six templates through Julia in a single subprocess."""
    inputs = []
    keys = []
    for name in _TEMPLATES_TO_ROUNDTRIP:
        spec = templates.init(name)
        inputs.append(spec.to_json())
        keys.append(name)
    payload = "\n".join(inputs) + "\n"
    proc = subprocess.run(
        ["julia", f"--project={REPO_ROOT}", str(ROUNDTRIP_SCRIPT)],
        input=payload,
        capture_output=True,
        text=True,
        timeout=120,
    )
    if proc.returncode != 0:
        pytest.fail(
            f"cross_lang_roundtrip.jl exited {proc.returncode}\n"
            f"stderr:\n{proc.stderr}\n"
            f"stdout:\n{proc.stdout}"
        )
    out_lines = [ln for ln in proc.stdout.splitlines() if ln.strip()]
    assert len(out_lines) == len(keys), (
        f"expected {len(keys)} lines from Julia, got {len(out_lines)}\n"
        f"stdout: {proc.stdout!r}"
    )
    return dict(zip(keys, (json.loads(ln) for ln in out_lines)))


@pytest.mark.parametrize("name", _TEMPLATES_TO_ROUNDTRIP)
def test_python_emit_julia_parse_round_trip_preserves_content(name, roundtripped):
    spec = templates.init(name)
    python_obj = json.loads(spec.to_json())
    julia_obj = roundtripped[name]
    assert _normalize_for_compare(python_obj) == _normalize_for_compare(julia_obj), (
        f"{name}: cross-language round-trip diverged.\n"
        f"python: {json.dumps(python_obj, sort_keys=True, indent=2)[:1000]}\n"
        f"julia:  {json.dumps(julia_obj, sort_keys=True, indent=2)[:1000]}"
    )


def test_julia_preserves_provenance_keys(roundtripped):
    """Provenance is a flat dict keyed by JSONPath strings; key set must
    survive the round-trip."""
    for name in _TEMPLATES_TO_ROUNDTRIP:
        spec = templates.init(name)
        python_keys = set(spec.provenance.keys())
        julia_keys = set(roundtripped[name].get("provenance", {}).keys())
        assert python_keys == julia_keys, (
            f"{name}: provenance key set diverged.\n"
            f"only-in-python: {python_keys - julia_keys}\n"
            f"only-in-julia:  {julia_keys - python_keys}"
        )


def test_julia_preserves_stage_kind_discriminator(roundtripped):
    """The `Stage` discriminator (`kind`) must round-trip exactly — the
    Python pydantic discriminated-union depends on it."""
    for name in _TEMPLATES_TO_ROUNDTRIP:
        spec = templates.init(name)
        python_kinds = [s.kind for s in spec.protocol]
        julia_kinds = [stg["kind"] for stg in roundtripped[name]["protocol"]]
        assert python_kinds == julia_kinds, (
            f"{name}: stage kinds diverged.\n"
            f"python: {python_kinds}\njulia:  {julia_kinds}"
        )
