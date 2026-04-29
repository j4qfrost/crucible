"""Coverage + lint tests."""

from __future__ import annotations

from crucible import (
    DynamicsStage,
    MDSpec,
    MinimizeStage,
    Observable,
    coverage_score,
    lint,
    provenance_coverage,
    templates,
)
from crucible.spec import (
    ForceFieldSpec,
    SolventSpec,
    SystemSource,
    SystemSpec,
)


def test_template_coverage_meaningful():
    spec = templates.init("vanilla")
    cov = provenance_coverage(spec)
    assert cov.total_numeric_fields > 0
    assert cov.fields_with_provenance > 0
    score = coverage_score(cov)
    assert 0.5 < score <= 1.0


def test_lint_short_production_advisory():
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied", topology="t.parm7",
                                coordinates="t.rst7"),
            n_atoms_estimate=1_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(),
        protocol=[
            MinimizeStage(),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.05),
            DynamicsStage(role="production", ensemble="NVT", duration_ns=0.1),
        ],
    )
    report = lint(spec)
    rules = {f.rule for f in report.findings}
    assert "short_production" in rules


def test_lint_no_equilibration_warn():
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied", topology="t.parm7",
                                coordinates="t.rst7"),
            n_atoms_estimate=1_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(),
        protocol=[
            MinimizeStage(),
            DynamicsStage(role="production", ensemble="NVT", duration_ns=10.0),
        ],
    )
    report = lint(spec)
    rules = {f.rule for f in report.findings}
    assert "no_equilibration" in rules


def test_lint_rmsd_without_trajectory_warn():
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied", topology="t.parm7",
                                coordinates="t.rst7"),
            n_atoms_estimate=1_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(),
        protocol=[
            MinimizeStage(),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.1),
            DynamicsStage(role="production", ensemble="NVT", duration_ns=10.0),
        ],
        observables=[Observable(type="rmsd", selection="protein and name CA")],
    )
    report = lint(spec)
    rules = {f.rule for f in report.findings}
    assert "rmsd_no_trajectory" in rules
