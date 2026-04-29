# Glossary

Cross-field vocabulary. Crucible spans biomolecular MD, drug
discovery, materials science, software engineering, and LLM tooling
— readers crossing fields land on terms that have specific meaning
in one community and a different (or no) meaning in another.

This page is the lookup. Terms are grouped by domain; cross-references
appear inline. If you find a term used in the project that's not
here and you had to Google it, that's a documentation bug — open an
issue or a PR.

## Molecular dynamics (MD)

**ensemble**
A statistical-mechanics constraint set the simulation enforces.
NVE = constant atoms, volume, energy (microcanonical, no thermostat).
NVT = constant atoms, volume, temperature (canonical, thermostatted).
NPT = constant atoms, pressure, temperature (isothermal-isobaric,
thermostatted + barostatted). Crucible's `DynamicsStage.ensemble`
is one of `:NVE`, `:NVT`, `:NPT`.

**force field**
The set of equations + parameters that tell each atom how hard to
push on its neighbors. Bond stretches, angle bends, dihedrals,
Lennard-Jones, Coulomb. Different families (AMBER, CHARMM, OPLS,
GAFF, OpenFF) have different parameter sets but the same functional
form. Crucible pins these via allowlists; see
`PROTEIN_FF_ALLOWLIST` etc. in `src/spec/MDSpec.jl`.

**timestep (`dt_fs`)**
How far the integrator advances per step, in femtoseconds.
Atomistic MD typically uses 1–2 fs (must be ~10× shorter than the
fastest bond vibration — H–X bonds at ~10 fs period). With H-bond
constraints (RATTLE/SHAKE/M-SHAKE), 4 fs is achievable. Coarse-
grained MD (Martini) uses 20–30 fs. Crucible's schema enforces
`dt_fs ≤ 5` for atomistic, `≤ 30` for CG.

**constraints**
Algorithmic freezing of selected internal coordinates so the
integrator can use a larger timestep without going unstable.
`:h_bonds` freezes only X-H bond lengths (the fastest atomistic
motion). `:all_bonds` freezes all bonds (allows slightly larger
dt). `:none` is rare for atomistic production work.

**thermostat / barostat**
Algorithms coupling the simulation to an effective heat bath
(thermostat) or pressure bath (barostat). Common thermostats:
Langevin (stochastic, simple, default in Crucible), Nosé-Hoover
(deterministic, can resonate), Andersen (rare in production).
Common barostats: Monte Carlo (default in Crucible), Berendsen
(legacy, biases distributions — avoid for production),
Parrinello-Rahman (deterministic). For membrane systems Crucible's
renderer auto-emits **MonteCarloMembraneBarostat** with semi-isotropic
coupling.

**Langevin equation**
The stochastic ODE most MD codes integrate when using a Langevin
thermostat: `m·a = F_potential − γ·m·v + R(t)` where γ is the
friction coefficient (`friction_ps`) and R is white noise. Crucible's
`DynamicsStage.friction_ps` typically defaults to 1.0 ps⁻¹.

**equilibration vs production**
A typical protocol does minimization → equilibration → production.
Equilibration relaxes the system from its initial conditions
(restraints help here); production is the part you analyze. Crucible's
`DynamicsStage.role` is `:equilibrate` or `:production`; the
semantic gates check that production stages have at least one
preceding equilibration.

**solvent model**
The explicit-water force field representing the solvent. TIP3P (3
sites, the AMBER default), TIP4P-EW (4 sites, more accurate at
high T), SPC/E (3 sites, GROMOS default). `:implicit_GBSA` is the
implicit-solvent shortcut (GBn2 in OpenMM).

**PME (Particle Mesh Ewald)**
Algorithm for long-range Coulomb interactions in periodic systems.
Required for explicit-solvent simulations. Crucible's renderer
auto-emits `nonbondedMethod=PME` when the solvent model is explicit.

**Rg (radius of gyration)**
Single-number measure of how spread-out a molecule is. Mass-weighted
RMS distance from the center of mass. Used for polymer conformation,
protein folding/unfolding signatures.

**RMSD (root-mean-square deviation)**
Distance between a snapshot's atom positions and a reference
structure's, after optimal rigid-body alignment. The standard
"is the protein moving away from its starting structure" metric.
Crucible's `:rmsd` observable computes RMSD over a selection.

**RMSF (root-mean-square fluctuation)**
Per-atom RMSD across a trajectory. Locates flexible regions. Crucible's
`:rmsf` observable computes per-atom values.

