# Crucible — one-page handout

*For a chemist evaluating whether this tool is relevant to their work.
Print or read on a phone in two minutes.*

## What it is

Crucible turns the methods section of a published molecular-dynamics
paper into a runnable simulation. The LLM extracts the protocol; it
does not write the code. A typed intermediate representation
(`MDSpec`) and five validation gates catch the silent errors before
any GPU time is spent.

The line: **the LLM doesn't write Python — it emits a typed IR with
provenance, and the validator catches the silent errors before
runtime.**

## What it does for materials chemistry

Two shipped templates relevant to electrolyte, polymer, and
formulation work:

- **`battery_electrolyte`** — Li⁺ diffusion + coordination shell in a
  carbonate solvent. Generalizes to LiTFSI / LiFSI / LiBOB, mixed
  solvents (EC + DMC + EMC), Na⁺ and K⁺ chemistries, water-in-salt.
  ~12 GPU-hours per run.
- **`polymer_dynamics`** — Rg + RMSD of a polymer backbone in
  solvent. Generalizes to polyelectrolytes, drug-conjugate polymers,
  polymer gels. ~6 GPU-hours per run.

Both are pre-screening tools: you can compare two solvents or two
monomer ratios cheaply against the literature *before* committing to
sourcing or scale-up.

## What it can't do

Honest disqualifiers — if any of these is your problem, this isn't
your tool:

- Metals and alloys (EAM/MEAM) — use LAMMPS.
- Catalysis and reactive surfaces (bond-making / breaking) — needs
  ReaxFF or QM/MM.
- SEI formation, ceramics, crystalline solids — out of scope.
- Electrochemistry at electrode interfaces — needs charge transfer,
  not covered.
- Retrosynthesis, sourcing, supply-chain — wrong tool entirely. This
  predicts how molecules *behave* in a box, not where to buy them.

It is classical organic-chemistry MD. Small molecules, polymers,
electrolytes, in a solvent box. That's the box.

## Status

- v1.5, active development. 386 tests passing.
- Open source, MIT.
- Two simulation backends: OpenMM (Python; the workhorse) and
  Molly.jl (native Julia; small-system / autodiff sweet spot).
- Three LLM providers: cloud Anthropic, local OpenAI-compatible
  (Ollama / vLLM / llama.cpp), recorded for offline tests.
- No paid SaaS, no telemetry, no auto-update phone-home.

## Links

- Code + docs: <https://github.com/j4qfrost/crucible>
- Materials use cases (full scope, what's in and what's deferred):
  [`docs/MATERIALS_USE_CASES.md`](../docs/MATERIALS_USE_CASES.md)
- Three formal pitch lengths (60s / 5m / 30m):
  [`docs/PROJECT_PITCH.md`](../docs/PROJECT_PITCH.md)
- Glossary (cross-field vocabulary):
  [`docs/GLOSSARY.md`](../docs/GLOSSARY.md)

## The two-question relevance check

If you answer yes to both, it's worth a closer look:

1. Does any part of your formulation work involve small organic
   molecules, polymers, or electrolytes in a solvent box?
2. Do you ever go to published MD literature for property values, and
   is the gap between "I read the paper" and "I have the number"
   non-trivial?

If the answer to either is no, this probably isn't your tool — and
that's a useful answer too.
