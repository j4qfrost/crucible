# Why I'm not adding a quantum backend (with terms + analogies)

Companion piece to `docs/QUANTUM_OUTLOOK.md`. Same conclusions, but
this version uses the actual jargon — `qubit`, `VQE`, `Trotterization`,
`fault-tolerant`, etc. — and bottoms out with a glossary that maps
each term to a concrete analogy. If a word looks foreign, it's
defined at the end. The point is to make you *literate in the field's
vocabulary*, not to hide it.

Aimed at someone who's read a headline like "quantum will revolutionize
drug discovery" and wants to know whether to take it seriously.

## What crucible actually does

Crucible runs **molecular dynamics** (MD) — a physics simulation where
each atom is a ball, bonds are springs, and we let Newton's equations
play out for a few nanoseconds while a protein bobs around in water
with a candidate drug molecule. The output tells you whether the drug
sticks. The expensive part is throughput: a useful run is ~10⁹
timesteps × 30 000 atoms × ~150 bytes/atom on a GPU, and you want it
to finish overnight.

The energy each atom feels at each step is supplied by a **force
field** — a parameterized stand-in for the true many-electron
quantum-mechanical Hamiltonian. The standard ones (AMBER, CHARMM,
OPLS) are accurate to ~1 kcal/mol on equilibrium properties, which
happens to be roughly the noise floor of binding-affinity wet-lab
measurements. So MD is "classical balls and springs whose parameters
were derived from quantum chemistry once and then frozen."

## The three things "quantum simulation of molecules" can mean

These are different research programs with different maturity, and
people conflate them constantly when pitching investors.

### 1. Ground-state electronic structure (VQE / QPE)

**Goal:** given a molecule, compute the lowest eigenvalue (ground-state
energy) of its electronic **Hamiltonian** — the operator whose
eigenvalues are the allowed total energies of the electrons.

**Methods on quantum hardware:**

- **Variational Quantum Eigensolver (VQE):** prepare a parameterized
  trial wavefunction (an **ansatz**) on the quantum chip, measure
  ⟨H⟩, hand the number to a classical optimizer that twiddles the
  parameters, repeat until ⟨H⟩ stops dropping. Tolerant of noise; the
  go-to method for **NISQ** (noisy near-term) hardware.
- **Quantum Phase Estimation (QPE):** Trotterize `e^(-iHt)`, run it on
  the chip, read off the eigenphase via the phase-kickback trick.
  Asymptotically much better than VQE but needs **fault-tolerant**
  qubits (with **surface-code** error correction, ~1000 physical
  qubits per logical qubit).

**Status:** H₂ (4 qubits, 2 electrons) was solved in 2014. ~30
electrons on noisy hardware in 2024. The classical gold standard,
**CCSD(T)**, scales as O(N⁷) and starts running out of steam around
50 electrons; that's where quantum hardware would buy us something
real, and that's a 2028+ horizon.

**Relevance to crucible:** indirect. Better ground-state energies for
small organic molecules → better **partial charges** (today computed
classically via **AM1-BCC**) → better ligand parameters. But for
binding-affinity MD, the partial-charge accuracy is already adequate
relative to wet-lab noise. We'd notice the upgrade for transition
states and reaction barriers, not for equilibrium binding.

### 2. Trotterized real-time dynamics

**Goal:** evolve a many-particle wavefunction `|ψ(t)⟩ = e^(-iHt)|ψ(0)⟩`
on quantum hardware. This is *true* quantum dynamics — the electrons
and nuclei evolving as a quantum object, no classical approximation.

**Method:** **Trotter–Suzuki decomposition** breaks `e^(-iHt)` into
small steps of `e^(-iH_kΔt)` for each Hamiltonian piece (kinetic,
Coulomb, …). Newer methods like **qubitization** and **LCU** (linear
combinations of unitaries) hit better asymptotics but need fault-
tolerance.

**Status:** Reiher et al. (2017) estimated **~few million logical
qubits** to simulate the FeMoco active site for one timestep. Babbush
et al. (2018, 2024) shaved orders of magnitude off this; we're now in
the "few hundred logical qubits, ~10⁶ T-gates per Trotter step"
regime. Today's hardware is hundreds of *physical* qubits with
gate-error rates that put fault-tolerance years away.

