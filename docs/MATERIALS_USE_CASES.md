# Materials science use cases

Crucible was built for biomolecular MD (drug discovery is the
prototypical workload — see `docs/CANCER_USE_CASES.md`). The same
classical-MD pipeline covers a meaningful slice of materials science
too — specifically, anything where the underlying force field is
"organic chemistry" (AMBER/GAFF/OpenFF). This doc is honest about
what fits, what's borderline, and what's deferred.

> **Honest scope.** "Materials science" is a much wider field than
> "biomolecular MD." This page covers what Crucible's IR + force-field
> allowlist support today. Several important materials regimes
> (metals, catalysis, ceramics) need force-field families Crucible
> doesn't ship and would require new IR axes; those are noted at the
> end of the page.

## What fits today

| Template | Question it answers | Typical compute |
|---|---|---|
| `polymer_dynamics` | What's the Rg / end-to-end / chain conformation distribution? | 1 GPU × ~6 hours |
| `battery_electrolyte` | What's the Li⁺ self-diffusion + coordination shell? | 1 GPU × ~12 hours |

Both use `:user_supplied` source — for materials systems with multiple
species in non-protein contexts, the user pre-builds the box (PACKMOL,
CHARMM-GUI, Moltemplate) and points Crucible at the resulting
topology + coordinates.

```bash
crucible templates init polymer_dynamics    --out spec.json
crucible templates init battery_electrolyte --out spec.json
```

## 1. Polymer dynamics — chain conformation in solvent

**Reference system**: PEG-20mer in 5 nm cubic TIP3P water box (~2,800
atoms). PEG (polyethylene glycol) is the canonical "well-studied
polymer in MD" — used in drug delivery, membrane research,
hydrogels, surface passivation.

**What the template does**:

1. Loads pre-built topology + coordinates (you build it externally).
2. Minimization → 0.5 ns NVT → 1 ns NPT equilibration with no
   restraints (the chain needs to relax).
3. **20 ns NPT production** observing:
   - Trajectory (every 20 ps)
   - Radius of gyration (Rg) of the polymer backbone
   - RMSD of the polymer backbone

**Use this when**: you have a polymer system pre-built and want to
sample chain conformations. Generalizes to:

- Polyacrylic acid / PAA at varying pH
- Polyelectrolytes in salt (add `ions_NaCl_mM`)
- Drug-conjugate polymers (PEG-drug) — combines with the cancer
  templates' protein side
- Polymer gels (cross-linked → user-supplied topology with the
  cross-links baked in)

**Don't use this for**:

- Glassy/amorphous bulk polymers (need orders of magnitude longer
  simulations + specialized cooling protocols).
- Crystalline polymer phases (need anisotropic NPT + sometimes
  specialized FFs).
