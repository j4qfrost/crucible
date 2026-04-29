"""MDSpec — the LLM-emitted IR. Python port of `src/spec/MDSpec.jl`.

Wire format is identical: `MDSpec.model_dump_json()` produces JSON that
the Julia `spec_from_json` loader accepts. Cross-language consistency is
the load-bearing invariant; tests pin it.

Hard rules (mirror the Julia side):
  * Every numeric field carries units in its name (`temperature_K`, `dt_fs`).
  * `provenance` is a flat dict keyed by JSONPath-ish strings.
  * Stage is a tagged union — discriminator is `kind`.
  * Schema bumps require a Migrations.py entry.
"""

from __future__ import annotations

from typing import Annotated, Literal, Optional, Union

from pydantic import BaseModel, ConfigDict, Field, model_validator

SCHEMA_VERSION = "0.3.0"

# Allowlists — never let the LLM invent FF names.
PROTEIN_FF = (
    "amber14sb", "amber99sb_ildn", "amber03",
    "charmm36m", "opls_aam",
    "martini3", "martini2_2",
)
CG_PROTEIN_FF = ("martini3", "martini2_2")
WATER_MODELS = ("TIP3P", "TIP4P_EW", "SPC_E", "implicit_GBSA", "vacuum")
LIGAND_FF = ("user_supplied", "gaff2", "openff_sage_2_2_0")
LIPID_FF = ("charmm36_lipid", "lipid21", "slipids")
LIPID_COMPOSITION = ("POPC", "POPE", "DPPC", "mixed_POPC_chol")


class _Frozen(BaseModel):
    model_config = ConfigDict(extra="forbid", validate_assignment=True)


# -----------------------------------------------------------------------------
# Provenance

class Provenance(_Frozen):
    source: Literal["paper", "paper_default", "assumed", "user", "runtime_default"]
    cite: Optional[str] = None
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


# -----------------------------------------------------------------------------
# System

class SystemSource(_Frozen):
    type: Literal["user_supplied", "pdb_id", "pdb_fetch", "smiles", "protein_ligand"]
    topology: Optional[str] = None
    coordinates: Optional[str] = None
    pdb_id: Optional[str] = None
    ligand_smiles: Optional[str] = None


class LipidBilayer(_Frozen):
    composition: Literal["POPC", "POPE", "DPPC", "mixed_POPC_chol"] = "POPC"
    n_lipids: int = Field(default=128, ge=0)
    chol_mol_fraction: float = Field(default=0.0, ge=0.0, le=0.5)


class SolventSpec(_Frozen):
    model: Literal["TIP3P", "TIP4P_EW", "SPC_E", "implicit_GBSA", "vacuum"] = "TIP3P"
    ions_NaCl_mM: float = Field(default=0.0, ge=0.0)
    membrane: Optional[LipidBilayer] = None


class ProtonationSpec(_Frozen):
    pH: float = Field(default=7.0, ge=0.0, le=14.0)
    titrating_residues: list[str] = Field(default_factory=list)
    transition_attempt_per_ps: float = Field(default=0.0, ge=0.0)
    salt_concentration_M: float = Field(default=0.15, ge=0.0)


class SystemSpec(_Frozen):
    source: SystemSource
    n_atoms_estimate: int = Field(ge=1, le=10_000_000)
    has_ligand: bool
    solvent: SolventSpec
    protonation: Optional[ProtonationSpec] = None


# -----------------------------------------------------------------------------
# Force field

class ForceFieldSpec(_Frozen):
    protein: Literal["amber14sb", "amber99sb_ildn", "amber03",
                     "charmm36m", "opls_aam",
                     "martini3", "martini2_2"] = "amber14sb"
    water: Literal["TIP3P", "TIP4P_EW", "SPC_E", "implicit_GBSA", "vacuum"] = "TIP3P"
    ligand: Literal["user_supplied", "gaff2", "openff_sage_2_2_0"] = "user_supplied"
    lipid: Optional[Literal["charmm36_lipid", "lipid21", "slipids"]] = None


