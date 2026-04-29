"""Canned starter MDSpecs — Python port of `src/spec/Templates.jl`.

Each builder returns a fresh, schema-valid `MDSpec`. Names match the
Julia registry one-for-one, so `crucible.templates.init("kinase_inhibitor_fep")`
yields the same starter spec the Julia CLI's `templates init` does.
"""

from __future__ import annotations

from typing import Callable

from .coverage import _enumerate_provenance_keys
from .spec import (
    CollectiveVariable,
    DynamicsStage,
    FEPStage,
    ForceFieldSpec,
    LipidBilayer,
    MDSpec,
    MetadynamicsStage,
    MinimizeStage,
    Observable,
    Provenance,
    REMDStage,
    RestraintSpec,
    SolventSpec,
    SystemSource,
    SystemSpec,
)


_TEMPLATES: dict[str, Callable[[], MDSpec]] = {}


def register(name: str, builder: Callable[[], MDSpec]) -> None:
    _TEMPLATES[name] = builder


def list_templates() -> list[str]:
    return sorted(_TEMPLATES)


def init(name: str) -> MDSpec:
    """Return a fresh, schema-valid MDSpec for `name`."""
    if name not in _TEMPLATES:
        raise KeyError(
            f"unknown template: {name}. available: {', '.join(list_templates())}"
        )
    return _TEMPLATES[name]()


def get(name: str) -> MDSpec:
    """Alias of `init(name)` matching the Julia `get_template` name."""
    return init(name)


# -----------------------------------------------------------------------------
# Builders (mechanical port; defaults mirror Julia)

def _vanilla_md() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="protein.parm7",
                                coordinates="protein.rst7"),
            n_atoms_estimate=15_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied"),
        protocol=[
            MinimizeStage(max_iterations=2000, tolerance_kj_mol_nm=10.0),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.1,
                          dt_fs=2.0, temperature_K=300.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=1000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
            DynamicsStage(role="production", ensemble="NPT", duration_ns=10.0,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=10.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=10.0),
        ],
        notes="vanilla MD template — solvated protein, AMBER14SB + TIP3P, 10 ns NPT",
    )
    return _enrich_provenance(spec, "vanilla")


def _smiles_ligand() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="smiles", ligand_smiles="CCO"),
            n_atoms_estimate=9, has_ligand=True,
            solvent=SolventSpec(model="vacuum", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="vacuum",
                                   ligand="openff_sage_2_2_0"),
        protocol=[
            MinimizeStage(max_iterations=200, tolerance_kj_mol_nm=10.0),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.01,
                          dt_fs=2.0, temperature_K=300.0),
            DynamicsStage(role="production", ensemble="NVT", duration_ns=1.0,
                          dt_fs=2.0, temperature_K=300.0),
        ],
        observables=[Observable(type="trajectory", selection="all", stride_ps=1.0)],
        notes="SMILES → MD template — replace ligand_smiles with your own SMILES",
    )
    return _enrich_provenance(spec, "smiles")


def _protein_ligand_fep() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="protein_ligand", pdb_id="1ubq",
                                ligand_smiles="Cc1ccc(cc1)O"),
            n_atoms_estimate=2_500, has_ligand=True,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="openff_sage_2_2_0"),
        protocol=[
            MinimizeStage(max_iterations=500),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.1,
                          dt_fs=2.0, temperature_K=300.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=1000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
            FEPStage(fep_kind="decouple", target_selection="resname LIG",
                     lambda_windows=[i / 10 for i in range(11)],
                     duration_per_window_ns=0.5,
                     ensemble="NPT", temperature_K=300.0, pressure_bar=1.0),
        ],
        observables=[Observable(type="trajectory", selection="all", stride_ps=10.0)],
        warnings=["FEP per-window duration is demo-scale; production needs ≥1 ns/window"],
        notes="protein-ligand alchemical FEP — replace pdb_id + ligand_smiles for your system",
    )
    return _enrich_provenance(spec, "protein_ligand_fep")


