# Cancer research use cases

Cancer drug discovery is the prototypical molecular-dynamics workload
Crucible was built to serve. This doc walks through the three flagship
templates the project ships, what scientific question each answers,
and which to pick for a given problem. Read this if you're starting
a cancer-MD project and want to know where Crucible fits.

> **Scientific scrutiny.** The templates are starting points, not
> publication-ready protocols. Every prediction needs experimental
> cross-check, the standard provenance + lint workflow, and (for
> binding affinities) literature-validated reference compounds.
> Crucible is a pipeline, not a guarantee of correctness.

## At a glance

| Template | Question it answers | Typical compute | When to pick |
|---|---|---|---|
| `kinase_inhibitor_fep` | What's the binding ΔG of this kinase inhibitor? | 1 GPU × ~1 day, single replicate | You have a candidate kinase inhibitor + a reference structure. |
| `bcl2_ppi_inhibitor` | Does this PPI fragment stay bound under MD? Which residues mediate? | 1 GPU × ~1 day | You have an early-stage PPI fragment hit, want to triage before scale-up. |
| `gpcr_oncogene_membrane` | What conformational states does this membrane-embedded oncogene visit? | 1 GPU × ~3 days | You have a built protein-in-bilayer system + want sampling before docking. |

Each is registered in `src/spec/Templates.jl`. Generate one with:

```bash
crucible templates init kinase_inhibitor_fep --out my-spec.json
crucible templates init bcl2_ppi_inhibitor --out my-spec.json
crucible templates init gpcr_oncogene_membrane --out my-spec.json
```

## 1. Kinase inhibitor — ΔG via decoupling FEP

**Reference structure:** PDB `2HYY` (Abl kinase + Imatinib). Imatinib
(Gleevec) was the first targeted cancer drug to work clinically; this
crystal structure is the canonical kinase-inhibitor reference cited
across the field.

**What the template does**:

1. Fetches `2HYY` via PDBFixer, repairs missing residues, adds H at pH 7.
2. Parameterizes the ligand (Imatinib SMILES included as a starter)
   via OpenFF Sage 2.2.0 + AM1-BCC charges.
3. Runs minimization → 0.5 ns NVT (heavy-atom restrained) →
   2 ns NPT (backbone restrained) equilibration.
4. **Decoupling FEP** across 11 λ windows × 2 ns/window. Output is
   `fep_4_u_kln.csv` — feed it to `pymbar.MBAR` for ΔG.

**Use this when**: you have a kinase target with a known co-crystal
structure + a candidate inhibitor analog. Replace `pdb_id` and
`ligand_smiles` for your system.

**Don't use this for**: kinase mutants without crystal structures
(use `:protein_ligand` source with a homology model first), allosteric
sites (FEP needs a defined binding pose), drugs that cross the
blood-brain barrier as a primary requirement (PK is downstream of MD).

**Caveats**:

- 2 ns/λ is the lower bound for kinase systems. Production work
  typically runs 5+ ns/λ, sometimes with replica swaps for
  convergence.
- Ligand parameter quality matters. OpenFF Sage 2.2.0 is competitive
  with GAFF2 on drug-like molecules but always validate against a
  reference compound with known experimental ΔG before trusting
  predictions.
- The Hard Rule applies: Crucible never invents FF parameters. If
  the ligand has unusual chemistry (boronic acids, halogen-bond
  donors, transition metals), AM1-BCC charges may be inadequate;
  consider hand-tuning + external validation.

## 2. PPI inhibitor — binding-mode stability

**Reference structure:** PDB `6O0P` (Bcl-2 + Venetoclax-fragment).
Venetoclax (Venclexta) is the first FDA-approved BH3-mimetic — it
saved chronic lymphocytic leukemia patients who had run out of
options. Its discovery was a landmark for "undruggable" PPI targets.

**What the template does**:

1. Fetches `6O0P` via PDBFixer + parameterizes a Venetoclax-like
   fragment via OpenFF.
2. Equilibration ladder identical to the kinase template.
3. **50 ns unbiased NPT production**, observing:
   - Trajectory (every 50 ps)
   - RMSD (protein backbone)
   - Distance (ligand → key residue), placeholder atom indices
   - H-bond count

**Use this when**: you have an early-stage PPI fragment hit. The
question isn't "what's the ΔG" (FEP for PPI inhibitors is harder than
for kinase inhibitors because the binding pose is often more
ambiguous); the question is **"does this fragment stay where I
docked it, and what holds it there?"**

**Don't use this for**:

- Final ΔG predictions (50 ns NPT isn't FEP — it gives you a stability
  picture, not a free-energy number).
- Targets with cryptic binding sites that haven't been crystallized
  (the production run will show the ligand drift away — that's a
  finding, but not the one you asked the template to provide).
- Any system where the binding mode is contested (multiple plausible
  poses → run all of them, compare lifetimes).

**Caveats**:

- 50 ns is the lower bound for PPI conformational sampling. Major
  Bcl-2 / MDM2 / KRAS papers run 200+ ns or use enhanced-sampling
  methods (REMD, metadynamics — Crucible has both as separate
  templates).
- The distance observable's atom indices are placeholders. Pick
  residues that are involved in the binding interaction (literature
  + visual inspection of the crystal structure).
