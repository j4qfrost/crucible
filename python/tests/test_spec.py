"""Round-trip + invariant tests for the MDSpec IR."""

from __future__ import annotations

import json

import pytest

from crucible import (
    SCHEMA_VERSION,
    DynamicsStage,
    FEPStage,
    ForceFieldSpec,
    MDSpec,
    MinimizeStage,
    Observable,
    REMDStage,
    RestraintSpec,
    SolventSpec,
    SystemSource,
    SystemSpec,
)
from crucible.spec import required_features


def _minimal_spec() -> MDSpec:
    return MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="t.parm7",
                                coordinates="t.rst7"),
            n_atoms_estimate=5_000,
            has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(),
        protocol=[
            MinimizeStage(),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.1),
            DynamicsStage(role="production", ensemble="NPT", duration_ns=1.0,
                          pressure_bar=1.0, barostat="monte_carlo"),
        ],
        observables=[Observable(type="trajectory", stride_ps=10.0)],
    )


def test_schema_version_constant():
    assert SCHEMA_VERSION == "0.4.0"


def test_python_schema_version_matches_canonical_schema_json():
    """Pydantic SCHEMA_VERSION must match the const in src/spec/schema.json.
    A schema bump that touches one but not the other is the regression
    class this test exists to catch."""
    import json
    from pathlib import Path
    repo_root = Path(__file__).resolve().parent.parent.parent
    schema_path = repo_root / "src" / "spec" / "schema.json"
    if not schema_path.is_file():
        pytest.skip(f"canonical schema.json missing at {schema_path}")
    schema = json.loads(schema_path.read_text())
    canonical = schema["properties"]["schema_version"]["const"]
    assert SCHEMA_VERSION == canonical, (
        f"SCHEMA_VERSION ({SCHEMA_VERSION!r}) drifts from "
        f"src/spec/schema.json const ({canonical!r}). "
        f"Update both halves of the bump together."
    )


def test_python_schema_version_matches_julia_mdspec_default():
    """Bumping SCHEMA_VERSION on the Python side requires a matching bump
    in src/spec/MDSpec.jl's MDSpec keyword default. Catches the third
    place a schema bump can drift."""
    from pathlib import Path
    repo_root = Path(__file__).resolve().parent.parent.parent
    mdspec_path = repo_root / "src" / "spec" / "MDSpec.jl"
    if not mdspec_path.is_file():
        pytest.skip(f"MDSpec.jl missing at {mdspec_path}")
    text = mdspec_path.read_text()
    # `MDSpec(; schema_version="0.4.0", ...)` is the canonical kwarg
    # default in src/spec/MDSpec.jl. Match the literal.
    import re
    m = re.search(r'schema_version\s*=\s*"(\d+\.\d+\.\d+)"', text)
    assert m is not None, "could not find `schema_version=\"…\"` in MDSpec.jl"
    julia_default = m.group(1)
    assert SCHEMA_VERSION == julia_default, (
        f"SCHEMA_VERSION ({SCHEMA_VERSION!r}) drifts from MDSpec.jl "
        f"default ({julia_default!r}). Update both halves together."
    )


def test_round_trip_minimal():
    spec = _minimal_spec()
    text = spec.to_json()
    parsed = MDSpec.from_json(text)
    assert parsed == spec


def test_extra_field_rejected():
    spec = _minimal_spec()
    obj = json.loads(spec.to_json())
    obj["unknown_field"] = 42
    with pytest.raises(Exception):
        MDSpec.from_dict(obj)


def test_dynamics_npt_with_pressure_round_trips():
    s = DynamicsStage(role="production", ensemble="NPT", duration_ns=5.0,
                      pressure_bar=1.0, barostat="monte_carlo")
    text = s.model_dump_json()
    parsed = DynamicsStage.model_validate_json(text)
    assert parsed.barostat == "monte_carlo"
    assert parsed.pressure_bar == 1.0


def test_fep_stage_serializes_with_kind_free_energy():
    spec = _minimal_spec()
    fep = FEPStage(target_selection="resname LIG",
                   lambda_windows=[0.0, 0.5, 1.0],
                   duration_per_window_ns=0.1)
    spec = spec.model_copy(update={"protocol": [fep]})
    obj = json.loads(spec.to_json())
    assert obj["protocol"][0]["kind"] == "free_energy"
    assert obj["protocol"][0]["fep_kind"] == "decouple"


def test_remd_stage_round_trip():
    s = REMDStage(temperature_ladder_K=[300.0, 320.0, 340.0])
    text = s.model_dump_json()
    parsed = REMDStage.model_validate_json(text)
    assert parsed.temperature_ladder_K == [300.0, 320.0, 340.0]


def test_required_features_explicit_solvent_pme():
    spec = _minimal_spec()
    feats = required_features(spec)
    assert "explicit_solvent" in feats
    assert "pme" in feats
    assert "barostat" in feats   # NPT production stage


def test_required_features_implicit_solvent():
    spec = _minimal_spec().model_copy(update={
        "system": _minimal_spec().system.model_copy(update={
            "solvent": SolventSpec(model="implicit_GBSA", ions_NaCl_mM=0.0),
        }),
    })
    feats = required_features(spec)
    assert "implicit_solvent" in feats
    assert "pme" not in feats


def test_restraint_default_is_none_with_zero_k():
    r = RestraintSpec()
    assert r.selection == "none"
    assert r.k_kj_mol_nm2 == 0.0


def test_provenance_strict_source_enum():
    from crucible import Provenance
    Provenance(source="paper")
    with pytest.raises(Exception):
        Provenance(source="invented")
