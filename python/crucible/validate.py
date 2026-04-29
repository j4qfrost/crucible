"""Validation gates 1 + 2 — Python port of `src/validation/Gates.jl`.

Gate 1 — JSON Schema (canonical schema.json, identical to the Julia side).
Gate 2 — semantic Julia rules ported one-for-one.
Gate 3 — backend loadability — only available via the Julia CLI bridge.
Gate 4 — preview run — only available via the Julia CLI bridge.

Pipeline contract: gates run sequentially; if N fails, N+1 does not run.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from importlib.resources import files
from pathlib import Path
from typing import Any

import jsonschema

from .spec import (
    CG_PROTEIN_FF,
    DynamicsStage,
    FEPStage,
    MDSpec,
    MetadynamicsStage,
    REMDStage,
)


@dataclass
class ValidationReport:
    ok: bool = True
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def add_error(self, msg: str) -> None:
        self.errors.append(msg)
        self.ok = False

    def add_warning(self, msg: str) -> None:
        self.warnings.append(msg)

    def merge(self, other: "ValidationReport") -> "ValidationReport":
        return ValidationReport(
            ok=self.ok and other.ok,
            errors=[*self.errors, *other.errors],
            warnings=[*self.warnings, *other.warnings],
        )


# -----------------------------------------------------------------------------
# Schema loading — the canonical schema.json is the cross-language contract.

_SCHEMA_CACHE: dict[str, Any] | None = None


def _schema_path() -> Path:
    """Resolve schema.json. Order:
       1. packaged data file (when installed via pip)
       2. dev tree at python/../src/spec/schema.json (when installed -e)
    """
    try:
        ref = files("crucible").joinpath("_data/schema.json")
        if ref.is_file():
            return Path(str(ref))
    except (ModuleNotFoundError, FileNotFoundError):
        pass
    here = Path(__file__).resolve().parent
    return here.parent.parent / "src" / "spec" / "schema.json"


def _load_schema() -> dict:
    global _SCHEMA_CACHE
    if _SCHEMA_CACHE is None:
        with _schema_path().open("r") as fh:
            _SCHEMA_CACHE = json.load(fh)
    return _SCHEMA_CACHE


# -----------------------------------------------------------------------------
# Gate 1 — JSON Schema

def gate_schema(spec_json: str) -> ValidationReport:
    r = ValidationReport()
    try:
        obj = json.loads(spec_json)
    except json.JSONDecodeError as exc:
        r.add_error(f"could not parse spec JSON: {exc}")
        return r
    try:
        jsonschema.validate(obj, _load_schema())
    except jsonschema.ValidationError as exc:
        r.add_error(_humanize_schema_error(exc))
    return r


def _humanize_schema_error(exc: jsonschema.ValidationError) -> str:
    path = "/".join(str(p) for p in exc.absolute_path) or "<root>"
    if exc.validator == "enum":
        return f"schema error at {path}: value {exc.instance!r} is not one of {exc.validator_value}"
    if exc.validator == "required":
        return f"schema error at {path}: required field is missing or null ({exc.message})"
    if exc.validator == "additionalProperties":
        return f"schema error at {path}: unknown field (additional properties not allowed at this level)"
    return f"schema error at {path}: {exc.message}"


# -----------------------------------------------------------------------------
# Gate 2 — Semantic rules
#
# One function per rule, mirror-named to the Julia side. Order is preserved
# for reproducibility of the (errors, warnings) sequence across languages.

def gate_semantic(spec: MDSpec) -> ValidationReport:
    r = ValidationReport()
    for rule in (
        _rule_npt_requires_barostat,
        _rule_constraints_timestep,
        _rule_implicit_solvent_no_barostat,
        _rule_production_after_equilibration,
        _rule_ligand_topology_required,
        _rule_temperature_sane,
        _rule_npt_pressure_required,
        _rule_vacuum_no_ions,
        _rule_langevin_friction_nonzero,
        _rule_nve_timestep,
        _rule_smiles_source_coherence,
        _rule_fep_lambda_monotonic,
        _rule_remd_ladder_monotonic,
        _rule_metadynamics_cv_atoms,
        _rule_membrane_coherence,
        _rule_protonation_coherence,
        _rule_coarse_grain_coherence,
    ):
        rule(spec, r)
    return r


def _rule_npt_requires_barostat(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, DynamicsStage) and s.ensemble == "NPT" and s.barostat is None:
            r.add_error(f"stage {i}: NPT ensemble requires a barostat (got nothing)")


def _rule_constraints_timestep(spec: MDSpec, r: ValidationReport) -> None:
    is_cg = spec.force_field.protein in CG_PROTEIN_FF
    cap_fs = 30.0 if is_cg else 5.0
    for i, s in enumerate(spec.protocol, start=1):
        if not isinstance(s, DynamicsStage):
            continue
        if not is_cg and s.constraints == "none" and s.dt_fs > 1.0:
            r.add_warning(
                f"stage {i}: dt={s.dt_fs} fs without constraints risks integrator "
                f"instability; consider :h_bonds"
            )
        if not is_cg and s.constraints in ("h_bonds", "all_bonds") and s.dt_fs > 4.0:
            r.add_warning(f"stage {i}: dt={s.dt_fs} fs is aggressive even with constraints")
        if s.dt_fs > cap_fs:
            r.add_error(f"stage {i}: dt={s.dt_fs} fs exceeds the {cap_fs} fs hard cap")


def _rule_implicit_solvent_no_barostat(spec: MDSpec, r: ValidationReport) -> None:
    if spec.system.solvent.model != "implicit_GBSA":
        return
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, DynamicsStage) and s.ensemble == "NPT":
            r.add_error(
                f"stage {i}: NPT is incoherent with implicit solvent (no volume to vary)"
            )


def _rule_production_after_equilibration(spec: MDSpec, r: ValidationReport) -> None:
    seen_eq = False
    for i, s in enumerate(spec.protocol, start=1):
        if not isinstance(s, DynamicsStage):
            continue
        if s.role == "equilibrate":
            seen_eq = True
        elif s.role == "production" and not seen_eq:
            r.add_warning(
                f"stage {i}: production stage has no preceding equilibration; "
                f"results may be biased by initial conditions"
            )


def _rule_ligand_topology_required(spec: MDSpec, r: ValidationReport) -> None:
    src = spec.system.source
    if src.type in ("smiles", "protein_ligand"):
        return
    if (
        spec.system.has_ligand
        and spec.force_field.ligand == "user_supplied"
        and src.topology is None
    ):
        r.add_error(
            "system has a ligand and ligand_ff=user_supplied, but system.source.topology "
            "is null. Either supply a topology, or switch source.type to :smiles / "
            ":protein_ligand and force_field.ligand to :openff_sage_2_2_0."
        )


def _rule_temperature_sane(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if not isinstance(s, DynamicsStage):
            continue
        if s.temperature_K < 50:
            r.add_warning(
                f"stage {i}: temperature={s.temperature_K} K is below the typical "
                f"biological range; verify this is intentional"
            )
        elif s.temperature_K > 500:
            r.add_warning(
                f"stage {i}: temperature={s.temperature_K} K is high; verify this "
                f"is intentional (REMD?)"
            )


def _rule_npt_pressure_required(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, DynamicsStage) and s.ensemble == "NPT" and s.pressure_bar is None:
            r.add_error(f"stage {i}: NPT ensemble requires pressure_bar to be set")


def _rule_vacuum_no_ions(spec: MDSpec, r: ValidationReport) -> None:
    if spec.system.solvent.model == "vacuum" and spec.system.solvent.ions_NaCl_mM > 0:
        r.add_error(
            f"system.solvent: ions_NaCl_mM={spec.system.solvent.ions_NaCl_mM} is "
            f"incoherent with model=:vacuum (no medium for ion concentration)"
        )


def _rule_langevin_friction_nonzero(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if (
            isinstance(s, DynamicsStage)
            and s.thermostat == "langevin"
            and s.friction_ps == 0
        ):
            r.add_warning(
                f"stage {i}: langevin thermostat with friction_ps=0 is degenerate "
                f"(no coupling); consider 1.0 ps^-1"
            )


def _rule_nve_timestep(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, DynamicsStage) and s.ensemble == "NVE" and s.dt_fs > 1.0:
            r.add_warning(
                f"stage {i}: dt={s.dt_fs} fs in NVE ensemble risks energy drift; "
                f"production NVE typically uses 0.5-1.0 fs"
            )


def _rule_smiles_source_coherence(spec: MDSpec, r: ValidationReport) -> None:
    src = spec.system.source
    if src.type not in ("smiles", "protein_ligand"):
        return
    if not src.ligand_smiles:
        r.add_error(
            f"system.source.type={src.type} requires a non-empty ligand_smiles"
        )
    if spec.force_field.ligand == "user_supplied":
        r.add_error(
            f"system.source.type={src.type} requires force_field.ligand to be a real "
            f"parameterizer (e.g. :openff_sage_2_2_0); :user_supplied is incoherent here"
        )
    if src.type == "protein_ligand" and (src.pdb_id is None or len(src.pdb_id) < 4):
        r.add_error("system.source.type=:protein_ligand requires a 4-character pdb_id")


def _rule_fep_lambda_monotonic(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if not isinstance(s, FEPStage):
            continue
        L = s.lambda_windows
        if len(L) < 2:
            r.add_error(f"stage {i}: FEP requires ≥2 lambda windows (got {len(L)})")
            continue
        if L[0] != 0.0 or L[-1] != 1.0:
            r.add_warning(
                f"stage {i}: FEP lambda windows should bracket [0.0, 1.0]; "
                f"got [{L[0]}, {L[-1]}]"
            )
        for k in range(1, len(L)):
            if L[k] <= L[k - 1]:
                r.add_error(
                    f"stage {i}: FEP lambda windows must be strictly monotonic; "
                    f"window {k}→{k+1} drops or repeats"
                )
                break
        if any(λ < 0.0 or λ > 1.0 for λ in L):
            r.add_error(f"stage {i}: FEP lambda values must lie in [0, 1]")
        if s.ensemble == "NPT" and s.pressure_bar is None:
            r.add_error(f"stage {i}: FEP NPT ensemble requires pressure_bar to be set")


def _rule_remd_ladder_monotonic(spec: MDSpec, r: ValidationReport) -> None:
    for i, s in enumerate(spec.protocol, start=1):
        if not isinstance(s, REMDStage):
            continue
        T = s.temperature_ladder_K
        if len(T) < 2:
            r.add_error(f"stage {i}: REMD requires ≥2 temperatures (got {len(T)})")
            continue
        for k in range(1, len(T)):
            if T[k] <= T[k - 1]:
                r.add_error(
                    f"stage {i}: REMD temperature_ladder_K must be strictly increasing; "
                    f"rung {k}→{k+1} drops or repeats"
                )
                break
        if any(t < 50 or t > 1000 for t in T):
            r.add_warning(
                f"stage {i}: REMD ladder includes temperatures outside the typical "
                f"50–1000 K range"
            )
        if s.ensemble == "NPT" and s.pressure_bar is None:
            r.add_error(f"stage {i}: REMD NPT ensemble requires pressure_bar to be set")
        for k in range(1, len(T)):
            ratio = T[k] / T[k - 1]
            if ratio > 1.3:
                r.add_warning(
                    f"stage {i}: REMD rung {k}→{k+1} has T-ratio {ratio:.2f}x (>1.3); "
                    f"exchange acceptance likely low for systems above ~5k atoms"
                )
                break


def _rule_metadynamics_cv_atoms(spec: MDSpec, r: ValidationReport) -> None:
    cv_atoms = {"distance": 2, "angle": 3, "dihedral": 4}
    for i, s in enumerate(spec.protocol, start=1):
        if not isinstance(s, MetadynamicsStage):
            continue
        if not s.cvs:
            r.add_error(f"stage {i}: metadynamics requires ≥1 collective variable")
            continue
        for j, cv in enumerate(s.cvs, start=1):
            if cv.kind == "rmsd" and not cv.reference:
                r.add_error(
                    f"stage {i}: metadynamics CV[{j}] kind=:rmsd requires a "
                    f"reference PDB path"
                )
            if cv.kind in cv_atoms:
                ngroups = cv.selection.count(",") + 1
                if ngroups != cv_atoms[cv.kind]:
                    r.add_warning(
                        f"stage {i}: metadynamics CV[{j}] kind=:{cv.kind} typically "
                        f"needs {cv_atoms[cv.kind]} atom groups in selection (got "
                        f"selection with {ngroups} comma-separated entries)"
                    )
        if s.well_tempered and s.bias_factor <= 1.0:
            r.add_error(
                f"stage {i}: well_tempered=true requires bias_factor > 1.0 "
                f"(got {s.bias_factor})"
            )
        if s.ensemble == "NPT" and s.pressure_bar is None:
            r.add_error(f"stage {i}: metadynamics NPT ensemble requires pressure_bar")


def _rule_membrane_coherence(spec: MDSpec, r: ValidationReport) -> None:
    mem = spec.system.solvent.membrane
    if mem is None:
        return
    if spec.force_field.lipid is None:
        r.add_error(
            "system.solvent.membrane is set but force_field.lipid is null — pick one "
            "of (:charmm36_lipid, :lipid21, :slipids)"
        )
    if spec.system.solvent.model in ("vacuum", "implicit_GBSA"):
        r.add_error(
            f"membrane systems require explicit water (TIP3P / TIP4P_EW / SPC_E); "
            f"got solvent.model=:{spec.system.solvent.model}"
        )
    if mem.composition == "mixed_POPC_chol" and mem.chol_mol_fraction <= 0:
        r.add_error(
            "system.solvent.membrane.composition=:mixed_POPC_chol requires "
            "chol_mol_fraction > 0"
        )
    if mem.composition != "mixed_POPC_chol" and mem.chol_mol_fraction > 0:
        r.add_warning(
            f"system.solvent.membrane.chol_mol_fraction={mem.chol_mol_fraction} is "
            f"ignored when composition={mem.composition}; switch to :mixed_POPC_chol "
            f"to honor it"
        )
    for i, s in enumerate(spec.protocol, start=1):
        if (
            isinstance(s, DynamicsStage)
            and s.role == "production"
            and s.ensemble == "NVT"
        ):
            r.add_warning(
                f"stage {i}: production NVT in a membrane system is unusual; "
                f"membranes typically run NPT with anisotropic coupling to relax "
                f"box dimensions"
            )
            break


def _rule_protonation_coherence(spec: MDSpec, r: ValidationReport) -> None:
    p = spec.system.protonation
    if p is None:
        return
    if not p.titrating_residues:
        r.add_error(
            "system.protonation set but titrating_residues is empty — list at least "
            "one selector (e.g. [\"resname HIS\", \"resid 35\"])"
        )
    if spec.system.solvent.model in ("vacuum", "implicit_GBSA"):
        r.add_warning(
            f"constant-pH MD with solvent.model=:{spec.system.solvent.model}; the "
            f"standard openmm-constph implementation assumes explicit water — verify "
            f"your reference impl"
        )
    if spec.system.solvent.membrane is not None:
        r.add_warning(
            "constant-pH MD + membrane bilayer is unsupported by openmm-constph and "
            "would require a custom integrator"
        )


def _rule_coarse_grain_coherence(spec: MDSpec, r: ValidationReport) -> None:
    if spec.force_field.protein not in CG_PROTEIN_FF:
        return
    if spec.system.solvent.model in ("TIP3P", "TIP4P_EW", "SPC_E"):
        r.add_error(
            f"force_field.protein=:{spec.force_field.protein} is coarse-grained; "
            f"atomistic water model :{spec.system.solvent.model} is incoherent. "
            f"Use :vacuum for Martini (Martini's polarizable water is supplied by "
            f"the topology)"
        )
    if spec.force_field.lipid is not None:
        r.add_warning(
            f"Martini protein FF + atomistic lipid FF {spec.force_field.lipid} is "
            f"unusual; Martini bilayers are typically supplied as user_supplied topology"
        )
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, DynamicsStage) and s.dt_fs < 10.0:
            r.add_warning(
                f"stage {i}: Martini typically uses 20–25 fs timesteps; got "
                f"{s.dt_fs} fs (coarse-grained dynamics are stable at much larger "
                f"steps than atomistic)"
            )
            break


# -----------------------------------------------------------------------------
# Composed pipeline (gates 1+2; gate 3 lives behind cli_bridge.py)

def run_validation(spec: MDSpec, *, spec_json: str | None = None) -> ValidationReport:
    """Run gates 1 + 2. If gate 1 fails, gate 2 does not run."""
    if spec_json is None:
        spec_json = spec.to_json()
    r1 = gate_schema(spec_json)
    if not r1.ok:
        return r1
    r2 = gate_semantic(spec)
    return r1.merge(r2)