- Generalizes to MDM2-p53, KRAS-G12C, MCL-1, etc. — same template
  shape, swap the PDB id + ligand.

## 3. GPCR oncogene — membrane-embedded sampling

**Reference structure:** CXCR4 (PDB `4RWS` is one option) — chemokine
receptor implicated in tumor metastasis across most cancer types.
Generally: many oncogenes are GPCRs (S1PR2, GPR55, EBI2, …) or RTKs
(EGFR, HER2, ALK), and they live in the cell membrane.

**What the template does**:

1. Loads a user-supplied topology + coordinates (you build the
   protein-in-POPC system separately — typically in CHARMM-GUI's
   Membrane Builder or via PACKMOL).
2. Equilibration ladder with longer NPT (5 ns) for membrane
   relaxation.
3. **100 ns production**. Observables: trajectory, RMSD per CA,
   RMSF per CA.
4. The OpenMM renderer **auto-detects the membrane** and emits
   `MonteCarloMembraneBarostat` with `XYIsotropic, ZFree` coupling
   instead of the regular barostat. This is the physically correct
   semi-isotropic regime for bilayers.

**Use this when**: you have a CHARMM-GUI'd or PACKMOL'd
protein-in-membrane system + want unbiased sampling before docking
or computing CV-driven free-energy surfaces.

**Don't use this for**:

- Ligand binding ΔG in a membrane protein (that's a research
  problem; standard FEP protocols don't account for membrane
  partitioning correctly).
- Activation studies (G-protein coupling, β-arrestin recruitment,
  ...) — these want microsecond timescales, sometimes via REMD.

**Caveats**:

- 100 ns is the lower bound. GPCR activation transitions are
  typically observed only on μs timescales; published-quality work
  runs 1–10 μs, sometimes with metadynamics on the activation
  helix-6 angle.
- Lipid21 (Amber) is what we render. CHARMM36-lipid is also fine
  — set `force_field.lipid = :charmm36_lipid` instead.

## What's missing (defer)

- **Drug-resistance mutations.** A common cancer-MD question: "does
  the T315I mutant of Abl rescue Imatinib resistance?" Crucible's
  IR represents this fine (point mutations in user-supplied topology),
  but the `kinase_inhibitor_fep` template doesn't auto-build a mutant.
  Run two FEPs (WT + mutant), diff with `crucible diff --intent`.

- **Allosteric site discovery.** Often run as long unbiased MD
  (~μs) followed by clustering, sometimes with metadynamics on a
  geometric collective variable. Crucible's `:metadynamics` stage
  can drive this; the template would be highly application-specific.

- **Free-energy of membrane partitioning.** Replace-membrane FEP
  protocols are an active research area; no Crucible template.

- **REMD-driven kinase loop sampling.** The kinase activation loop
  flips between active (DFG-in) and inactive (DFG-out) on μs
  timescales. The `:remd` template gives the multi-replica
  scaffolding; for the specific kinase + temperature ladder, a paper
  reference is the right starting point.

## Recommended workflow

For a typical cancer-target-discovery cycle:

1. `crucible doctor` — confirm openmm, openff-toolkit, pdbfixer,
   mdtraj, openmmtools are installed.
2. `crucible templates init <name> --out spec.json` — start from
   one of the three above.
3. Edit `spec.json`: replace placeholder PDB id + SMILES + atom-index
   selections.
4. `crucible health spec.json` — gates 1-3 + lint + provenance in
   one panel. Iterate until verdict is `✓ ready`.
5. `crucible advise spec.json --budget-hours 24` — see which GPU
   class fits + cost estimate. (Note: cancer-MD systems are often
   ~50k atoms; double-check VRAM headroom in the advisor's
   warnings.)
6. `crucible run spec.json --workdir runs/$(date +%Y%m%d)
   --seed 42 --precision mixed` — render + execute.
7. `crucible analyze runs/<date> --format markdown` — observable
   summary table.
8. `crucible plot runs/<date>` — PNG plots of every CSV (needs
   matplotlib).
9. `crucible snapshot runs/<date> --out my-result.tar.gz` — packs
   the whole workdir + spec + manifest for sharing.

## Hard rules that apply to cancer-MD work specifically

- **Don't fabricate experimental data.** If the LLM transpile
  produces a binding ΔG without a citation, treat it as a hallucination.
  Crucible's provenance tracking is designed to catch this — every
  numeric field has a `source` field; `crucible cite` lists them all.
- **The renderer is the only code that converts units.** Cancer
  papers report binding affinities in IC₅₀ (μM/nM), not ΔG (kcal/mol);
  the IR refuses to mix them. Convert on entry; the IR carries
  consistent ΔG in kJ/mol.
- **Drug-likeness is downstream of MD.** Crucible doesn't compute
  Lipinski rules, ADMET predictions, or off-target screening. Pair
  with cheminformatics tooling (RDKit, ChEMBL) outside the pipeline.

## See also

- `examples/protein_ligand_fep.jl` — generic protein-ligand FEP
  walkthrough.
- `examples/membrane_protein.jl` — generic GPCR-in-bilayer
  walkthrough.
- `examples/walkthrough_v15_methods.jl` — Pluto notebook letting you
  pick any template (including the cancer ones) interactively.
- `musings/why_ir_as_contract.md` — why these templates emit JSON
  instead of running scripts directly.