**Relevance to crucible:** **near zero.** The asymptotic argument
that quantum computers can simulate `e^(-iHt)` exponentially faster
than classical ones is real but only matters when the system is
classically intractable. Crucible's systems aren't intractable —
they're polynomial-time-easy (parameterized force fields don't have
exponential entanglement) and bottlenecked by raw GPU throughput.
Even a perfect fault-tolerant computer can't help here; you'd
spend more time loading the classical state in and out of the
quantum device than Trotterizing it.

### 3. Quantum-enhanced sampling

**Goal:** speed up Monte Carlo sampling from rough energy landscapes
(protein folding, REMD trajectories, alchemical FEP windows).

**Methods:** quantum-enhanced **Boltzmann sampling**, quantum
Hamiltonian descent, quantum walks on configuration space. D-Wave's
quantum-annealing platform fits here too.

**Status:** speculative for chemistry. Demonstrations on Ising-like
toy models are real. A 2024 D-Wave protein-folding lattice-model
paper got cited a lot but doesn't transfer to atomistic simulations.
**No production tool, no clear path to one in 5 years.**

**Relevance to crucible:** if quantum samplers ever achieve a
provable speedup on Boltzmann-style sampling at chemical scales,
REMD becomes quantum-accelerated. Crucible already has the IR for
REMD (`REMDStage`); we'd add a `:quantum_sampler` ensemble or
similar. Don't hold breath.

## Why classical wins for biological MD specifically

A quick table comparing where quantum has an asymptotic win:

| Algorithm | Classical cost | Quantum cost | Crossover |
|---|---|---|---|
| Ground-state E (FCI / CCSD(T)) | O(exp(N)) or O(N⁷) | O(poly(N)) | ~50 electrons |
| Real-time `e^(-iHt)` evolution | O(exp(N)) | O(poly(N)) | ~30 qubits FT |
| Boltzmann sampling | O(τ_autocorr × N) | conjectured O(√…) | unknown |
| **Newtonian MD on parameterized FF** | **O(N log N)** | **same or worse** | **never** |

Crucible's workload is the last row. There is **no exponential
problem to give quantum a foothold.** The MD step is already
classical-polynomial; the bottleneck is GPU clock cycles, not
algorithmic complexity. Plugging quantum into the integration
loop adds overhead with zero asymptotic benefit.

The genuinely quantum-mechanical part of biology is hidden inside the
classical force field — every time we say "this O atom has partial
charge -0.83 e," we're using a number that was computed once with
quantum chemistry. **Quantum computers help fill in better numbers.
They don't replace MD.**

## The wormhole-truck analogy

Imagine you run a delivery business. Someone offers you a fancy new
vehicle that travels through wormholes.

1. The wormhole vehicle is a city block in size and costs more per
   minute than a Boeing 747 to operate.
2. It only goes to specific destinations — places with the right
   exotic-matter substrate. Most of your routes don't qualify.
3. The destinations you actually need to deliver to are reachable in
   a few hours by your existing trucks.

Keep the trucks. Keep a tiny "watch and wait" budget for if and when
wormhole tech matures and the destination list expands.

## What this means for crucible

**Don't add a quantum SystemSource or QuantumBackend.** There's no
runtime to render to. Pre-emptive scaffolding (the way we did for
constph + Martini, where the runtime *exists* but is academic-stage)
would be cargo-cult here.

**Do leave the door open via `LigandParameterizer`.** Crucible
already abstracts "compute force-field parameters for a ligand" into
a swappable interface — today implemented by `OpenFFParameterizer`
(SMILES → AM1-BCC charges + Sage typing). A future
`QuantumParameterizer` would have the same shape:

- inputs: SMILES, output directory
- backend: VQE on real hardware or an emulator (Qiskit, PennyLane)
- output: `ligand.parm7 / ligand.rst7` — same format
  `OpenMMBackend` already loads

The rest of crucible doesn't change. Five gates still apply. The
script the renderer emits doesn't change a byte. Only the source of
the parameters changes. **This is the right shape, and it's small —
~300 lines of Julia plus a Python helper.** Don't ship it now;
document that it's the intended extension point for when a vendor
publishes a binding-relevant result on real hardware (~2028+).