**SASA (solvent-accessible surface area)**
Surface area accessible to a probe (typically water; 1.4 Å radius).
Computed by Shrake-Rupley or Lee-Richards algorithms. Tracks
hydrophobic-core packing, binding-site exposure.

**FEP (free-energy perturbation)**
Alchemical free-energy method. Instead of directly computing
ΔG = G_bound − G_unbound (which would need infinite sampling),
FEP gradually transforms the system between two states across a
series of intermediate (`λ`) windows and integrates the
work-along-the-path. Output is `u_kln` — the energy at every λ
evaluated for samples drawn at every λ.

**REMD (replica-exchange MD)**
Enhanced-sampling method that runs multiple copies of a system at
different temperatures (or different Hamiltonians for REST2) and
periodically attempts Metropolis swaps between adjacent replicas.
Hot replicas escape energy barriers; cold replicas sample the wells
finely. Crucible's `REMDStage` ships with an exponential T-ladder
heuristic.

**metadynamics**
Enhanced-sampling method that biases the dynamics by depositing
small Gaussians on a chosen collective-variable (CV) space, gradually
filling in the free-energy landscape. Well-tempered metadynamics
adds a temperature-like factor that converges the bias.

**collective variable (CV)**
A function of atomic coordinates that captures a slow degree of
freedom — typically a distance, angle, dihedral, or RMSD to a
reference. Crucible's `MetadynamicsStage.cvs` field carries a list
of `:distance`/`:angle`/`:dihedral`/`:rmsd` CVs.

**MBAR / BAR / WHAM**
Statistical estimators for combining samples from multiple
thermodynamic states (different λ windows in FEP, different
temperatures in REMD) into a free-energy estimate. MBAR is the
modern multi-state version; pymbar is the canonical implementation.

**checkpoint**
Serialized snapshot of the simulation state (positions, velocities,
forces, RNG state, integrator step count) that lets you resume
exactly where you left off. Crucible's `CRUCIBLE_CHECKPOINT_PERIOD_PS`
+ `CRUCIBLE_RESUME_FROM` env vars plumb this through.

## Drug discovery

**ligand**
A small molecule that binds (non-covalently, usually) to a larger
biomolecule. The drug candidate, in discovery contexts.

**receptor**
The biomolecular target — typically a protein. The thing the ligand
sticks to.

**Kd, Ki, IC₅₀**
Experimentally measured binding affinities. Kd = dissociation
constant (= [L][R]/[LR] at equilibrium). Ki = inhibition constant
(roughly, Kd in inhibition contexts). IC₅₀ = concentration that
gives 50% inhibition (depends on assay conditions; not a clean
thermodynamic quantity). They're related to ΔG via
ΔG = -RT·ln(Kd).

**ΔG (binding free energy)**
Thermodynamic signature of binding. Negative = favorable. ~ -10
kcal/mol is a typical drug-like binding affinity (Kd ~ 50 nM at
310 K). Crucible's `FEPStage` is the alchemical path to predicting
ΔG.

**ΔΔG (delta-delta-G)**
Difference in ΔG between two related systems — most commonly,
between a wildtype and a mutant. ΔΔG = ΔG(mutant) − ΔG(WT).
Positive = mutation hurts binding; negative = helps. The
`antibody_paratope_fep` template is built around this.

**kinase**
Family of enzymes that transfer a phosphate group from ATP to a
substrate. Many cancer-driving mutations are in kinases (BCR-ABL
in CML, EGFR in lung cancer, BRAF in melanoma). Imatinib (Gleevec)
established kinase inhibition as a therapeutic strategy.

**GPCR (G-protein coupled receptor)**
Large family of membrane-embedded receptors. ~30% of approved drugs
target a GPCR. Many cancer-relevant ones (CXCR4 in metastasis,
S1PR2, GPR55).

**RTK (receptor tyrosine kinase)**
Membrane-embedded receptors with intracellular kinase domains.
EGFR/HER2/ALK are oncology-relevant.

**PPI (protein-protein interaction)**
Binding interfaces between two proteins. Long considered
"undruggable" because the interfaces are large + flat; Bcl-2 family
+ MDM2-p53 + KRAS-G12C have all yielded PPI inhibitors over the
past decade. Crucible's `bcl2_ppi_inhibitor` template is the
prototype.

**paratope**
The region of an antibody that contacts the antigen (the binding
surface). Mutations in paratope residues affect affinity. CDRs
(complementarity-determining regions) are the parts of the paratope
most often mutated in affinity maturation.

**affinity maturation**
The biological (or computational) process of improving an antibody's
binding affinity through mutations. Crucible's
`antibody_paratope_fep` template is for the computational version.

