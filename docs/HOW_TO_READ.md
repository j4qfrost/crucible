# How to read this project

Six guides for six different readers. Pick yours, follow the reading
order, ignore the rest until you need it. Each guide has the same
shape: minimum prep → reading order (do these in order) → hands-on
exercises → "you've got it when…" checkpoint → what to read once
you're past the basics.

| You are a… | Jump to |
|---|---|
| Wet-lab biologist or chemist; you don't normally code | [§ Wet-lab biologist](#wet-lab-biologist) |
| Computational chemist; you've used OpenMM, Gromacs, or Amber | [§ Computational chemist](#computational-chemist) |
| Research software engineer; the architectural decisions are why you're here | [§ Research software engineer](#research-software-engineer) |
| PI / staff scientist deciding whether your group should adopt | [§ PI evaluating adoption](#pi-evaluating-adoption) |
| New PhD student; you've been told "go do MD" and want a path | [§ New PhD student](#new-phd-student) |
| LLM-tooling engineer; you're here for the IR-as-contract pattern | [§ LLM-tooling engineer](#llm-tooling-engineer) |

A single sentence summary you can use to decide whether the project
is even relevant to you: **Crucible is a Julia + Python pipeline that
takes a chemistry paper, extracts its molecular-dynamics protocol via
an LLM into a structured intermediate representation (`MDSpec`), and
renders that IR into a runnable OpenMM (or Molly) script with
provenance, validation, and a cloud-sizing recommendation.**

Two cross-cutting resources useful to every reader:

- [`docs/GLOSSARY.md`](GLOSSARY.md) — definitions for every
  domain-specific term used in the project (MD, drug-discovery,
  materials, quantum, LLM, Crucible-internal).
- [`examples/study_validation_gates.jl`](../examples/study_validation_gates.jl)
  — Pluto notebook walking through the five-gate validation pipeline
  hands-on. Pairs nicely with the "research software engineer" and
  "new PhD student" guides.

---

## Wet-lab biologist

You know your way around a cell culture, a Western blot, and a kinase
assay. You've heard about MD simulations and want to know whether you
can use Crucible to predict, say, whether your candidate inhibitor
will bind your target — without becoming a molecular dynamicist.

### Minimum prep

- Comfort with the **command line** (you can `cd` and `cat`).
- Familiar with **PDB files** — you've at least looked one up on RCSB.
- Conceptual feel for **binding affinity (Kd / Ki)**.
- That's it. No coding.

### Reading order

1. **README** (~10 minutes). Read just the first three sections (what it
   is, the hard rule, GPU acceleration). Skip the rest.
2. **`docs/USE_CASES.md`** (~15 minutes). The "if you're doing X, start
   from Y" picking guide.
3. **`docs/CANCER_USE_CASES.md`** (~30 minutes). Read in full; it's the
   most aligned with wet-lab drug-discovery thinking. The
   "scientific scrutiny" warning and the "don't use this for" notes
   are the most-important bits — they tell you when MD will mislead
   you.

### Hands-on exercises

```bash
# 1. Confirm the tool runs
crucible --help
crucible doctor

# 2. Make a starter spec for your kind of question
crucible templates init kinase_inhibitor_fep --out my-spec.json

# 3. See it in plain English
crucible explain my-spec.json

# 4. See what it'll cost on the cloud
crucible advise my-spec.json --budget-hours 24

# 5. See its quality score (lower = more "the LLM guessed")
crucible health my-spec.json
```

You don't need to actually run the simulation — `crucible explain`
turns the IR into a paragraph you can show to a computational
collaborator and ask "does this look right for what I want?"

### You've got it when…

…you can describe the difference between the three cancer templates
in your own words ("kinase FEP gives a binding number, PPI gives a
stability picture, GPCR membrane gives conformational sampling"),
AND you understand that running the simulation is the *easy* part —
the hard part is choosing the right system and trusting the result.

### Past the basics

Pair Crucible with one of: an MD-comfortable collaborator (you supply
the SMILES + crystal structure; they own the run + analysis); the
[OpenMM Cookbook](http://openmm.org/cookbook/) (free, written for
biologists); Frenkel & Smit chapters 1-3 (graduate MD textbook,
optional unless you want to actually do this yourself).

---

## Computational chemist

You've run OpenMM, Gromacs, or Amber. You know what NPT means; you've
debugged a CHARMM-GUI build; you know that ff14SB ≠ ff14SBonlysc. You
want to know what Crucible adds vs. just writing your own scripts.

### Minimum prep

- Working OpenMM install (any platform).
- Comfort with conda/pip.
- A specific MD problem you'd want to solve.

### Reading order

1. **`docs/PLAN.md`** (~20 minutes). The architecture + the design
   choices. Skip the historical "Status as of 2026-04-25" sections —
   read v1.0 update onward.
2. **`docs/IR.md`** (~15 minutes). Auto-generated reference. Skim;
   come back when you want field-level detail.
3. **`musings/why_ir_as_contract.md`** (~20 minutes). The most
   important call the project has made. If you disagree with it,
   the project's not for you and that's fine.
4. **`musings/why_subprocess_over_pythoncall.md`** (~10 minutes). The
   choice that made Python interop tractable.
5. **`docs/USE_CASES.md`** + whichever of the three application docs
   matches your domain (~30 minutes).

### Hands-on exercises

```bash
# 1. Render a fully runnable OpenMM script, no LLM, no API key
crucible templates init protein_ligand_fep --out spec.json
crucible render spec.json --backend openmm --out run.py

# 2. Read the generated Python — it's idiomatic OpenMM, not a black box
less run.py

# 3. Compare to your own pipeline. Notes:
#    - The CRUCIBLE_PLATFORM auto-fallthrough (CUDA → HIP → OpenCL → CPU)
#    - The seed plumbing through every integrator
#    - The CheckpointReporter pattern for long runs
#    - The MonteCarloMembraneBarostat auto-detection in membrane systems
#    - The openmmtools.alchemy / multistate code for FEP / REMD
```

### You've got it when…

…you can compare a `crucible render`-emitted script line-by-line to
one you'd have written yourself and identify what's added (provenance
hooks, env-var pluming, deterministic seeding) vs. what's the same
(the OpenMM API calls). The point is: Crucible doesn't hide OpenMM —
it organizes the metadata around it.

### Past the basics

The interesting questions for you: how does Crucible's IR compare to
[CHARMM-GUI's session config](https://charmm-gui.org/), [OpenFF
Evaluator's protocol schema](https://github.com/openforcefield/openff-evaluator),
or [BioSimSpace](https://biosimspace.openbiosim.org/)? Each made
slightly different IR-shape decisions — Crucible's stance is
documented in `musings/why_ir_as_contract.md`.

If you want to extend Crucible: read `CONTRIBUTING.md` § "Adding a new
stage type." The pattern is well-grooved (Minimize → Dynamics → FEP →
REMD → Metadynamics all followed it).

---

## Research software engineer

You ship code professionally. You know about SemVer, schema
migrations, CI/CD, multi-language interop, contract-driven design.
You may or may not know MD, and that's fine. You're here for the
architecture.

### Minimum prep

- Comfortable in any of: Julia, Python, Rust, Go.
- You've shipped code that's been reviewed by other engineers.
- You've felt the pain of an unstructured-output LLM in production.

### Reading order

1. **README** (~10 minutes). Skim. The "What works" tables are the
   capability surface.
2. **`musings/README.md`** + all five musings in there (~60 minutes
   total). This is the project's design philosophy. Read in this
   order:
   1. `why_ir_as_contract.md` — the foundation
   2. `why_subprocess_over_pythoncall.md` — the multi-language story
   3. `why_no_genie.md` — the framework-choice discipline
   4. `why_dual_ci.md` — the CI trade-off
   5. `quantum_outlook_eli5.md` — calibration on a hyped adjacent field
3. **`CONTRIBUTING.md`** (~20 minutes). The hard rules + workflow
   patterns are the engineering discipline distilled.
4. **`docs/PLAN.md`** § Architecture (~15 minutes). The IR shape +
   five-gate validation pipeline.
5. **`src/spec/MDSpec.jl`** + **`src/spec/schema.json`** + **`src/spec/Migrations.jl`**
   (~30 minutes total). The actual contract.

### Hands-on exercises

```bash
# 1. The "first 5 minutes" walkthrough as a working developer
./examples/starter_session.sh

# 2. Read the rendered output of a complex template
crucible render kinase_inhibitor_fep --out /tmp/k.py
wc -l /tmp/k.py

# 3. See the JSON Schema explicitly (useful for understanding the
#    LLM contract)
crucible export-jsonschema | jq '.properties.protocol.items.oneOf[0]'

# 4. Look at the migration story
cat src/spec/Migrations.jl
julia --project tools/migration_smoke.jl

# 5. Test pyramid
ls test/
docker run --rm -v "$PWD":/work -v /tmp/crucible-depot:/julia-depot \
    -w /work -e JULIA_DEPOT_PATH=/julia-depot julia:1.10 \
    bash -c 'julia --project -e "using Pkg; Pkg.test()"'
```

### You've got it when…

…you can explain to another engineer why the LLM emits structured
JSON instead of runnable Python (the answer in
`why_ir_as_contract.md`), why subprocess beat PythonCall (in
`why_subprocess_over_pythoncall.md`), and what the project's three-
tier deferral discipline is (real runtime + deferred runtime + deferred
IR — see how constph and Martini are scaffolded vs. how
`QuantumParameterizer` is documented but not scaffolded).

### Past the basics

The architecture-decision records in `musings/` are deliberately
candid. If you want to apply this pattern to your own project, the
key invariants:

- The IR is the contract. Every consumer reads the IR; nothing
  bypasses it. Validation gates run sequentially. Schema bumps are
  versioned + migration-registered.
- Multi-language interop happens at process boundaries (subprocess),
  not function boundaries (FFI/PythonCall). The other process owns
  its environment.
- Don't scaffold for hypothetical runtimes. Scaffold for runtimes
  that exist (constph, Martini); document for runtimes that don't
  (quantum). This keeps cargo-cult code out of the source tree.

---

## PI evaluating adoption

You run a research group; one of your students wants to use this; you
want to know whether it's a sustainable choice or a project the
person who wrote it will abandon in six months.

### Minimum prep

- The vague shape of what your group does.
- Awareness that "we use this in production" is a different bar than
  "we tried it."

### Reading order

1. **README "Status" table** (~5 minutes). Counts the surface.
2. **`CHANGELOG.md`** (~10 minutes). Read the most recent entries
   (v1.10+ for the GPU work, v1.15+ for the use-case templates) for
   the velocity feel. Cadence is roughly daily.
3. **`docs/PLAN.md`** sections "Hard rules" and "Status" (~10 minutes).
4. **`docs/QUANTUM_OUTLOOK.md`** (~15 minutes). The project is
   *unusually disciplined* about not chasing hype; this doc is the
   evidence. If you find a project's quantum-computing position
   honest, that's a strong signal.
5. **`docs/USE_CASES.md`** + the use-case doc(s) for your group's
   domain (~30 minutes).
6. **`tools/`** directory listing (~5 minutes). The operational
   surface: doctor, snapshot/restore, migration_smoke, gha-runner-setup,
   regenerate_fixtures, sync_remotes. Production-grade tooling for a
   project this young.

### Adoption decision matrix

| Concern | Where to look | Honest read |
|---|---|---|
| **Will it survive the maintainer leaving?** | `CONTRIBUTING.md`, `AGENTS.md`, `musings/` | Yes — the architectural-decision records are unusually thorough; another senior engineer could pick this up cold. |
| **Is it production-grade?** | CI yamls, test count (860+), `tools/migration_smoke.jl`, `tools/baselines/` | Yes for the IR + render path. The LLM transpile path is more recent. |
| **Will my students learn from it?** | `docs/HOW_TO_READ.md` § Computational chemist + § PhD student | Yes — see the dedicated section below. |
| **Is the LLM dependency a vendor-lockin risk?** | `src/llm/Provider.jl` (`AnthropicProvider`, `LocalProvider`, `RecordedProvider`) | No — three-provider abstraction. RecordedProvider lets the test suite run without any LLM. |
| **Does the IR evolve too fast for stable use?** | `src/spec/Migrations.jl`, `tools/migration_smoke.jl` | No — every schema bump has a forward migration; the smoke test enforces it in CI. |
| **GPU vendor lock?** | `musings/`-adjacent: `OpenMMBackend._emit_protocol`'s platform fallthrough | No — auto-detect CUDA → HIP → OpenCL → CPU; AMD is first-class. |

### You've got it when…

…you can sketch the answer to "what would happen if I told a junior
person in my group to use this for their thesis project" without
hand-waving.

### Past the basics

Two questions worth raising with the maintainer before deep adoption:

1. **What's the validation strategy for the LLM transpile path on
   *your* domain?** The recorded fixture exercises a known-good
   spec; your domain may need its own fixtures.
2. **What's the support story when the schema bumps from 0.3.0 to
   0.4.0?** The migration framework handles this, but a major
   schema bump may require updating downstream tooling that consumed
   the JSON.

---

## New PhD student

You started ~three months ago. Your advisor said "go do MD." You're
deciding whether to learn OpenMM directly, use Gromacs, or use this.

### Minimum prep

- Your undergrad chemistry / biophysics / pharmacology background.
- ~6 hours/week to invest over ~6 weeks.
- A specific small project to motivate the work (without one, MD
  becomes abstract fast).

### Reading order (3-week curriculum)

**Week 1 — orient.**

Read in this order:

1. README + `docs/PLAN.md` § Context (~30 minutes).
2. `docs/USE_CASES.md` + the use-case doc closest to your project
   (~30 minutes).
3. Frenkel & Smit, *Understanding Molecular Simulation*, chapters
   1-3 (~6 hours). Don't skip — the basics make everything that
   follows easier.
4. `examples/starter_session.sh` — run it, read every line of output
   (~30 minutes).

**Week 2 — hands-on.**

1. Pick a template that maps to your project. Read its `notes` field
   + the matching use-case doc.
2. Run it end-to-end on a CPU first (set `CRUCIBLE_PLATFORM=CPU` and
   shorten the durations). The point is to see all the moving pieces.
3. Use `crucible explain` and `crucible cite` on the spec until you
   understand every numeric field.
4. Read OpenMM's user guide chapter on whatever method your template
   uses (FEP, REMD, or basic NPT MD).

**Week 3 — extend.**

1. Modify the template for your specific system (different SMILES,
   different PDB id, different temperature ladder).
2. Run on GPU.
3. Use `crucible analyze` + `crucible plot` on the output.
4. Read `musings/why_ir_as_contract.md` — at this point you'll have
   the context to appreciate it.
5. (Optional) Read Mobley & Klimovich on practical FEP if your work
   is binding-affinity-shaped.

### You've got it when…

…you can take a methods section from a paper in your field and tell
me which template it most-closely maps to, what you'd need to change,
and roughly what the run would cost. AND you can read the rendered
OpenMM script and predict roughly what every block does.

### Past the basics

The full curriculum from the project README:

- Frenkel & Smit (graduate MD)
- Leach (modeling, easier)
- Chodera et al. on FEP
- Mobley & Klimovich on alchemical free energies
- OpenMM 8 user guide

Plus the project's own:
- All five musings in `musings/`
- `CONTRIBUTING.md` (when you're ready to extend)
- `docs/QUANTUM_OUTLOOK.md` (calibration on hype)

---

## LLM-tooling engineer

You build LLM-driven products. You've watched too many demos where the
LLM emits raw code and the demo team ships a "watch the magic happen"
video. You want to see what production-grade LLM-in-research-software
actually looks like.

### Minimum prep

- Familiar with structured-output / function-calling APIs.
- You've debugged at least one LLM hallucination in production.
- Comfort reading any of: Python, Julia, TypeScript.

### Reading order

1. **`musings/why_ir_as_contract.md`** (~20 minutes). The thesis.
2. **`src/llm/Provider.jl`** — the three providers
   (`AnthropicProvider`, `LocalProvider`, `RecordedProvider`) +
   the `TRANSPILE_SYSTEM_PROMPT` (~15 minutes).
3. **`src/spec/schema.json`** — the LLM's actual output contract
   (~15 minutes).
4. **`src/validation/Gates.jl`** — the validation pipeline that
   runs on the LLM output (~10 minutes).
5. **`src/spec/Coverage.jl`** — the provenance / lint system
   (~10 minutes).
6. **`src/llm/Transcripts.jl`** — the data flywheel implementation
   (~5 minutes).
7. **`docs/PLAN.md`** § "Roadmap to 'Option 3' (specialized fine-tuned
   chem model)" (~10 minutes).

### Hands-on exercises

```bash
# 1. See the structured-output prompt
julia --project -e 'using Crucible; print(Crucible.TRANSPILE_SYSTEM_PROMPT)' | less

# 2. The deterministic offline path
crucible transpile notes "AMBER ff14SB ... NPT ... 100 ns" \
    --provider recorded:test/fixtures/recorded_anthropic_spec.json

# 3. Quality scoring on the result
crucible coverage <output-spec.json>
crucible lint <output-spec.json>

# 4. The training-data export format
julia --project tools/templates_to_jsonl.jl > seed.jsonl
crucible import-jsonl seed.jsonl
crucible audit-transcripts ~/.local/share/crucible/transcripts.duckdb
```

### Patterns worth stealing

- **Structured-output as JSON Schema, not free-form code.** The
  LLM's output space is a finite enum/numeric domain. Hallucinations
  collapse to "wrong enum value" → schema validation catches them.
- **Provenance as first-class.** Every numeric field carries
  `{source: :paper | :assumed | :paper_default, cite, confidence}`.
  This is what makes the audit story credible.
- **Five-gate validation pipeline.** Schema → semantic → loadability
  → preview-run → user-confirm. Sequential, non-skippable. Each
  gate's cost increases; cheap rejections happen early.
- **Lint as advisory layer.** Beyond pass/fail validation, the
  `lint()` function emits `:short_production`, `:no_equilibration`,
  `:provenance_low`, etc. This is where you encode "things the
  LLM gets right but a human reviewer would catch."
- **Coverage scoring → corpus quality → fine-tune readiness.** The
  data flywheel: log every transpile session, score by provenance
  quality, audit periodically. When coverage > N for ~1k entries,
  fine-tune a small model on the JSONL export.
- **Three-provider abstraction.** Real LLM (Anthropic), local LLM
  (vLLM/Ollama via OpenAI-compatible API), recorded fixture (no
  network, deterministic tests). Tests run on the recorded path
  even in CI.
- **Transcripts → DuckDB.** Local-first, JSONL export for sharing.
  Future fine-tune training-data is one `cat *.jsonl` away.

### You've got it when…

…you can describe Crucible's LLM architecture using exactly five
words: "structured output as JSON schema." And then explain how
provenance, lint, coverage, and transcripts each follow from that
choice without contradiction.

### Past the basics

The fine-tune roadmap (Option 3) in `docs/PLAN.md` is the long
arc: log → curate → fine-tune → swap. None of it requires
proprietary models. The realistic path: at ~1k high-quality
transcripts, fine-tune Qwen-Coder-7B (or successor) with
constrained-decoding to the schema. JSON Schema validity becomes
the cheapest correctness signal for the training loop.

---

## Across all six paths: the common skeleton

Every guide above ends in the same place: you can read a generated
spec, predict what `crucible run` will do, and decide whether the
output is trustworthy. The path to that confidence differs:

- **Wet-lab** comes through `docs/USE_CASES.md` and `crucible explain`.
- **Comp chem** comes through reading the rendered OpenMM script.
- **RSE** comes through the IR + the musings.
- **PI** comes through the CI hygiene + tooling surface.
- **PhD student** comes through 3 weeks of structured practice.
- **LLM engineer** comes through the schema + provenance + lint
  triple.

If your path doesn't fit one of these six, the most-useful thing to
read first is `docs/PLAN.md` § Context + `musings/why_ir_as_contract.md`.
That gives you enough vocabulary to know where to look next.

## Open question

This doc is itself a work in progress. If you've read it and have a
"this section was wrong for my background" reaction, that's
actionable feedback — open a PR adjusting the relevant section, or
file an issue with the specific gap. The goal is for each section
to feel like it was written *for you*, not for a generic reader.