- Reactive polymers (bond breaking/forming → ReaxFF or QM/MM, both
  out of Crucible's scope).

**Caveats**:

- 20 ns is a starter. Rg convergence for high-MW chains often needs
  100+ ns. Bump `duration_ns` of the production stage.
- OpenFF Sage 2.2.0 handles short oligomers fine. Long chains
  (>50 monomers) need block-by-block parameterization that
  OpenFFParameterizer doesn't do automatically — pre-build the
  topology with a polymer tool (e.g., `polymer-builder`,
  `pysimm`).
- Very long polymers (>200 monomers) need polymer-specialized
  force fields (TraPPE, MARTINI 3 with polymer extensions). Out of
  scope.

## 2. Battery electrolyte — Li⁺ diffusion and coordination

**Reference system**: 1 M LiPF₆ in ethylene carbonate (EC), built as
~10 EC molecules per 1 LiPF₆ pair (≈ 4,500 atoms). Standard
"first-generation" lithium-ion battery electrolyte chemistry.

**What the template does**:

1. Loads pre-built topology + coordinates from PACKMOL.
2. 2 ns NPT equilibration to relax the box at 1 atm.
3. **50 ns NVT production** at 300 K observing:
   - Trajectory at 10 ps stride (good for MSD analysis with
     post-processing)
   - RMSD of Li⁺ ions (used as a sanity check; the real diffusion
     analysis is MSD which the trajectory enables)
   - Li⁺ ↔ EC carbonyl oxygen distance (coordination shell)

**Why NVT for production?** Once the box density has equilibrated in
NPT, NVT is preferred for transport-property calculation (diffusion
coefficient): NPT's volume fluctuations bias short-time MSD.

**Use this when**: you have a battery-relevant ion-solvent system
pre-built and want diffusion + coordination data. Generalizes to:

- LiTFSI, LiFSI, LiBOB salts (swap PF₆⁻ for the alternate anion)
- Mixed solvents (EC + DMC + EMC; PACKMOL with multiple species)
- Higher concentrations (3 M, "water-in-salt" electrolytes)
- Sodium- or potassium-ion electrolytes (Na⁺/K⁺ instead of Li⁺)

**Don't use this for**:

- Solid Electrolyte Interphase (SEI) formation (needs reactive FFs;
  ReaxFF is the standard tool).
- Polymer electrolytes (PEO + LiTFSI etc.) — combine the
  `polymer_dynamics` shape with electrolyte content + a longer
  production run.
- Solid-state electrolytes (LLZO, sulfides) — ionic conductors with
  specialized force fields (Buckingham + shell models, often).
- Electrochemistry at electrode interfaces (charge transfer needs
  QM, surface needs metal FFs).

**Caveats**:

- 1 fs timestep with h_bonds constraints is conservative. Some
  electrolyte papers use 0.5 fs without constraints for safety;
  others use 2 fs aggressively. Match your published reference if
  you're chasing literature numbers.
- 50 ns is the lower bound for Li⁺ diffusion convergence
  (D ≈ 10⁻¹⁰ m²/s in EC means ~5 nm net displacement per 50 ns).
  Production papers run 200+ ns or use multiple replicates.
- The OpenFF Sage / GAFF2 parameter quality for ions is OK but not
  great. For publication-quality work, polarizable FFs (AMOEBA) or
  hand-tuned OPLS variants are sometimes preferred — out of scope
  for Crucible's allowlist today.
- Distance observable selectors (`resname LI and name LI`,
  `resname EC and name O3`) match a PACKMOL build convention. Adjust
  the residue + atom names to match whatever the topology actually
  uses.

## What's deferred (out of scope today)

Crucible's IR + force-field allowlist doesn't currently support these
materials regimes. They'd need new IR axes or new FF families. None
are scaffolded — the path forward is "ML potentials" (which already
beat AMBER for some of these) rather than adding bespoke FF families.

### Metals and alloys

EAM (Embedded Atom Method) and MEAM force fields are the standard
for metals + alloys. Used for dislocation dynamics, grain-boundary
behavior, fracture, phase transitions. Crucible's allowlist is
organic-chemistry FFs — adding EAM/MEAM is non-trivial because
the Hamiltonian shape is different (many-body embedding terms).

**Workaround today**: not really. If you're doing metal MD, use
LAMMPS directly. The same `crucible doctor` story works for LAMMPS
in principle (subprocess shell-out, same pattern as our OpenMM
path), but the IR doesn't have a "metal system" representation.

### Catalysis and reactive surfaces

Reactive bond-making/breaking needs ReaxFF or QM/MM. ReaxFF is one
specialized force-field family; QM/MM is per-paper. Both out of
scope today.

**Track**: ML potentials trained on quantum chemistry (ANI, MACE,
Allegro) are starting to beat ReaxFF for some catalysis problems.
When they do consistently, Crucible adds them to `LIGAND_FF_ALLOWLIST`
using the v2 IR scaffolding pattern (see `docs/QUANTUM_OUTLOOK.md` +
`musings/quantum_outlook_eli5.md`).

### Crystalline solids and ceramics

Buckingham potentials, shell models, anisotropic NPT with full strain
tensor — these need an IR for general crystalline NPT (the
membrane-NPT path is a special case but not generalized).

**Workaround today**: rigid lattice MD on organic crystals (drug
co-crystals, organic semiconductors) works in Crucible if you supply
a frozen-position topology. Anything dynamic in the lattice needs
out-of-scope FFs.

### Coarse-grained materials beyond Martini

Martini is in the IR (v2 scaffolding, renderer raises). DPD
(Dissipative Particle Dynamics), Lennard-Jones-only models for
generic soft matter, and bead-spring polymer models all need new
runtime hooks. No scaffolding.

## Recommended workflow

Same as the cancer-MD path:

```bash
# 1. Confirm tooling
crucible doctor

# 2. Pick a starter
crucible templates init polymer_dynamics --out spec.json
crucible fmt spec.json --in-place

# 3. Edit: replace topology + coordinates with your PACKMOL build,
#    adjust observable selectors to match your topology's residue +
#    atom names, set duration to your target.

# 4. Triage
crucible health spec.json

# 5. Cost
crucible advise spec.json --budget-hours 24

# 6. Run
crucible run spec.json --workdir runs/$(date +%Y%m%d) \
    --seed 42 --precision mixed

# 7. Analyze
crucible analyze runs/<date> --format markdown
crucible plot runs/<date>

# 8. Pack + share
crucible snapshot runs/<date> --out my-result.tar.gz
```

For diffusion + transport properties specifically, the post-run
analysis is *not* what `crucible analyze` produces (that gives you
mean / min / max). MSD analysis needs `mdtraj.compute_msd` or similar
— do that separately on the trajectory artifacts.

## See also

- `docs/CANCER_USE_CASES.md` — the biomolecular flagship use case;
  the templates use the same shapes (FEP, REMD, membrane).
- `examples/protein_ligand_fep.jl` — generic ligand-binding FEP
  template; the kinase template extends it.
- `musings/why_ir_as_contract.md` — why we ship templates (JSON
  shapes) instead of bash scripts.
- `musings/quantum_outlook_eli5.md` — the ML-potentials lane that
  will eventually expand Crucible's reach into materials regimes
  it doesn't cover today.
