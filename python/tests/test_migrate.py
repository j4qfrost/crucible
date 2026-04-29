"""Migration-framework tests."""

from __future__ import annotations

import json

import pytest

from crucible import migrate_json, templates


def test_identity_when_target_equals_input():
    spec = templates.init("vanilla")
    out = migrate_json(spec.to_json(), target="0.3.0")
    assert json.loads(out)["schema_version"] == "0.3.0"


def test_v0_1_to_v0_3_chain_fills_nullables():
    """Old v0.1.0 specs lacked ligand_smiles/membrane/lipid; the migration
    chain should fill them with None and bump schema_version to 0.3.0."""
    old = {
        "schema_version": "0.1.0",
        "system": {
            "source": {"type": "user_supplied", "topology": "t.parm7",
                       "coordinates": "t.rst7", "pdb_id": None},
            "n_atoms_estimate": 100, "has_ligand": False,
            "solvent": {"model": "TIP3P", "ions_NaCl_mM": 0.0},
        },
        "force_field": {"protein": "amber14sb", "water": "TIP3P",
                        "ligand": "user_supplied"},
        "protocol": [{"kind": "minimize", "max_iterations": 100,
                      "tolerance_kj_mol_nm": 10.0}],
        "observables": [],
        "provenance": {},
        "warnings": [],
        "notes": "",
    }
    out = migrate_json(json.dumps(old), target="0.3.0")
    obj = json.loads(out)
    assert obj["schema_version"] == "0.3.0"
    assert obj["system"]["source"]["ligand_smiles"] is None
    assert obj["system"]["solvent"]["membrane"] is None
    assert obj["force_field"]["lipid"] is None


def test_no_path_raises():
    bogus = json.dumps({"schema_version": "9.9.9"})
    with pytest.raises(ValueError):
        migrate_json(bogus, target="0.3.0")
