# Pitch to a chemistry PhD friend — manufacturing & procurement edition

Meeting prep for explaining Crucible to a chemistry PhD who works at a
chemistry startup on the manufacturing + procurement side. They have
deep chemistry intuition but aren't a programmer and don't write code.

The framing below avoids the "drug discovery" wedge (wrong audience)
and leans on the materials-science templates that are already shipped
(`polymer_dynamics`, `battery_electrolyte`). Companion to the in-depth
docs at [`../docs/MATERIALS_USE_CASES.md`](../docs/MATERIALS_USE_CASES.md)
and the formal pitch shapes at [`../docs/PROJECT_PITCH.md`](../docs/PROJECT_PITCH.md).

## One-liner

Crucible turns the methods section of a published molecular-dynamics
paper into a runnable simulation, with the LLM as the *extractor* —
not the author — so the physics stays the physicist's job.

## The problem, in their language

A chemist reads a paper. The methods say *"AMBER ff14SB, TIP3P water,
310 K, 1 bar, 2 fs timestep, Langevin thermostat at 1 ps⁻¹, 100 ns."*
That's a recipe. To actually run it, somebody has to translate one
paragraph of prose into ~200 lines of Python wired up to OpenMM (or
GROMACS, or NAMD). That translation step is:

- slow (a postdoc-week per paper),
- error-prone (silent failures — wrong water model gives plausible-
  looking but physically meaningless output),
- a wall between "I want to try this" and "I have data."

Naive "ask ChatGPT to write the script" makes the error problem
worse — the LLM hallucinates parameters (ff14SB vs ff19SB, TIP3P vs
TIP4P) and the simulation runs without crashing. False-pass output
is worse than no output.

## What Crucible does differently

The LLM is not allowed to write code. It can only fill in a strict
typed form (called the `MDSpec`). Every field is checked:

- enums (force field, water model, ensemble) are bound to allowlists
  — the LLM physically cannot pick a force field that doesn't exist;
- numbers carry units in the field name (`temperature_K`, `dt_fs`,
  `duration_ns`);
- every number is tagged with where it came from — `paper`,
  `paper_default`, `assumed`, or `user` — so a reviewer can see what's
  extracted vs. guessed;
- five validation gates run before any compute is spent: schema →
  semantic rules (e.g., NPT must have a barostat) → backend loadability
  → preview run → human confirm in a notebook.

Only after all five gates pass does it render the actual OpenMM Python
or Molly.jl code and hand it off to a GPU.

## Why a chemist-procurement person should care

Two shipped templates are dead-on for materials work, not biology:

- **`battery_electrolyte`** — 1 M LiPF₆ in EC, measures Li⁺ diffusion
  and coordination shell. Generalizes to LiTFSI/LiFSI/LiBOB, mixed
  solvents (EC+DMC+EMC), Na⁺/K⁺ chemistries, water-in-salt. ~12
  GPU-hours.
- **`polymer_dynamics`** — PEG-20mer in TIP3P, measures Rg + RMSD of
  the backbone. Generalizes to polyelectrolytes, drug-conjugate
  polymers, polymer gels. ~6 GPU-hours.

That maps to procurement-shaped questions: *"before we buy 50 kg of
solvent X for the pilot cell, what does its Li⁺ coordination look
like vs. solvent Y?"* or *"this monomer ratio — what's the chain
conformation distribution?"* It's not a sourcing recommender — it's
a way to pre-screen properties cheaply against the published
literature before committing money.

## Be honest about what it can't do

This is the part that earns trust. Crucible explicitly cannot handle
(and the docs say so):

- **Metals and alloys** — EAM/MEAM force fields aren't in scope. If
  the startup does metallurgy or catalyst metals, this isn't their
  tool. LAMMPS is.
- **Catalysis / reactive surfaces** — anything where bonds break or
  form. Needs ReaxFF or QM/MM.
- **Ceramics, crystalline solids, SEI formation** — Buckingham
  potentials, shell models, full strain tensors. Out of scope.
- **Polymer electrolytes beyond ~50 monomers, glassy bulk polymers,
  electrochemistry at electrode interfaces.**

It's classical organic-chemistry MD. If their pipeline is "design a
small molecule / polymer / electrolyte and simulate it in a solvent
box," yes. If it's "predict surface chemistry on a Ni catalyst," no.

## Why now — what changed

Two things converged: (a) LLMs got reliable enough to fill a strict
form (not write free-form code), and (b) OpenMM + OpenFF Sage matured
enough that small-molecule parameterization is a subprocess call
rather than a manual ordeal. The wedge is the IR — it's the contract
that makes the LLM's output *rejectable*. The line to memorize:
**the LLM doesn't write Python — it emits a typed IR with provenance,
and the validator catches the silent errors before runtime.**

## Status, honestly

v1.5, active development. 386 tests passing. Open source, MIT,
`github.com/j4qfrost/crucible`. Two real backends shipped (OpenMM +
Molly.jl), three LLM providers (cloud Anthropic, local Ollama/vLLM,
recorded for offline tests). No commercial license, no paid SaaS — a
personal project.

## Good questions to ask the friend

These do two things at once — they make the conversation about their
work, and they tell you whether Crucible is even relevant to their
startup:

1. *"What chemistries does your team actually formulate or source?
   Small organic molecules, polymers, electrolytes, or something with
   metals/surfaces?"* (Answer tells you immediately if Crucible is in
   or out of scope.)
2. *"When you're evaluating a new reagent or solvent, do you ever go
   to published MD literature for properties? How much friction is
   there between reading the paper and using the number?"* (Tests the
   wedge.)
3. *"Who at the startup — if anyone — runs molecular simulations
   today? In-house computational chemist, contracted out, or none?"*
   (Tells you what Crucible would be replacing or augmenting.)
4. *"Does the manufacturing side care about anything that needs
   reactive chemistry — catalysis, surface bonding, SEI?"* (Honest
   disqualifier check.)
5. *"Who decides whether the company adopts new tooling — and is
   open-source vs. commercial a factor?"* (If they're a Schrödinger
   / OpenEye shop, the conversation is different.)

## Two things to avoid in the meeting

- **Don't oversell the "LLM does the work" angle.** The pitch is the
  opposite — the LLM is the cheap, fallible part; the value is the
  gate that catches it lying. A chemist will respect that framing.
- **Don't pretend it crosses into synthesis, retrosynthesis, or
  supply-chain.** It's pure classical MD. If they ask "can it help me
  find a supplier for this monomer," the answer is no — it predicts
  how the monomer *behaves* in a box, not where to buy it.

## See also

- [`../docs/PROJECT_PITCH.md`](../docs/PROJECT_PITCH.md) — the
  three formal pitch lengths (60s / 5m / 30m).
- [`../docs/MATERIALS_USE_CASES.md`](../docs/MATERIALS_USE_CASES.md) —
  full materials-science scope doc; what fits, what's borderline,
  what's deferred.
- [`../docs/USE_CASES.md`](../docs/USE_CASES.md) — index across
  cancer / materials / protein-engineering.
- [`../docs/GLOSSARY.md`](../docs/GLOSSARY.md) — cross-field
  vocabulary if the conversation gets technical fast.