**pose / docking**
A specific 3D arrangement of a ligand inside a binding site
("pose"). Computational docking finds candidate poses; MD validates
or refutes them.

**allosteric site**
A binding pocket that's NOT the active site. Drugs that bind
allosteric sites can modulate enzyme activity without competing with
the natural substrate.

**Lipinski's rule of 5**
Heuristic for orally-bioavailable drugs: MW ≤ 500, logP ≤ 5, ≤ 5
H-bond donors, ≤ 10 H-bond acceptors. Calculated by RDKit, not
crucible — drug-likeness is downstream of MD.

**ADMET**
Absorption, Distribution, Metabolism, Excretion, Toxicity. The
non-binding-affinity properties a drug needs. Crucible doesn't
compute these; they're typically post-MD with cheminformatics tools.

## Materials science

**polymer**
A long chain of repeating monomer units. PEG, PEO, polyacrylic acid,
polystyrene. Crucible's `polymer_dynamics` template is for chain
dynamics in solvent.

**electrolyte**
The ion-conducting medium in a battery or capacitor. Liquid
electrolytes (LiPF₆ in EC), polymer electrolytes (PEO + LiTFSI),
solid electrolytes (LLZO, sulfides). Crucible's `battery_electrolyte`
covers the liquid case.

**SEI (Solid Electrolyte Interphase)**
The decomposition layer that forms on a Li-ion battery anode in
the first few cycles. Critical to battery longevity; modeling it
needs reactive force fields (ReaxFF) — out of Crucible's scope.

**diffusion coefficient (D)**
Statistical-mechanics quantity describing random-walk speed.
Computed from the long-time slope of the mean-squared displacement
(MSD): `D = lim_{t→∞} ⟨|r(t) − r(0)|²⟩ / 6t`. Crucible's renderer
writes the trajectory; MSD analysis happens in mdtraj or similar.

**EAM / MEAM**
Embedded Atom Method / Modified EAM. Force-field families for
metals + alloys. Many-body embedding terms not in standard MM
force fields. Out of Crucible's scope today.

**ReaxFF**
Reactive force field that allows bond formation/breaking during
MD. Used for combustion, catalysis, SEI formation. Out of Crucible's
scope.

**QM/MM**
Hybrid method: quantum-mechanical treatment of an active region
(reactive site, transition state) embedded in a classical-MM
treatment of the surroundings. Out of Crucible's scope.

**CHARMM-GUI**
Web service for building solvated/membrane-embedded biomolecular
systems. Outputs topology + coordinates files in AMBER/CHARMM/GROMACS
formats. Often the upstream of Crucible's `:user_supplied` source
type.

**PACKMOL**
Tool for packing molecules into a simulation box. Used to build
electrolyte boxes, ionic-liquid systems, polymer melts.

## Quantum chemistry / computing

**electronic structure**
Where the electrons are in a molecule. The fundamental
QM-chemistry object; ground-state geometry + energies follow from
it.

**ground state**
Lowest-energy configuration of the electrons. The basic target of
quantum chemistry.

**CCSD(T)**
Coupled-cluster singles, doubles, perturbative triples. The
classical "gold standard" for ground-state energies of small
molecules. Scales as O(N⁷); practical limit is ~50 electrons.

**DFT (Density Functional Theory)**
Mid-tier QM method that uses electron density rather than the full
many-body wavefunction. ~O(N³) scaling; standard for molecules with
~100-1000 atoms. Many functional choices (B3LYP, ωB97X-D, …).

**VQE (Variational Quantum Eigensolver)**
Near-term-quantum algorithm for ground-state energies. Tolerant of
noise. See `musings/quantum_outlook_eli5.md` for the full
treatment.

**QPE (Quantum Phase Estimation)**
Asymptotically better than VQE but needs fault-tolerant qubits.

**fault-tolerance / surface code**
Quantum error correction scheme. Each "logical" qubit is built from
~1000 noisy physical qubits in a 2D grid that constantly
cross-checks.

**ML potential (ANI / MACE / Allegro)**
Neural network trained on quantum-chemistry data; predicts forces
at near-classical-MM cost. The realistic path to better-than-AMBER
accuracy without quantum hardware. See
`musings/quantum_outlook_eli5.md`.

## LLM tooling (Crucible-relevant)

**structured output**
LLM API mode where the model is constrained to emit JSON conforming
to a schema. Anthropic's `tool_use` with `input_schema` and OpenAI's
function-calling are the canonical paths. Crucible uses this in
`AnthropicProvider`.

**provenance**
Record of where each value in a structured output came from. In
Crucible: `{source: :paper | :paper_default | :assumed | :user |
:runtime_default, cite: <citation>, confidence: <float>}` per
numeric field.

