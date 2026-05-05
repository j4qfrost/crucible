# Project pitch — three lengths

Three pitches at three lengths. Pick the one that matches the time
the listener has. They're stand-alone (you don't need to read the
60s before the 5m); they're consistent (no contradictions, no
mismatched framings).

Usage:

- **60 seconds** — elevator, conference hallway, cold-email opening.
  Verbatim if needed.
- **5 minutes** — dinner-conversation, ACS-COMP poster session,
  podcast intro.
- **30 minutes** — boardroom / sponsor-meeting / academic-seminar
  intro slide deck.

All three end at the same place: *here's what you do next*.

---

## The 60-second pitch

> **Crucible turns a published MD paper into a runnable simulation
> script.** The trick: the LLM doesn't write Python. It emits a
> typed intermediate representation — every protein force field,
> every water model, every timestep is enum-typed, and every
> numeric carries its source (paper / paper-default / assumed).
> Five validation gates catch the silent errors LLMs make on MD —
> missing barostat, non-monotonic FEP windows, NPT-without-pressure
> — before any GPU time is allocated.
>
> The renderer emits OpenMM scripts you can hand to your cluster,
> or Molly.jl in-process for autodiff. On-prem mode (Ollama or
> vLLM) keeps your unpublished protocols inside your network.
>
> Open source, Apache 2.0, github.com/j4qfrost/crucible. The
> hallucination benchmark is published; you can verify the
> accuracy claims yourself.

The wedge sentence (memorize this if nothing else): *"the LLM
doesn't write Python — it emits a typed IR with provenance, and
the validator catches the silent errors before runtime."*

---

## The 5-minute pitch

### Problem

Reproducing molecular-dynamics simulations from published papers is
hard for two reasons:

1. **Methods sections are human-readable but not machine-runnable.**
   "We used AMBER ff14SB with TIP3P water at 310 K and 1 bar" needs
   to be turned into ~200 lines of OpenMM Python by hand.
2. **Naive "LLM writes the script" produces silently-wrong code.**
   Wrong force field name (ff14SB vs ff19SB), wrong water model
   (TIP3P vs TIP4P), missing barostat under NPT — all things the
   LLM will hallucinate; all things that don't crash but produce
   physically-meaningless results.

A senior comp-chem PI in our salt-mines panel review put it: *"a
false-pass validator is worse than no validator."* The wedge for
Crucible isn't "LLM writes simulations"; it's "LLM extractions are
trustworthy because we made them rejectable."

### Solution

The IR-as-contract design:

1. **Typed intermediate representation.** The LLM emits JSON
   matching a strict JSON Schema. Every enum (force field, water
   model, ensemble, integrator) is bound to an allowlist; every
   numeric carries units in its name (`temperature_K`, `dt_fs`).
2. **Provenance per field.** Every numeric is tagged `paper`,
   `paper_default`, `assumed`, or `user`. Reviewers see what the
   LLM extracted vs. what it guessed.
3. **Five validation gates.** Schema → semantic rules → backend
   loadability → preview run → user confirm. Failure of any gate
   blocks downstream.
4. **Renderer is the only unit converter.** No upstream layer
   touches units. The IR is in the natural unit of the field;
   the renderer converts to whatever OpenMM / Molly / GROMACS
   wants.

### Today

- **Two backends shipped:** OpenMM (Python subprocess; the
  workhorse) and Molly.jl (native Julia; the autodiff /
  small-system / coarse-grained sweet spot).
- **Two LLM providers:** Anthropic (cloud) and Local
  (OpenAI-API-compatible — Ollama / vLLM / llama.cpp). The local
  path is the on-prem unblock for pharma security.
- **Hallucination benchmark.** 5-paper seed set
  (Lindorff-Larsen 2010, Mobley 2007, Sugita-Okamoto 1999, Wang
  2015 FEP+, Salomon-Ferrer 2013); expanding to 20. The framework
  refuses to score unverified entries — *honest empty over
  confident wrong*.
- **Python bindings.** Pure-Python IR + validation + lint + corpus
  for headless integration; subprocess to the Julia CLI for
  rendering and runtime.
- **Longitudinal runs DB.** Every benchmark run is recorded;
  `crucible benchmark trends` and `runs-stats` show drift over
  time across providers, models, and schema versions.

### What you do next

Three paths depending on who you are:

- **Researcher reproducing a paper:** read
  [`docs/USER_PROFILE_GRAD_STUDENT.md`](USER_PROFILE_GRAD_STUDENT.md);
  the 30-minute path produces a runnable script from your paper.
- **Pharma CADD lead evaluating tooling:** read
  [`docs/USER_PROFILE_PHARMA_POC.md`](USER_PROFILE_PHARMA_POC.md);
  the 30-day path produces a written eval for management.
- **Academic referee evaluating the project:** read
  [`docs/USER_PROFILE_JOSS_REVIEWER.md`](USER_PROFILE_JOSS_REVIEWER.md);
  the 30-minute smoke walks the 6 JOSS criteria.

Open source, Apache 2.0, no telemetry, no auto-update phone-home.

---

## The 30-minute pitch

### Slide 1 — title + headline

> **Crucible — turning published MD papers into runnable
> simulations, with the audit trail a reviewer would accept.**

### Slide 2 — the reproducibility crisis is also a translation crisis

Recent surveys (cite: Mobley 2018 J. Comp. Chem.; PLOS One 2020
reproducibility study) show that 30-50% of published MD claims
fail to replicate when re-run from the Methods section alone. The
diagnosis is overwhelmingly *protocol misspecification*, not
scientific fraud — wrong force field version, wrong cutoff,
missing constraint, wrong integrator.