## The thing that's *actually* the next leap

**Machine-learning potentials (MLPs)** like `ANI-2x`, `MACE`,
`Allegro`. These are neural networks trained on millions of
quantum-chemistry calculations done classically (yes, on existing
HPC clusters, no quantum hardware needed). At inference time, they
predict atomic forces with near-CCSD(T) accuracy at near-classical
cost. *Already real, already production-grade, already deployed by
the OpenMM-ML and TorchMD-Net communities.*

When MLPs reach the point where they consistently beat AMBER/CHARMM
on protein–ligand binding ΔG (close, not quite there for the
trickier systems), crucible should add `:ani2x`, `:mace`,
`:allegro` to `LIGAND_FF_ALLOWLIST` using the same v2-IR-scaffolding
pattern we used for constph and Martini. **This is the lane to
watch hard. It's the realistic 2026–2028 leap, and it doesn't need
a single qubit.**

## TL;DR

- **2026:** Run classical MD on a GPU. Crucible already does this.
- **2026–2028:** Track ML potentials. Add to the IR when they beat
  AMBER on binding ΔG.
- **2028+:** If a vendor demonstrates ligand binding on real quantum
  hardware (real chemistry, real molecule, beating CCSD(T)), build
  `QuantumParameterizer`. ~300 lines of Julia.
- **2030+:** Re-evaluate everything; update this document.

Don't buy "quantum stocks for drug discovery" hype. Do watch the
ML-potential lane.

---

## Glossary (term → analogy)

Each term is the actual jargon you'll see in papers and pitch decks,
followed by a one-paragraph plain-language analogy.

**qubit**
The basic unit of a quantum computer — a quantum bit. Where a
classical bit is a coin lying flat (heads or tails), a qubit is a
*spinning* coin: until you measure it, it's a fuzzy mix of both. The
useful part isn't the spin — it's that two qubits can be tied
together (entangled) such that observing one instantly constrains the
other. Stack enough entangled qubits and you can encode states that no
classical computer can describe with fewer than 2ⁿ numbers.

**superposition**
A qubit being "both 0 and 1 at once." Like a coin that's still
spinning. The trick of quantum algorithms is *interfering* superpositions
so the wrong answers cancel out and the right one rings loud — the
spinning coins all settle the same way.

**Hamiltonian (H)**
The operator that tells you how a quantum system's energy works. Like
a board-game rulebook: it doesn't say what the board state is, it
says how state-A relates to state-B in energy terms. The "ground
state" is the lowest-energy configuration the rulebook allows.

**ground state**
The lowest-energy arrangement of a quantum system. The bottom of the
energy bowl. For a molecule, the ground state of its electrons tells
you the molecule's binding energy, equilibrium geometry, and partial
charges — basically every "intrinsic" chemical property.

**ansatz**
A parameterized guess for the wavefunction. Like a guitar tuner where
you've decided the strings are going to be tuned to a specific chord
shape — you're just adjusting the individual peg positions to find
the in-tune version. The ansatz constrains the search space; the
optimizer just twiddles the pegs.

**VQE (Variational Quantum Eigensolver)**
"Tune the guitar to the lowest-energy note." Prepare an ansatz on the
chip, measure its energy, hand the number to a classical optimizer to
adjust the parameters, repeat. Tolerant of noise because every step
just reads a number — the wrong answer is "out of tune," not
"silent."

**QPE (Quantum Phase Estimation)**
The Stradivarius version of VQE. Doesn't tune by trial and error; it
plays a chord and *reads off* the exact frequency from how it
interferes with itself. Vastly more accurate but requires a
near-perfect chip.

**Trotterization (Trotter–Suzuki decomposition)**
Time evolution by tiny steps. Imagine you want to bake a cake but
your oven only has settings for "heat" or "stir," not "heat AND
stir." Trotterization says: heat for 1 second, stir for 1 second,
heat for 1 second … if you alternate fast enough, the result
approximates the cake you'd get if both were happening together.
Same idea for non-commuting Hamiltonian terms.