# -----------------------------------------------------------------------------
# Stages (tagged union — discriminator is `kind`)

class RestraintSpec(_Frozen):
    selection: Literal["heavy_atoms", "backbone", "ca", "none"] = "none"
    kind: Literal["harmonic", "flat_bottom"] = "harmonic"
    k_kj_mol_nm2: float = Field(default=0.0, ge=0.0)


class MinimizeStage(_Frozen):
    kind: Literal["minimize"] = "minimize"
    max_iterations: int = Field(default=5000, ge=0)
    tolerance_kj_mol_nm: float = Field(default=10.0, ge=0.0)


class DynamicsStage(_Frozen):
    kind: Literal["dynamics"] = "dynamics"
    role: Literal["equilibrate", "production"]
    ensemble: Literal["NVE", "NVT", "NPT"]
    duration_ns: float = Field(ge=0.0)
    dt_fs: float = Field(default=2.0, gt=0.0)
    temperature_K: float = Field(default=300.0, ge=0.0)
    pressure_bar: Optional[float] = None
    thermostat: Literal["langevin", "nose_hoover", "andersen", "berendsen"] = "langevin"
    barostat: Optional[Literal["monte_carlo", "berendsen", "parrinello_rahman"]] = None
    friction_ps: float = Field(default=1.0, ge=0.0)
    constraints: Literal["none", "h_bonds", "all_bonds"] = "h_bonds"
    restraints: RestraintSpec = Field(default_factory=RestraintSpec)


class FEPStage(_Frozen):
    kind: Literal["free_energy"] = "free_energy"
    fep_kind: Literal["decouple", "annihilate"] = "decouple"
    target_selection: str
    lambda_windows: list[float] = Field(
        default_factory=lambda: [0.0, 0.1, 0.2, 0.3, 0.4, 0.5,
                                 0.6, 0.7, 0.8, 0.9, 1.0]
    )
    duration_per_window_ns: float = Field(default=0.5, ge=0.0)
    ensemble: Literal["NVT", "NPT"] = "NPT"
    temperature_K: float = Field(default=300.0, ge=0.0)
    pressure_bar: Optional[float] = 1.0
    dt_fs: float = Field(default=2.0, gt=0.0)
    thermostat: Literal["langevin", "nose_hoover", "andersen", "berendsen"] = "langevin"
    friction_ps: float = Field(default=1.0, ge=0.0)
    constraints: Literal["none", "h_bonds", "all_bonds"] = "h_bonds"


class REMDStage(_Frozen):
    kind: Literal["remd"] = "remd"
    temperature_ladder_K: list[float]
    duration_per_replica_ns: float = Field(default=0.5, ge=0.0)
    exchange_attempt_period_ps: float = Field(default=1.0, gt=0.0)
    ensemble: Literal["NVT", "NPT"] = "NVT"
    pressure_bar: Optional[float] = None
    dt_fs: float = Field(default=2.0, gt=0.0)
    thermostat: Literal["langevin", "nose_hoover", "andersen", "berendsen"] = "langevin"
    friction_ps: float = Field(default=1.0, ge=0.0)
    constraints: Literal["none", "h_bonds", "all_bonds"] = "h_bonds"


class CollectiveVariable(_Frozen):
    kind: Literal["distance", "angle", "dihedral", "rmsd"]
    name: str
    selection: str
    reference: Optional[str] = None
    sigma: float = Field(default=0.1, gt=0.0)


class MetadynamicsStage(_Frozen):
    kind: Literal["metadynamics"] = "metadynamics"
    cvs: list[CollectiveVariable]
    bias_height_kj_mol: float = Field(default=1.0, ge=0.0)
    bias_deposit_period_ps: float = Field(default=1.0, gt=0.0)
    duration_ns: float = Field(default=10.0, ge=0.0)
    well_tempered: bool = True
    bias_factor: float = Field(default=10.0, ge=1.0)
    ensemble: Literal["NVT", "NPT"] = "NVT"
    temperature_K: float = Field(default=300.0, ge=0.0)
    pressure_bar: Optional[float] = None
    dt_fs: float = Field(default=2.0, gt=0.0)
    thermostat: Literal["langevin", "nose_hoover", "andersen", "berendsen"] = "langevin"
    friction_ps: float = Field(default=1.0, ge=0.0)
    constraints: Literal["none", "h_bonds", "all_bonds"] = "h_bonds"


