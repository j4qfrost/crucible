# Why I'm not adding a quantum backend (ELI5)

Companion piece to `docs/QUANTUM_OUTLOOK.md`. Same conclusions, no
jargon. Aimed at someone who's read a headline or two about "quantum
computers will revolutionize drug discovery" and wants to know whether
to take it seriously.

## What crucible actually does

Drug discovery means finding small molecules ("ligands") that stick to
a particular protein in your body — the receptor. Before testing a
million candidates in a wet lab, you simulate them. The simulation is
basically a video game: each atom is a tiny ball connected by springs
to its neighbors, the protein is a blob of thousands of these balls
sloshing around in a bath of water, and you let physics run for a
nanosecond or two and see what happens.

That video game is **molecular dynamics** (MD). Crucible takes a
chemistry paper, extracts "use these atoms, this temperature, these
forces, run for this long," and writes a script that runs the video
game on a GPU. That's the whole product.

## What people mean when they say "quantum computer"

A regular computer stores information as bits — each bit is either 0
or 1. A quantum computer stores it as **qubits** — each qubit can be
in a fuzzy mix of 0 and 1 at the same time, until you look at it.

This sounds magical. The honest version: it's only useful for very
specific problems where the answer comes from interfering many fuzzy
states with each other. Most everyday computing problems are NOT in
that bucket.

Three things that *are* in the bucket and that people sometimes call
"quantum simulation of molecules":

### 1. Figuring out what a molecule's energy actually is

If you take a small molecule — say, ten atoms — and ask "what's the
lowest-energy way for the electrons to arrange themselves around the
nuclei?", that's a problem regular computers struggle with. The
electrons interact with each other in a way that gets exponentially
harder as you add more electrons. Above ~30 electrons the answer
becomes unreachable on classical machines using the most accurate
methods.

Quantum computers can in principle solve this much faster. **This
works in tiny demos today and is real research, not vaporware.**
Hydrogen molecule (H₂, 2 electrons): solved on a quantum computer in
2014. A molecule with ~30 electrons: at the edge of what 2026 hardware
can do, with a lot of error correction.

This matters for drug discovery, but **not for the simulation step.**
It matters for the step *before* the simulation — figuring out how
much each individual atom of the drug should pull on its neighbors.
Once you have those numbers, you write them down once and use them
forever. The MD video game itself doesn't need quantum.

### 2. Watching the molecule actually move (in true quantum time)

You could ask: instead of approximating the molecule as balls and
springs, why not simulate the *real* quantum-mechanical evolution of
all the electrons and nuclei moving in real time?

The answer: in principle, on a quantum computer, you could. In
practice, the most-cited 2017 estimate said you'd need millions of
nearly-perfect qubits to simulate the active site of *one* enzyme.
We have hundreds of imperfect qubits today. The gap is roughly
"useful flashlight" vs "death star," and not in a way that gets
closed by a few iterations of Moore's law — these are different
physics regimes.

For a drug discovery simulation, you typically have **30,000 atoms**
sloshing in water for **a billion timesteps**. Each atom has dozens
of electrons. There is no quantum computer in any plausible decade
that can do this directly. There probably never will be one, because
the asymptotic argument doesn't even help here — the problem isn't
"hard for classical computers," it's "easy for classical computers
that just need to run faster GPUs." Quantum computers offer zero
advantage on a problem that classical computers already handle in
polynomial time.

### 3. Better random-number generation for sampling

If you're trying to find the lowest-energy shape of a protein, you
sample many shapes and pick the best. There's a class of problems
where quantum computers might sample *smarter* than classical ones.
This is genuinely speculative for chemistry — D-Wave has a result on
toy lattice models that gets cited a lot but doesn't translate to
real proteins. **File under "watch in 5–10 years, don't plan for."**

## The quick analogy

Imagine you run a delivery business and someone offers you a fancy
new vehicle that travels through wormholes. Sounds amazing.

But:

1. The wormhole vehicle is the size of a city block, and it costs more
   to operate than a Boeing 747.
2. It can only go to specific destinations that you mostly don't
   actually need to deliver to.
3. The destinations you DO need to deliver to are reachable by your
   existing trucks in a few hours.

You should keep the trucks. You should also have a tiny budget for
"if and when the wormhole tech matures and applies to my routes,
which destinations would I add to my map?" That's the right amount
of attention.

## What this means for crucible specifically

I'm not adding a quantum backend.

The IR (the structured spec the LLM emits) doesn't need a quantum
field, because there's no quantum runtime to render to. Adding a
"placeholder for the future" backend would be cargo-cult — the same
thing as adding "warp drive" to the engine list of a car-rental app
because eventually one might exist.

But there IS one real extension point I'm leaving documented:
crucible already has a `LigandParameterizer` abstraction for the
"figure out the springs" step. Today that's `OpenFFParameterizer`,
which uses standard chemistry. In ~2028, when small-molecule ground-
state energies on real quantum hardware become competitive, someone
could write a `QuantumParameterizer` that drops in. Same shape, same
output (a `.parm7` file), the rest of crucible doesn't change.

Until then: don't worry about it.

## The thing that's *actually* happening that crucible should pay attention to

Quantum computing for drug discovery is currently a 2030+ story.

The 2026 story for "doing better than classical springs-and-balls" is
**machine-learning potentials**. These are neural networks trained on
quantum-chemistry calculations done classically (yes, on classical
machines). At inference time they predict atomic forces with
near-quantum-accuracy at near-classical-cost. They're called things
like ANI, MACE, Allegro.

This is the same ROI the quantum-people are promising, but it works
right now, runs on a 2026 GPU, and doesn't need a building full of
liquid helium. When ML potentials reach the point where they beat
classical force fields for protein–ligand binding (close, not quite
there for binding ΔG), I'll add them to crucible's force-field
allowlist. That's the next thing to track.

## TL;DR for the wallet

- **2026:** Use classical MD on a GPU. (This is what crucible does.)
- **2026–2030:** Track ML potentials. Add them to the IR when they
  beat AMBER for binding free energies.
- **2028+:** If a vendor demonstrates ligand binding on a real
  quantum chip, build the `QuantumParameterizer` extension. Whole
  thing is ~300 lines of Julia + a Python helper.
- **2030+:** Re-evaluate everything above; update this document.

Don't buy quantum-stocks-for-drug-discovery hype. Do, however, keep an
eye on the trained-ML-potential lane — that's where the next leap in
biological simulation is coming from, and it doesn't need a single
qubit.
