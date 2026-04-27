# Quantum computing for molecular simulation — outlook for Crucible

A working assessment of what quantum computing offers (and doesn't offer)
for the kind of work Crucible automates: drug-discovery-grade molecular
dynamics on solvated proteins. This is not a research review; it's a
project-internal feasibility note so we know where the IR + backends
should be ready to receive a quantum target, and where the hype outruns
the hardware.

A jargon-free version of this document lives at
[`musings/quantum_outlook_eli5.md`](../musings/quantum_outlook_eli5.md)
— same conclusions, written for someone who hasn't followed the
quantum-hardware story and just wants to know whether to take the
"quantum will revolutionize drug discovery" headlines seriously.

Last reviewed: 2026-04-27. Treat this as a snapshot — quantum hardware
roadmaps move on a 12–24 month cycle, and the state of the art listed
here will be partly obsolete by 2027.

## TL;DR

- **Crucible's actual workload (classical MD on 10⁴–10⁶ atom solvated
  systems for nanoseconds-to-microseconds) is *not* a target for quantum
  computers in any reasonable horizon.** The asymptotic advantage is
  zero — these are classical Newtonian dynamics on classically tractable
  Hamiltonians, and the bottleneck is *throughput* (ns/day), not
  *accuracy*. Quantum hardware is many orders of magnitude slower per
  step.
- **The genuinely quantum-advantaged regime is electronic-structure
  computation on small molecules** — typically <50 atoms, where you want
  ground-state energies, excitation spectra, or accurate transition-
  state geometries. This is "quantum chemistry," not MD.
- **The realistic crucible-adjacent integration** is to use quantum
  hardware (or quantum-emulator software) to compute *force-field
  parameters* for ligands or non-standard residues, then hand the
  resulting parameters to a classical MD engine. Crucible's IR already
  has a stage for this: `OpenFFParameterizer`. A future
  `QuantumParameterizer <: LigandParameterizer` is a natural extension.
- **Direct quantum simulation of dynamics** (Trotterized Hamiltonian
  evolution of a many-particle wavefunction) is asymptotically powerful
  but practically limited to ~10–100 qubit systems on noisy hardware.
  No biological-scale system fits in any plausible roadmap before 2040.

## What "quantum simulation of molecules" actually means

The phrase covers at least three distinct things, with very different
maturity levels and very different relevance to drug discovery.

### 1. Quantum chemistry ground-state computation

**Goal:** find E₀ for a molecule's electronic Hamiltonian, more
accurately than classical CCSD(T), at a cost that doesn't scale as
factorial-N.

**Methods:** Variational Quantum Eigensolver (VQE), Quantum Phase
Estimation (QPE), iterative qubit coupled-cluster.

**Status:** mature in the toy-system sense. H₂ in 4 qubits has been
done since 2014. Up to ~50-electron systems on simulators with hardware
demonstrations on ~30 noisy qubits. Microsoft, IBM, Google, AWS have
all published variants.

**Hardware needs:** 100–10⁴ logical qubits (depending on basis set +
electron count). Today's hardware is in the 100–1000 *physical* qubit
range with error rates that demand surface-code overhead of ~1000:1 —
so a few logical qubits are realistic in 2026, more in 2030.

**Relevance to crucible:** indirect. A high-accuracy ground-state
energy gets you a better small-molecule force-field parameterization
(partial charges, conformer energies) — but the OpenFF + AM1-BCC path
we already use is *adequate* for protein-ligand binding ΔG to ~1
kcal/mol, which is the noise floor of the experimental measurements
anyway. Quantum chemistry only helps when you're doing reaction
thermodynamics or transition-state hunting, not equilibrium MD.

### 2. Trotterized real-time dynamics

**Goal:** simulate `|ψ(t)⟩ = e^(-iHt)|ψ(0)⟩` for a molecular
Hamiltonian. This is genuinely quantum dynamics — wavefunctions
evolving, not classical trajectories.

**Methods:** Trotter–Suzuki decomposition, qDRIFT, qubitization,
LCU (linear combinations of unitaries).