def _remd_folding() -> MDSpec:
    ladder = [300.0, 313.0, 327.0, 342.0, 358.0, 374.0, 391.0, 408.0]
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied", topology="protein.parm7",
                                coordinates="protein.rst7"),
            n_atoms_estimate=12_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied"),
        protocol=[
            MinimizeStage(max_iterations=500),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0),
            REMDStage(temperature_ladder_K=ladder,
                      duration_per_replica_ns=2.0,
                      exchange_attempt_period_ps=2.0,
                      ensemble="NVT"),
        ],
        observables=[Observable(type="trajectory", selection="all", stride_ps=10.0)],
        notes="REMD template — 8 replicas, 300–408 K exponential ladder",
    )
    return _enrich_provenance(spec, "remd")


def _membrane_protein() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="gpcr_in_popc.parm7",
                                coordinates="gpcr_in_popc.rst7"),
            n_atoms_estimate=72_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0,
                                membrane=LipidBilayer(composition="POPC",
                                                      n_lipids=200,
                                                      chol_mol_fraction=0.0)),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied", lipid="lipid21"),
        protocol=[
            MinimizeStage(max_iterations=2000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=310.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=2000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=2.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo",
                          restraints=RestraintSpec(selection="backbone",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=500.0)),
            DynamicsStage(role="production", ensemble="NPT", duration_ns=10.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=20.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=20.0),
        ],
        notes="membrane-protein template — POPC bilayer, 310 K physiological",
    )
    return _enrich_provenance(spec, "membrane")


def _kinase_inhibitor_fep() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(
                type="protein_ligand", pdb_id="2HYY",
                ligand_smiles="Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1"),
            n_atoms_estimate=45_000, has_ligand=True,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="openff_sage_2_2_0"),
        protocol=[
            MinimizeStage(max_iterations=2000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=310.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=2000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=2.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo",
                          restraints=RestraintSpec(selection="backbone",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=500.0)),
            FEPStage(fep_kind="decouple", target_selection="resname LIG",
                     lambda_windows=[i / 10 for i in range(11)],
                     duration_per_window_ns=2.0,
                     ensemble="NPT", temperature_K=310.0, pressure_bar=1.0),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=20.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=20.0),
        ],
        warnings=[
            "Imatinib SMILES is a starter — replace with your own analog for prospective work.",
            "ΔG predictions need experimental cross-check before publication.",
            "FEP per-window 2 ns is the lower bound for kinase systems; consider 5+ ns.",
        ],
        notes=(
            "Cancer use case: kinase inhibitor binding ΔG via decoupling FEP. "
            "Abl + Imatinib (PDB 2HYY) is the canonical kinase-inhibitor reference; "
            "swap pdb_id + ligand_smiles for your kinase + analog."
        ),
    )
    return _enrich_provenance(spec, "kinase_inhibitor_fep")


def _bcl2_ppi_inhibitor() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(
                type="protein_ligand", pdb_id="6O0P",
                ligand_smiles="O=C(NC1CCN(c2nc(N3CCN(C(C)=O)CC3)nc(C)c2)CC1)c1ccccc1"),
            n_atoms_estimate=38_000, has_ligand=True,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="openff_sage_2_2_0"),
        protocol=[
            MinimizeStage(max_iterations=2000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=310.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=2000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=2.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo",
                          restraints=RestraintSpec(selection="backbone",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=500.0)),
            DynamicsStage(role="production", ensemble="NPT", duration_ns=50.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=50.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=50.0),
            Observable(type="distance",
                       selection="resname LIG and name C1, protein and resid 145 and name CA",
                       stride_ps=10.0),
            Observable(type="hbonds", selection="resname LIG or protein", stride_ps=50.0),
        ],
        warnings=[
            "Venetoclax-like SMILES is a fragment, not the full drug — full Venetoclax is ~700 g/mol.",
            "Distance observable's atom indices are placeholders; pick real residue contacts.",
            "50 ns production is the minimum for PPI conformational sampling; 200+ ns is typical for a paper.",
        ],
        notes=(
            "Cancer use case: protein-protein interaction inhibitor binding stability. "
            "Bcl-2 + Venetoclax-fragment (PDB 6O0P) is a landmark targeted-cancer-therapy "
            "structure; the workflow generalizes to MDM2-p53, KRAS-G12C, etc."
        ),
    )
    return _enrich_provenance(spec, "bcl2_ppi_inhibitor")


