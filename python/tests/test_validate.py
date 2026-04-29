"""Gate 1+2 tests for the Python port."""

from __future__ import annotations

import pytest

from crucible import MDSpec, templates, validate
from crucible.spec import (
    DynamicsStage,
    FEPStage,
    ForceFieldSpec,
    MinimizeStage,
    REMDStage,
    SolventSpec,
    SystemSource,
    SystemSpec,
)
from crucible.validate import gate_schema, gate_semantic, run_validation


def _good_spec() -> MDSpec:
    return templates.init("vanilla")


def test_gate_schema_accepts_template():
    spec = _good_spec()
    r = gate_schema(spec.to_json())
    assert r.ok, r.errors


def test_gate_schema_rejects_unknown_field():
    import json
    spec = _good_spec()
    obj = json.loads(spec.to_json())
    obj["bogus"] = True
    r = gate_schema(json.dumps(obj))
    assert not r.ok
    assert any("additional" in e.lower() or "unknown" in e.lower() for e in r.errors)


def test_gate_schema_rejects_bad_enum():
    import json
    spec = _good_spec()
    obj = json.loads(spec.to_json())
    obj["force_field"]["protein"] = "amber99_typo"
    r = gate_schema(json.dumps(obj))
    assert not r.ok


def test_gate_semantic_accepts_template():
    spec = _good_spec()
    r = gate_semantic(spec)
    assert r.ok, r.errors


def test_npt_without_barostat_error():
    spec = _good_spec()
    bad_stage = DynamicsStage(role="production", ensemble="NPT",
                              duration_ns=1.0, pressure_bar=1.0,
                              barostat=None)
    spec = spec.model_copy(update={"protocol": [bad_stage]})
    r = gate_semantic(spec)
    assert not r.ok
    assert any("NPT" in e and "barostat" in e for e in r.errors)


def test_npt_without_pressure_error():
    """NPT with barostat but no pressure -> error from _rule_npt_pressure_required."""
    spec = _good_spec()
    bad = DynamicsStage(role="production", ensemble="NPT",
                        duration_ns=1.0, pressure_bar=None,
                        barostat="monte_carlo")
    spec = spec.model_copy(update={"protocol": [bad]})
    r = gate_semantic(spec)
    assert not r.ok


def test_dt_above_5fs_atomistic_error():
    spec = _good_spec()
    bad = DynamicsStage(role="production", ensemble="NPT", duration_ns=1.0,
                        dt_fs=6.0, pressure_bar=1.0, barostat="monte_carlo")
    spec = spec.model_copy(update={"protocol": [bad]})
    r = gate_semantic(spec)
    assert not r.ok
    assert any("hard cap" in e for e in r.errors)


def test_implicit_solvent_npt_incoherent():
    spec = _good_spec().model_copy(update={
        "system": _good_spec().system.model_copy(update={
            "solvent": SolventSpec(model="implicit_GBSA", ions_NaCl_mM=0.0),
        }),
    })
    r = gate_semantic(spec)
    assert not r.ok
    assert any("implicit solvent" in e.lower() for e in r.errors)


def test_fep_lambda_must_be_monotonic():
    spec = _good_spec()
    bad = FEPStage(target_selection="resname LIG",
                   lambda_windows=[0.0, 0.5, 0.4, 1.0],
                   duration_per_window_ns=0.1,
                   ensemble="NPT", pressure_bar=1.0)
    spec = spec.model_copy(update={"protocol": [bad]})
    r = gate_semantic(spec)
    assert not r.ok


def test_remd_must_be_strictly_increasing():
    spec = _good_spec()
    bad = REMDStage(temperature_ladder_K=[300.0, 280.0, 320.0],
                    ensemble="NVT")
    spec = spec.model_copy(update={"protocol": [bad]})
    r = gate_semantic(spec)
    assert not r.ok


def test_smiles_source_requires_real_ligand_ff():
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="smiles", ligand_smiles="CCO"),
            n_atoms_estimate=9, has_ligand=True,
            solvent=SolventSpec(model="vacuum"),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="vacuum",
                                   ligand="user_supplied"),
        protocol=[
            MinimizeStage(),
            DynamicsStage(role="production", ensemble="NVT", duration_ns=0.1),
        ],
    )
    r = gate_semantic(spec)
    assert not r.ok


def test_run_validation_short_circuits_on_gate_1():
    """If gate 1 fails, gate 2 errors should not be present."""
    import json
    spec = _good_spec()
    obj = json.loads(spec.to_json())
    obj["unknown"] = True
    r = run_validation(spec, spec_json=json.dumps(obj))
    # Short-circuited at gate 1, so no semantic errors leak through.
    assert not r.ok
    assert all("schema error" in e for e in r.errors)


def test_validate_callable_form():
    spec = _good_spec()
    r = validate(spec)
    assert r.ok


@pytest.mark.parametrize("name", [
    "vanilla", "smiles", "protein_ligand_fep", "remd", "membrane",
    "metadynamics", "kinase_inhibitor_fep", "bcl2_ppi_inhibitor",
    "gpcr_oncogene_membrane", "polymer_dynamics", "battery_electrolyte",
    "enzyme_design_remd", "antibody_paratope_fep",
])
def test_all_templates_pass_gates_1_and_2(name):
    spec = templates.init(name)
    r = run_validation(spec)
    assert r.ok, f"{name}: {r.errors}"