Stage = Annotated[
    Union[MinimizeStage, DynamicsStage, FEPStage, REMDStage, MetadynamicsStage],
    Field(discriminator="kind"),
]

# -----------------------------------------------------------------------------
# Observables

class Observable(_Frozen):
    type: Literal["rmsd", "rmsf", "energy", "trajectory", "rg",
                  "sasa", "distance", "hbonds"]
    selection: str = "all"
    stride_ps: float = Field(default=10.0, gt=0.0)


# -----------------------------------------------------------------------------
# Top-level MDSpec

class MDSpec(_Frozen):
    schema_version: str = SCHEMA_VERSION
    system: SystemSpec
    force_field: ForceFieldSpec
    protocol: list[Stage]
    observables: list[Observable] = Field(default_factory=list)
    provenance: dict[str, Provenance] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
    notes: str = ""

    @model_validator(mode="after")
    def _check_schema_version(self) -> "MDSpec":
        if self.schema_version != SCHEMA_VERSION:
            raise ValueError(
                f"schema_version {self.schema_version!r} != {SCHEMA_VERSION!r}; "
                f"use crucible.migrate() first"
            )
        return self

    # -------------------------------------------------------------------------
    # JSON round-trip — the load-bearing cross-language invariant.

    def to_json(self, *, indent: Optional[int] = None) -> str:
        """Wire-format JSON. The Julia loader's `spec_from_json` accepts this."""
        return self.model_dump_json(indent=indent, exclude_none=False)

    @classmethod
    def from_json(cls, text: str) -> "MDSpec":
        return cls.model_validate_json(text)

    @classmethod
    def from_dict(cls, obj: dict) -> "MDSpec":
        return cls.model_validate(obj)


# -----------------------------------------------------------------------------
# Feature derivation — used by the Router on the Julia side; useful in
# Python too for advisor / cost-estimation logic that doesn't need the CLI.

def required_features(spec: MDSpec) -> set[str]:
    feats: set[str] = set()
    if spec.system.solvent.model == "implicit_GBSA":
        feats.add("implicit_solvent")
    if spec.system.solvent.model in ("TIP3P", "TIP4P_EW", "SPC_E"):
        feats.add("explicit_solvent")
    if spec.system.solvent.membrane is not None:
        feats.update({"membrane", "anisotropic_barostat"})
    if spec.system.protonation is not None:
        feats.update({"constph", "titration"})
    if spec.system.has_ligand:
        feats.add("ligand")
    if spec.force_field.protein in CG_PROTEIN_FF:
        feats.add("coarse_grain")
    for s in spec.protocol:
        if isinstance(s, FEPStage):
            feats.add("alchemy")
            if s.ensemble == "NPT":
                feats.update({"npt", "barostat"})
        elif isinstance(s, REMDStage):
            feats.update({"remd", "multi_replica"})
            if len(s.temperature_ladder_K) >= 4:
                feats.add("multi_gpu_eligible")
            if s.ensemble == "NPT":
                feats.update({"npt", "barostat"})
        elif isinstance(s, MetadynamicsStage):
            feats.update({"metadynamics", "biased_sampling", "plumed"})
            if s.ensemble == "NPT":
                feats.update({"npt", "barostat"})
        elif isinstance(s, DynamicsStage):
            if s.ensemble == "NPT":
                feats.update({"npt", "barostat"})
            elif s.ensemble == "NVT":
                feats.add("thermostat")
            if spec.system.solvent.model in ("TIP3P", "TIP4P_EW", "SPC_E"):
                feats.add("pme")
            if s.constraints != "none":
                feats.add("constraints")
    return feats