def _gpcr_oncogene_membrane() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="cxcr4_in_popc.parm7",
                                coordinates="cxcr4_in_popc.rst7"),
            n_atoms_estimate=78_000, has_ligand=True,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0,
                                membrane=LipidBilayer(composition="POPC",
                                                      n_lipids=200,
                                                      chol_mol_fraction=0.0)),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied", lipid="lipid21"),
        protocol=[
            MinimizeStage(max_iterations=3000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=1.0,
                          dt_fs=2.0, temperature_K=310.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=2000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=5.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo",
                          restraints=RestraintSpec(selection="backbone",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=500.0)),
            DynamicsStage(role="production", ensemble="NPT", duration_ns=100.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=100.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=100.0),
            Observable(type="rmsf", selection="protein and name CA", stride_ps=100.0),
        ],
        warnings=[
            "Topology + coordinates are user-supplied: build the protein+POPC system in CHARMM-GUI or PACKMOL first.",
            "100 ns production is the lower bound for GPCR conformational sampling; receptor activation needs μs-scale.",
            "MonteCarloMembraneBarostat semi-isotropic coupling is auto-emitted by the renderer — don't override.",
        ],
        notes=(
            "Cancer use case: GPCR oncogene (e.g. CXCR4 in metastasis) embedded in POPC. "
            "Replace topology + coordinates with your CHARMM-GUI build; Crucible auto-uses "
            "MonteCarloMembraneBarostat with XYIsotropic + ZFree coupling."
        ),
    )
    return _enrich_provenance(spec, "gpcr_oncogene_membrane")


def _polymer_dynamics() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="peg20_water.parm7",
                                coordinates="peg20_water.rst7"),
            n_atoms_estimate=2_800, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="openff_sage_2_2_0"),
        protocol=[
            MinimizeStage(max_iterations=1000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=1.0,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
            DynamicsStage(role="production", ensemble="NPT", duration_ns=20.0,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=20.0),
            Observable(type="rg", selection="resname PEG or resname OEG", stride_ps=20.0),
            Observable(type="rmsd", selection="resname PEG or resname OEG", stride_ps=20.0),
        ],
        warnings=[
            "Topology + coordinates are user-supplied: build the polymer + solvent box in CHARMM-GUI Polymer Builder or PACKMOL.",
            "20 ns is a starter; polymer Rg convergence often needs 100+ ns for high-MW chains.",
            "Long chains (>50 monomers) need OpenFF block-by-block parameterization; very long polymers (>200) need polymer-specialized FFs.",
        ],
        notes=(
            "Materials use case: polymer chain in solvent for Rg / end-to-end / "
            "conformational sampling. Generalizes to PEG, polyacrylic acid, "
            "polyelectrolytes (with NaCl), drug-delivery polymers."
        ),
    )
    return _enrich_provenance(spec, "polymer_dynamics")


def _battery_electrolyte() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="lipf6_ec.parm7",
                                coordinates="lipf6_ec.rst7"),
            n_atoms_estimate=4_500, has_ligand=False,
            solvent=SolventSpec(model="vacuum", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="vacuum",
                                   ligand="openff_sage_2_2_0"),
        protocol=[
            MinimizeStage(max_iterations=1000),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=2.0,
                          dt_fs=1.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo"),
            DynamicsStage(role="production", ensemble="NVT", duration_ns=50.0,
                          dt_fs=1.0, temperature_K=300.0),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=10.0),
            Observable(type="rmsd", selection="resname LI", stride_ps=10.0),
            Observable(type="distance",
                       selection="resname LI and name LI, resname EC and name O3",
                       stride_ps=2.0),
        ],
        warnings=[
            "Topology + coordinates are user-supplied: build via PACKMOL (1 LiPF6 per ~10 EC for ~1 M).",
            "1 fs timestep + h_bonds constraints; halve dt for very high-density electrolytes.",
            "50 ns is the lower bound for Li+ diffusion convergence (D ~ 10^-10 m^2/s); 200+ ns is typical.",
            "Distance observable atom names ('LI', 'EC name O3') are PACKMOL-build conventions; adjust to match your topology.",
            "OPLS-AA or polarizable FFs (AMOEBA) are sometimes preferred over GAFF/OpenFF for ionic liquids.",
        ],
        notes=(
            "Materials use case: Li-ion battery electrolyte sampling for "
            "diffusion + coordination. LiPF6/EC is the canonical Li-ion chemistry; "
            "swap salt + solvent for LiTFSI, FSI, propylene carbonate, EMC, etc."
        ),
    )
    return _enrich_provenance(spec, "battery_electrolyte")