**Status:** active research. Reiher et al. (2017) estimated a few
million logical qubits to simulate the FeMoco active site for
nitrogenase — at the edge of feasibility. Babbush et al. (2018,
2024) reduced this to ~10⁶ T-gates per Trotter step on a few
hundred logical qubits. Still way out of reach.

**Hardware needs:** millions of physical qubits with sub-10⁻³
gate-error rates for fault-tolerant operation. The 2030s at best.

**Relevance to crucible:** **near-zero for biological MD.** The
quantum systems we'd want to simulate this way are tiny: a single
peptide dihedral with explicit electrons, a metal–ligand bond
during a reaction. These are the "small but interesting"
Hamiltonians. They're *not* the 30k-atom solvated proteins
crucible orchestrates.

### 3. Quantum-classical hybrid sampling

**Goal:** use quantum hardware as a sampler for classical Monte
Carlo or as a preconditioner for variational ansätze in
classically-hard distributions.

**Methods:** Quantum-enhanced Monte Carlo (QEMC), quantum-Hamiltonian
descent, quantum Boltzmann machines.

**Status:** speculative for chemistry. Demonstrations on Ising-like
toy problems exist; nothing biologically scaled. A 2024 D-Wave
result on protein-folding lattice models is a curiosity, not a
production tool.

**Relevance to crucible:** very speculative. If quantum samplers
ever achieve a polynomial speedup on rough-energy-landscape
Boltzmann sampling, REMD might become quantum-accelerated. The
required mapping is non-obvious and probably 10+ years out.

## Asymptotic vs. actual: why classical wins for biological MD

Quantum advantages are **asymptotic**. Specifically:

| Algorithm | Classical cost | Quantum cost | Crossover |
|---|---|---|---|
| Ground-state energy | O(exp(N)) (FCI) or O(N⁷) (CCSD(T)) | O(poly(N)) (QPE) | ~50 electrons |
| Real-time dynamics | O(exp(N)) | O(poly(N)) | ~30 qubits if FT, much higher if NISQ |
| Boltzmann sampling | O(autocorrelation × N) | conjectured O(√...) | unknown |

Classical MD is *not* on this list because **classical MD is already
classical-polynomial.** Newton's equations on parameterized force
fields are O(N²) per step (or O(N log N) with PME). A 30k-atom
system on an A100 finishes 100 ns in a few hours. Adding quantum to
the integration loop offers no asymptotic advantage and a massive
constant-factor penalty: every step would need to ferry the entire
state in/out of the quantum device.

The genuinely quantum-hard part of biology is **the underlying
electronic Hamiltonian we're force-fielding away.** When we use
amber14sb, we're approximating the true molecular Hamiltonian by a
sum of bonded + nonbonded classical terms with empirically fit
parameters. Quantum chemistry can give us *better parameters*. It
cannot replace the MD step itself, because the MD step doesn't need
replacing — it needs faster GPUs.

## What this means for Crucible

### Stay where we are for the IR + render path

