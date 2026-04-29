"""Template registry tests."""

from __future__ import annotations

import pytest

from crucible import templates


EXPECTED = {
    "vanilla", "smiles", "protein_ligand_fep", "remd", "membrane",
    "metadynamics", "kinase_inhibitor_fep", "bcl2_ppi_inhibitor",
    "gpcr_oncogene_membrane", "polymer_dynamics", "battery_electrolyte",
    "enzyme_design_remd", "antibody_paratope_fep",
}


def test_list_templates_matches_julia():
    """All 13 templates from the Julia registry are present."""
    assert set(templates.list_templates()) == EXPECTED


def test_list_is_sorted():
    assert templates.list_templates() == sorted(templates.list_templates())


def test_unknown_template_raises():
    with pytest.raises(KeyError):
        templates.init("not_a_real_template")


def test_init_returns_fresh_instance():
    a = templates.init("vanilla")
    b = templates.init("vanilla")
    assert a == b
    # Mutation of one should not affect the other.
    a2 = a.model_copy(update={"notes": "changed"})
    assert b.notes != "changed"


def test_kinase_template_is_protein_ligand():
    spec = templates.init("kinase_inhibitor_fep")
    assert spec.system.source.type == "protein_ligand"
    assert spec.system.source.pdb_id == "2HYY"
    assert spec.force_field.ligand == "openff_sage_2_2_0"


def test_battery_template_uses_vacuum():
    spec = templates.init("battery_electrolyte")
    assert spec.system.solvent.model == "vacuum"
    assert spec.system.solvent.ions_NaCl_mM == 0.0


def test_remd_template_has_8_replicas():
    spec = templates.init("remd")
    remd = [s for s in spec.protocol if s.kind == "remd"][0]
    assert len(remd.temperature_ladder_K) == 8