def _enzyme_design_remd() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="design_candidate.parm7",
                                coordinates="design_candidate.rst7"),
            n_atoms_estimate=18_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied"),
        protocol=[
            MinimizeStage(max_iterations=2000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=2000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=2.0,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          barostat="monte_carlo",
                          restraints=RestraintSpec(selection="backbone",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=500.0)),
            REMDStage(temperature_ladder_K=[300.0, 313.0, 327.0, 342.0,
                                            358.0, 374.0, 391.0, 408.0],
                      duration_per_replica_ns=5.0,
                      exchange_attempt_period_ps=2.0,
                      ensemble="NVT"),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=20.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=20.0),
            Observable(type="rmsf", selection="protein and name CA", stride_ps=20.0),
            Observable(type="rg", selection="protein and name CA", stride_ps=20.0),
        ],
        warnings=[
            "Topology is user-supplied: feed in the AlphaFold/RFdiffusion output via PDBFixer + tleap (or CHARMM-GUI).",
            "5 ns/replica is a starter; folding-stability work needs 50+ ns/replica.",
            "REMD acceptance heuristic: rung-to-rung T-ratio ≤ 1.10 keeps acceptance > 25% for ≤ 200-residue proteins.",
            "For larger designs (>300 residues), REST2 (replica exchange with solute tempering) is preferred over plain T-REMD.",
        ],
        notes=(
            "Protein engineering: enzyme design candidate stability via "
            "T-REMD. Tests whether an AlphaFold/RFdiffusion-generated "
            "structure stays folded; identifies mobile loops + "
            "metastable conformations."
        ),
    )
    return _enrich_provenance(spec, "enzyme_design_remd")


def _antibody_paratope_fep() -> MDSpec:
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied",
                                topology="fab_antigen.parm7",
                                coordinates="fab_antigen.rst7"),
            n_atoms_estimate=85_000, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=150.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied"),
        protocol=[
            MinimizeStage(max_iterations=2000),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=1.0,
                          dt_fs=2.0, temperature_K=310.0,
                          restraints=RestraintSpec(selection="heavy_atoms",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=2000.0)),
            DynamicsStage(role="equilibrate", ensemble="NPT", duration_ns=5.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          barostat="monte_carlo",
                          restraints=RestraintSpec(selection="backbone",
                                                   kind="harmonic",
                                                   k_kj_mol_nm2=500.0)),
            FEPStage(fep_kind="annihilate",
                     target_selection="resname MUT",
                     lambda_windows=[i / 10 for i in range(11)],
                     duration_per_window_ns=3.0,
                     ensemble="NPT", temperature_K=310.0, pressure_bar=1.0),
        ],
        observables=[
            Observable(type="trajectory", selection="all", stride_ps=50.0),
            Observable(type="rmsd", selection="protein and name CA", stride_ps=50.0),
            Observable(type="hbonds", selection="protein", stride_ps=50.0),
        ],
        warnings=[
            "Topology is user-supplied: build the Fab+antigen complex with the mutated residue tagged as resname MUT.",
            "Annihilation (not decoupling) is the right alchemy for protein-side mutations.",
            "Run twice: once with mutant, once with WT; ΔΔG = ΔG(mutant) - ΔG(WT). Use `crucible diff --intent` to compare specs.",
            "3 ns/window is a starter; convergent ΔΔG for protein-protein interfaces needs 5-10 ns/window plus error analysis (BAR + bootstrapping).",
        ],
        notes=(
            "Protein engineering: antibody affinity-maturation ΔΔG via "
            "annihilation FEP. Generalizes to any protein-protein "
            "interface mutation (TCR-pMHC, hormone-receptor, etc.)."
        ),
    )
    return _enrich_provenance(spec, "antibody_paratope_fep")


