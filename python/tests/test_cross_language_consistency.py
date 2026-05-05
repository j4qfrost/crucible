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


# -----------------------------------------------------------------------------
# Recorded-transcript round-trip — exercises the actual fixture the
# RecordedProvider replays. If this drifts, every transcript in the
# transcript store risks failing to load on one side.

_RECORDED_FIXTURES = (
    "recorded_anthropic_spec",
    "known_good_spec",
)


def test_python_migration_output_parses_cleanly_in_julia():
    """A v0.1.0-shape spec migrated through the Python registry must
    serialize to JSON that Julia's `spec_from_json` parses without
    error, and the parsed-as-dict result must equal what Python's
    pydantic-validated round-trip produces.

    Pins migration parity — if the Python migration registry drifts
    from Julia's (or either side's parser stops accepting a migrated
    field), this test fires.
    """
    from crucible import migrate_json
    old_v0_1 = json.dumps({
        "schema_version": "0.1.0",
        "system": {
            "source": {"type": "user_supplied", "topology": "p.parm7",
                       "coordinates": "p.rst7", "pdb_id": None},
            "n_atoms_estimate": 12000, "has_ligand": False,
            "solvent": {"model": "TIP3P", "ions_NaCl_mM": 150.0},
        },
        "force_field": {"protein": "amber14sb", "water": "TIP3P",
                        "ligand": "user_supplied"},
        "protocol": [
            {"kind": "minimize", "max_iterations": 1000,
             "tolerance_kj_mol_nm": 10.0},
            {"kind": "dynamics", "role": "production", "ensemble": "NPT",
             "duration_ns": 5.0, "dt_fs": 2.0, "temperature_K": 300.0,
             "pressure_bar": 1.0, "thermostat": "langevin",
             "barostat": "monte_carlo", "friction_ps": 1.0,
             "constraints": "h_bonds",
             "restraints": {"selection": "none", "kind": "harmonic",
                            "k_kj_mol_nm2": 0.0}},
        ],
        "observables": [],
        "provenance": {},
        "warnings": [],
        "notes": "old-shape transcript",
    })
    # Python migrates to the current schema; pydantic re-validates.
    migrated = migrate_json(old_v0_1)
    from crucible import MDSpec
    py_spec = MDSpec.from_json(migrated)
    py_emit = py_spec.to_json()

    # Julia parses the Python-migrated + Python-emitted JSON cleanly.
    proc = subprocess.run(
        ["julia", f"--project={REPO_ROOT}", str(ROUNDTRIP_SCRIPT)],
        input=py_emit + "\n",
        capture_output=True, text=True, timeout=120,
    )
    assert proc.returncode == 0, (
        f"julia rejected the Python-migrated spec\nstderr:\n{proc.stderr}"
    )
    julia_obj = json.loads(proc.stdout.strip())
    py_obj = json.loads(py_emit)
    assert _normalize_for_compare(julia_obj) == _normalize_for_compare(py_obj), (
        "migration output diverges between Python and Julia round-trips."
    )
    # Sanity: the migration actually filled in the v0.4.0-only field.
    assert "padding_nm" in julia_obj["system"]["solvent"]
    assert julia_obj["system"]["solvent"]["padding_nm"] is None


@pytest.mark.parametrize("fixture", _RECORDED_FIXTURES)
def test_julia_can_parse_python_validated_recorded_fixture(fixture):
    """Python pydantic validates the recorded fixture; pipe it through
    Julia's spec_from_json + spec_to_json and the result still round-
    trips through Python."""
    fixture_path = REPO_ROOT / "test" / "fixtures" / f"{fixture}.json"
    if not fixture_path.is_file():
        pytest.skip(f"fixture missing at {fixture_path}")
    raw = fixture_path.read_text()
    # Python parse + emit. Pydantic validates the schema along the way.
    from crucible import MDSpec
    py_spec = MDSpec.from_json(raw)
    py_emitted = py_spec.to_json()
    # Julia parse + emit through the cross_lang_roundtrip script.
    proc = subprocess.run(
        ["julia", f"--project={REPO_ROOT}", str(ROUNDTRIP_SCRIPT)],
        input=py_emitted + "\n",
        capture_output=True, text=True, timeout=120,
    )
    assert proc.returncode == 0, (
        f"julia roundtrip failed for {fixture}:\nstderr:\n{proc.stderr}"
    )
    julia_emitted = proc.stdout.strip()
    assert julia_emitted, f"julia produced no output for {fixture}"
    # Final invariant: parsed-as-dict equality between Python emit and
    # Julia emit. (Key order is not contractual; values must match.)
    py_obj = json.loads(py_emitted)
    julia_obj = json.loads(julia_emitted)
    assert _normalize_for_compare(py_obj) == _normalize_for_compare(julia_obj), (
        f"{fixture}: Python ↔ Julia divergence on recorded fixture.\n"
        f"py:    {json.dumps(py_obj, sort_keys=True)[:600]}\n"
        f"julia: {json.dumps(julia_obj, sort_keys=True)[:600]}"
    )