**hallucination**
LLM emitting a value that's plausible-looking but wrong. Crucible's
defense is the schema (collapses output to a finite enum/numeric
domain) plus the validation gates (semantic checks the schema
can't express).

**JSON Schema**
Structured-data validation language. Crucible's
`src/spec/schema.json` is the LLM's output contract; both
`AnthropicProvider` and `LocalProvider` pin it as `input_schema`.

**fine-tuning**
Training a base model on domain-specific data. Crucible's option-3
roadmap targets a fine-tune of a small open-weights model (e.g.,
Qwen-Coder-7B) on the JSONL transcripts the project accumulates.

**prompt engineering**
The discipline of designing the system + user messages an LLM sees.
Crucible's `TRANSPILE_SYSTEM_PROMPT` (in `src/llm/Provider.jl`)
exemplifies the pattern: enums embedded in the prompt, hard rules
called out, fallback behavior specified.

**few-shot learning**
Including example input/output pairs in the prompt. Crucible's
prompt is currently zero-shot; the templates can serve as few-shot
seeds in a future iteration.

## Crucible-internal terms

**MDSpec**
The IR (intermediate representation). The structured JSON object the
LLM emits + the renderer consumes. Defined in
`src/spec/MDSpec.jl`. The contract.

**Stage**
A unit of the MD protocol. Five subtypes: `MinimizeStage`,
`DynamicsStage`, `FEPStage`, `REMDStage`, `MetadynamicsStage`.

**SystemSource**
What the simulation system is built from. Five types:
`:user_supplied` (BYO topology), `:pdb_id` / `:pdb_fetch` (PDBFixer
auto-build), `:smiles` (OpenFF parameterizer), `:protein_ligand`
(PDBFixer + SMIRNOFFTemplateGenerator at runtime).

**five-gate validation pipeline**
Schema (Gate 1) → Semantic rules (Gate 2) → Backend loadability
(Gate 3) → Preview run (Gate 4) → User confirmation (Gate 5).
Sequential, non-skippable.

**backend**
A simulator that consumes MDSpec and produces a runnable script.
Crucible ships `MollyBackend` (Julia-native, lightweight),
`OpenMMBackend` (subprocess, the workhorse), and a `KineticsBackend`
stub.

**provider**
An LLM provider. `AnthropicProvider` (real Claude),
`LocalProvider` (OpenAI-compatible endpoint, e.g. vLLM/Ollama),
`RecordedProvider` (replays a JSON fixture, deterministic, used
in tests).

**parameterizer**
Generates force-field parameters for a small molecule from its
SMILES. `OpenFFParameterizer` shells out to a Python helper using
openff-toolkit + Interchange. The `:smiles` and `:protein_ligand`
source types invoke it.

**renderer**
Translates MDSpec to a runnable script. OpenMMBackend renders
Python; MollyBackend renders Julia. Renderers are the only code
that converts units (the IR carries units in field names like
`temperature_K`, `dt_fs`).

**transcript store**
Local DuckDB at `~/.local/share/crucible/transcripts.duckdb`.
Records every transpile session for the option-3 fine-tune
flywheel. Manipulated via `TranscriptStore` (open / log /
iter_transcripts / export_transcripts_jsonl).

**flywheel**
The data-accumulation loop: each user session logs to the
transcript store; periodically those transcripts are exported as
JSONL training pairs; eventually fine-tune a domain model on the
accumulated corpus. The IR is what makes this tractable —
`(paper_text, MDSpec_json)` pairs are deterministic, validate
against schema, diffable. See `musings/why_ir_as_contract.md`.

**v2 IR scaffolding**
Pattern for committing IR shape + validation now while deferring
the runtime to v2. Used for constant-pH MD and Martini coarse-
graining; the renderer raises with a clear remediation pointer
(install `openmm-constph`, run `martinize2`, etc.). Documented in
`AGENTS.md` and the matching musings.

**five hard rules**
Project-internal invariants that don't change without a major
revision. Listed in `AGENTS.md` § "Hard rules":
1. The LLM never invents force-field parameters.
2. The IR is the contract.
3. Renderers are the only code that converts units.
4. BYO-topology gate is scoped to `:user_supplied` source only.
5. Validation gates are sequential.

## See also

- `docs/HOW_TO_READ.md` — role-specific reading guides.
- `docs/PLAN.md` — architecture document (canonical source for
  internal terms).
- `musings/quantum_outlook_eli5.md` — has its own glossary section
  for quantum-chemistry terminology specifically.