def _metadynamics_dihedral() -> MDSpec:
    cvs = [
        CollectiveVariable(kind="dihedral", name="phi",
                           selection="5,7,9,15", sigma=0.5),
        CollectiveVariable(kind="dihedral", name="psi",
                           selection="7,9,15,17", sigma=0.5),
    ]
    spec = MDSpec(
        system=SystemSpec(
            source=SystemSource(type="user_supplied", topology="dipeptide.parm7",
                                coordinates="dipeptide.rst7"),
            n_atoms_estimate=500, has_ligand=False,
            solvent=SolventSpec(model="TIP3P", ions_NaCl_mM=0.0),
        ),
        force_field=ForceFieldSpec(protein="amber14sb", water="TIP3P",
                                   ligand="user_supplied"),
        protocol=[
            MinimizeStage(),
            DynamicsStage(role="equilibrate", ensemble="NVT", duration_ns=0.1,
                          dt_fs=2.0, temperature_K=300.0),
            MetadynamicsStage(cvs=cvs,
                              bias_height_kj_mol=1.0,
                              bias_deposit_period_ps=2.0,
                              duration_ns=10.0, well_tempered=True,
                              bias_factor=10.0, ensemble="NVT",
                              temperature_K=300.0),
        ],
        observables=[Observable(type="trajectory", selection="all", stride_ps=10.0)],
        warnings=["selection atom indices are placeholders — replace with your dihedrals"],
        notes="metadynamics template — 2 dihedral CVs (phi/psi), well-tempered γ=10",
    )
    return _enrich_provenance(spec, "metadynamics")


# -----------------------------------------------------------------------------
# Provenance enrichment — match Julia _enrich_provenance!.

_PAPER_KEYS = {
    "temperature_K", "duration_ns", "duration_per_window_ns",
    "duration_per_replica_ns", "lambda_windows",
    "temperature_ladder_K", "pressure_bar",
}
_PAPER_DEFAULT_KEYS = {
    "n_atoms_estimate", "ions_NaCl_mM",
    "max_iterations", "n_lipids",
    "chol_mol_fraction", "k_kj_mol_nm2",
    "stride_ps",
}
_ASSUMED_KEYS = {
    "dt_fs", "friction_ps", "tolerance_kj_mol_nm",
    "exchange_attempt_period_ps", "bias_height_kj_mol",
    "bias_deposit_period_ps", "bias_factor", "sigma",
}


def _enrich_provenance(spec: MDSpec, label: str) -> MDSpec:
    paths = _enumerate_provenance_keys(spec)
    prov = dict(spec.provenance)
    prov.setdefault(
        "system.n_atoms_estimate",
        Provenance(source="user", cite=f"template: {label}", confidence=1.0),
    )
    for path in paths:
        if path in prov:
            continue
        leaf = path.rsplit(".", 1)[-1]
        if leaf in _PAPER_KEYS:
            prov[path] = Provenance(
                source="paper",
                cite=f"template: {label} — paper cites this directly",
                confidence=1.0,
            )
        elif leaf in _PAPER_DEFAULT_KEYS:
            prov[path] = Provenance(
                source="paper_default", cite=f"template: {label}",
                confidence=0.9,
            )
        elif leaf in _ASSUMED_KEYS:
            prov[path] = Provenance(
                source="assumed",
                cite=f"template: {label} — Crucible default, paper rarely states this",
                confidence=0.7,
            )
        else:
            prov[path] = Provenance(
                source="paper_default", cite=f"template: {label}",
                confidence=0.8,
            )
    return spec.model_copy(update={"provenance": prov})


# -----------------------------------------------------------------------------
# Bootstrap

register("vanilla", _vanilla_md)
register("smiles", _smiles_ligand)
register("protein_ligand_fep", _protein_ligand_fep)
register("remd", _remd_folding)
register("membrane", _membrane_protein)
register("metadynamics", _metadynamics_dihedral)
register("kinase_inhibitor_fep", _kinase_inhibitor_fep)
register("bcl2_ppi_inhibitor", _bcl2_ppi_inhibitor)
register("gpcr_oncogene_membrane", _gpcr_oncogene_membrane)
register("polymer_dynamics", _polymer_dynamics)
register("battery_electrolyte", _battery_electrolyte)
register("enzyme_design_remd", _enzyme_design_remd)
register("antibody_paratope_fep", _antibody_paratope_fep)