The cost: graduate-student months per failed reproduction, lost
peer-review confidence, slower iteration on real biology.

### Slide 3 — naive LLM scripts make this worse, not better

A natural reaction in 2026: "give the Methods section to GPT and
let it write the OpenMM script." This produces *more* silent
failures because the LLM:

- Hallucinates force-field names that don't exist
- Picks defaults from one paper for another paper's system
- Skips the barostat in NPT
- Inverts unit conventions (kJ vs kcal, nm vs Å)
- Ignores constraints settings that affect timestep stability

These bugs don't crash. They produce simulations that *look*
fine — finite energies, equilibrating temperature — but are
physically wrong. The salt-mines review panel quoted earlier:
"a false-pass validator is worse than no validator."

### Slide 4 — the IR-as-contract design

Crucible inverts the problem. The LLM doesn't write Python; it
emits a JSON Schema-validated IR. Show the schema diagram (from
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md)).

The IR has 9 top-level objects (system, force_field, protocol,
observables, …) and a flat `provenance` map. Every numeric field
carries units in its name; every enum is bound to an allowlist.

Result: the LLM's hallucination surface collapses. It can't make
up a force-field name (allowlist rejection); it can't invert
units (none exist on the LLM-side); it can't skip required fields
(JSON Schema rejection).

### Slide 5 — five validation gates

Show the gate diagram (from
[`docs/ARCHITECTURE.md`](ARCHITECTURE.md)). Walk each gate with
one sentence:

1. **Schema** — JSON Schema validates the IR.
2. **Semantic** — 17 Julia rules enforce cross-field invariants
   (NPT → barostat present, FEP λ monotonic, vacuum → no ions,
   constant-pH → titrating residues non-empty).
3. **Loadability** — backend tries to load the topology +
   coordinates.
4. **Preview run** — 100-1000 steps; assert energies finite, T
   within ±50 K.
5. **User confirm** — Pluto/UI gate before allocating production
   GPU time.

### Slide 6 — the hallucination benchmark

Crucible's *empirical* answer to "is the LLM actually any good?"
is the published benchmark: 5 papers (expanding to 20), each
verified against the source Methods section, scored on 10 binary
axes. Show the benchmark page
([`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md)).

The framework deliberately refuses to score unverified entries.
Fabricated ground truth is the worst possible failure mode; we
prefer honest empty over confident wrong.

Run the benchmark yourself in 5 minutes — the on-screen reproduce
section shows the commands.

### Slide 7 — pharma-grade on-prem mode

The pharma adoption-blocker is IP policy: most CADD groups are
forbidden from sending unpublished protocols to third-party APIs.
Crucible's `LocalProvider` is OpenAI-API-compatible — point it at
Ollama / vLLM / llama.cpp and the protocol never leaves your
network.

Show [`docs/ON_PREM.md`](ON_PREM.md). Note the network-policy
preflight script for IT/security review.

### Slide 8 — the option-3 fine-tune flywheel

Every transcript Crucible processes is logged to a DuckDB store
(`(paper_text, MDSpec, validation_outcome, score)`). After a
year, this is the training corpus for a chemistry-MD-fine-tuned
open model. The plan: when the corpus is mature, fine-tune
Qwen2.5-Coder or similar; deploy as a drop-in `LocalProvider`
swap.

This is what justifies the IR-first design: pair-data
(`paper_text → MDSpec_json`) is dramatically easier to curate +
validate than pair-data (`paper_text → runnable_python`).

### Slide 9 — adoption timeline

Show [`docs/ADOPTION_TIMELINE.md`](ADOPTION_TIMELINE.md) phase
table. Identify which phase the audience is in:

- Researchers / instructors → Phase 0/1.
- Open-source contributors → Phase 1.
- Pharma evaluators → Phase 2c.

Each row points to a `USER_PROFILE_*.md` doc; the audience
leaves with concrete next steps in their hand.

### Slide 10 — call to action + Q&A

- **For researchers:** clone, run a 30-minute path against your
  paper, file an issue if anything tripped.
- **For evaluators:** scope a 30-day POC against your internal
  protocols.
- **For investors / sponsors:** read
  [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md);
  this is what the next 6 months look like.
- **For everyone:** the project is open source, Apache 2.0, no
  telemetry. Audit it; fork it; tell us what's missing.

Repository: github.com/j4qfrost/crucible.
Maintainer: cited explicitly in the README; reach out via issues
or email.

---

## Pitch maintenance

When to update each:

- **60-second:** any time the wedge sentence changes (rare). The
  wedge is `IR + provenance + validation gates`. As long as those
  three are the value prop, the 60s holds.
- **5-minute:** when a major capability ships (new backend, new
  provider, benchmark publishes a real number). Check that "Today"
  list against the actual feature set.
- **30-minute:** when adoption-phase status changes (hitting Phase
  1, hitting Phase 2c). The slide-by-slide structure stays; the
  phase-table content updates.

Cross-check against the canonical pitch in
[`musings/scaling_modes.md`](../musings/scaling_modes.md) opening —
if they diverge, fix the divergence here, not in the musing (the
musing is durable; this doc is operational).

## See also

- [`README.md`](../README.md) — even shorter pitch (the 30-second
  variant; lives in the project landing page).
- [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md)
  — the technical-depth backing for the slide-4 design claim.
- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) —
  the credibility anchor referenced in slide 6.
- [`docs/USER_PROFILES.md`](USER_PROFILES.md) — the next-step
  pointers from each pitch land here.