Don't add a `:quantum` SystemSource type or a `QuantumBackend
<: SimBackend` until there's a credible runtime to render against.
The constph + Martini scaffolding work is justified because their
runtimes (`openmm-constph`, `martinize2`) exist; quantum equivalents
do not.

Pre-emptively scaffolding a quantum backend would be cargo-cult work.

### One genuinely useful axis: a `QuantumParameterizer`

The `LigandParameterizer` abstraction is already there. A future
`QuantumParameterizer` could wrap:

- a quantum-emulator backend (Qiskit, Cirq, PennyLane) for testing
- a real cloud quantum provider (IBM Quantum, AWS Braket, Azure
  Quantum) for ground-state energies + AM1-BCC-replacement charges
- a hybrid VQE/CCSD(T) sandwich that uses the quantum result only
  when the system is small enough for it to matter

The output would be the same `ParameterizedLigand` shape. Crucible's
five gates wouldn't change. The script the OpenMMBackend renders
wouldn't change. Only the source of `ligand.parm7` would change.

This is the *right* shape for a quantum extension, and it's small —
~300 LOC plus a mocked test fixture. We don't need to ship it now.
Documenting that it's the intended extension point is enough.

### Things to ignore even if a vendor email pitches them

- **"Drug discovery on quantum"** marketing. Translate it: "quantum
  chemistry on small ligand fragments, then classical docking
  downstream." That's already a pipeline; the quantum step replaces
  CCSD(T) at the parameterization stage, not the MD stage.
- **"Quantum molecular dynamics"** for solvated proteins. Asymptotic
  argument fails; constant factors are catastrophic. Trotterizing
  100k atoms × 10⁹ steps would take longer than the universe even
  with a perfect fault-tolerant computer.
- **"Quantum-enhanced REMD"**. Conceivable but ~10 years out and
  the mapping is unobvious. If the user asks, we say "not in
  Crucible's roadmap; ask again in 2030."

### Things worth tracking

- **Cleve-style early-stopping QPE** for ligand ground-state
  energies — most likely first practical application, ~2028 timeline.
- **AlphaFold-style ML potentials trained on quantum chemistry
  data** — not quantum-on-runtime, but quantum-on-training. ANI,
  MACE, Allegro are already real and could replace classical force
  fields for small molecules without any quantum hardware at
  inference time. **This is more impactful for crucible's domain
  than direct quantum hardware ever will be.** Track this lane
  hard.
- **Hybrid CASSCF/MM** — embed a quantum-treated active site
  inside a classical-treated environment. Crucible's IR could
  represent this with a `QMRegion` field on `SystemSpec`. Worth
  scaffolding *if* `openmm-ml` or `psi4` integration becomes
  routine in the broader OpenMM ecosystem.

## Concrete crucible-side action items (ordered by usefulness)

1. **Track the ML-potential lane.** Add `:ani2x`, `:mace`,
   `:allegro` candidate values to `LIGAND_FF_ALLOWLIST` when those
   models reach production maturity. ~v2 IR scaffolding pattern,
   identical to constph + Martini. Probably the next non-classical
   FF the IR should know about.
2. **Document the `QuantumParameterizer` extension point** in
   `AGENTS.md` so future contributors don't re-debate the
   architecture when the moment arrives.
3. **Don't ship a quantum backend.** No matching runtime, no
   training data, no user demand at the molecular-dynamics scale.

## References

- McArdle et al., "Quantum computational chemistry," Rev. Mod.
  Phys. 92, 015003 (2020). The standard review.
- Reiher et al., "Elucidating reaction mechanisms on quantum
  computers," PNAS 114(29) 7555–7560 (2017). The famous FeMoco
  resource estimate.
- Babbush et al., "Encoding electronic spectra in quantum
  circuits with linear T complexity," Phys. Rev. X 8, 041015
  (2018). Order-of-magnitude reductions in QPE cost.
- Lee et al., "Even more efficient quantum computations of
  chemistry through tensor hypercontraction," PRX Quantum 2,
  030305 (2021). Best current asymptotic for ground-state QPE.
- Smith et al., "ANI-1ccx and ANI-1x data sets, coupled-cluster
  and density functional theory properties for molecules,"
  Sci. Data 7, 134 (2020). The ML-potential training-data lane
  Crucible should care about more than direct quantum hardware.
- Kirsopp et al., "Quantum computational quantification of
  protein–ligand interactions," Int. J. Quantum Chem. 122, 22 (2022).
  Honest assessment of where the quantum/MD interface actually is.

## Document maintenance

This file is reviewed quarterly during the project's `audit-transcripts
+ outlook` step. Bump the "Last reviewed" line and update the table of
algorithm crossovers when the hardware roadmap meaningfully shifts. If
a real `QuantumParameterizer` becomes feasible (typically signaled by
IBM/Google publishing a small-molecule binding-energy result that beats
CCSD(T) on real hardware), promote action item #1 from "track" to
"implement" and start scaffolding.