**fault-tolerant computing / surface code**
Quantum error correction. Each "logical" qubit (the perfect kind your
algorithm wants) is built out of ~1000 noisy physical qubits arranged
in a 2D grid that constantly cross-checks itself. Like RAID for
qubits — any single failure is corrected by the redundant copies.
Today's hardware can build a few logical qubits this way; we need
hundreds to thousands for production chemistry.

**NISQ (Noisy Intermediate-Scale Quantum)**
The current era — hundreds of physical qubits, error-prone, no
fault-tolerance. The "useful flashlight" stage of quantum computing.
Algorithms designed for NISQ (mostly VQE variants) deliberately
trade asymptotic optimality for noise tolerance.

**electronic structure**
The arrangement of electrons around a molecule's nuclei. The
fundamental object of quantum chemistry: get the electronic structure
right and every other chemical property follows.

**CCSD(T)**
"Coupled-cluster singles, doubles, perturbative triples." The
classical gold standard for ground-state energies of small molecules
— what every quantum-hardware paper compares against. Scales as
O(N⁷) which means doubling the molecule size makes it 128× slower;
practical limit is ~50 electrons. Where it gives up, quantum
hardware *might* take over.

**partial charge / AM1-BCC**
The little fractional electric charge each atom carries in a
molecule, used in MD to compute Coulomb forces. AM1-BCC is the
classical recipe — fast, fits about 1 kcal/mol from CCSD(T). The
target a future `QuantumParameterizer` would replace.

**Boltzmann sampling**
Drawing snapshots from a probability distribution that weights low-
energy configurations more heavily. The slot machine of statistical
mechanics: pull the lever many times, the rare wins (low-energy
states) pay out proportionally to e^(-E/kT). Hard when the energy
landscape has many deep wells separated by tall barriers — exactly
the situation in protein conformational sampling.

**ML potential (ANI / MACE / Allegro)**
A neural network trained on quantum-chemistry calculations that
predicts forces on atoms. Think "an autocomplete that learned
chemistry from a billion small calculations." At inference time it's
classical and fast; at training time it absorbed the quantum
information once. The realistic 2026 path to better-than-AMBER
accuracy without any quantum hardware.

**force field**
The set of equations + parameters that tell each atom how hard to
push on its neighbors. AMBER, CHARMM, OPLS — the "physics engine
config files" of MD. Crucible's IR pins these via allowlists so the
LLM can't invent ones that don't exist.

**ligand**
A small molecule that binds to a protein. The drug candidate, in
discovery contexts. The target of every "is this the next blockbuster
drug?" question crucible's pipeline answers.

**transition state**
The high-energy mountain pass on a chemical reaction's path. Hard for
classical force fields (which are fit to equilibrium properties) and
exactly the regime where ground-state quantum chemistry pays off.

**Trotter step / T-gate count**
The "operations per simulated second" cost. Algorithms get measured
in "we need 10⁶ T-gates per Trotter step" — that's a budget statement
about how many error-corrected operations the hardware needs to
execute before you have a useful answer.

**LCU (Linear Combinations of Unitaries) / qubitization**
The 2018+ generation of Hamiltonian-simulation algorithms that beat
plain Trotterization in asymptotic cost. Mathematical machinery.
Important for resource estimates; not something you'd touch as a
crucible user.

**Trotter resource estimate**
A back-of-the-envelope answer to "how big a quantum computer would I
need to do this calculation?" Reiher et al.'s 2017 paper gave one
for nitrogenase; the answer was "a few million logical qubits" —
which is what set the timeline expectation for the whole field.

**REMD (Replica Exchange MD)**
Already a crucible feature — run K copies of the simulation at
K different temperatures, swap them periodically. Hot replicas escape
energy wells, cold ones sample the wells finely; the swap protocol
mixes the two. The "speculative quantum-acceleration" lane (#3 above)
would be a quantum-enhanced version of this.

**fault-tolerance threshold**
The gate-error rate below which error correction becomes possible at
all (typically ~10⁻³ for the surface code). Today's hardware is
flirting with this number; once we cross it confidently, the count
of logical qubits starts growing meaningfully.
