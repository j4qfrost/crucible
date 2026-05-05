# User profile — JOSS reviewer / scientific software referee

> **You leave with:** a JOSS-style review of Crucible covering the 6
> required criteria (statement of need, installation, functionality,
> tests, documentation, software paper). Total review time: 3-5
> hours. The doc maps each criterion to the specific file or command
> that exercises it.

This profile is for someone reviewing Crucible (or a Crucible-derived
project) as a JOSS / SOSS / pyOpenSci / similar scientific-software
referee. Could also be a tenure-and-promotion committee evaluating
software contributions, a peer reviewer for a Methods paper that
cites Crucible, or a tool-eval committee at a national lab.

The wedge: every JOSS criterion has a specific Crucible artifact
that addresses it, and they're cross-referenced from this doc so
you can finish the review in one sitting without grep-spiraling
through the codebase.

## Pre-flight (15 minutes)

What you need:

- Crucible installed (per
  [`docs/USER_PROFILE_GRAD_STUDENT.md`](USER_PROFILE_GRAD_STUDENT.md)
  pre-flight). `crucible doctor` should be green.
- A copy of the [JOSS review checklist](https://joss.readthedocs.io/en/latest/review_checklist.html)
  (or your venue's equivalent) open in another tab.

Read [`AGENTS.md`](../AGENTS.md) once before reviewing — it
documents the project's hard rules, and several of those map to
JOSS criteria (the "no fabricated parameters" rule answers the
"correctness" question).

## The 30-minute path — the smoke review

Walk through this in order; each step exercises a JOSS criterion.

### 1. Installation (5 min)

```bash
git clone https://github.com/j4qfrost/crucible
cd crucible
julia --project -e 'using Pkg; Pkg.instantiate()'   # Julia side
pip install -e python                                # Python bindings
crucible doctor
```

JOSS criterion: *"Does the software install successfully on at
least one platform?"*

What to record: the wall-clock time for the above; any failures
(open an issue in the repo with the failure mode).

### 2. Functionality (10 min)

```bash
crucible templates list                              # see canned starter specs
crucible templates init kinase_inhibitor_fep > spec.json
crucible health spec.json                            # run the 5-gate validator
crucible render spec.json --backend openmm | head -50
```

JOSS criterion: *"Does the software perform the functionality
claimed?"*

What to record: whether `crucible health` passes on each shipped
template, whether the rendered script is valid Python (you don't
need OpenMM to read it).

### 3. Tests (5 min)

```bash
# Julia test suite.
julia --project -e 'using Pkg; Pkg.test()'

# Python test suite.
cd python && pip install -e .[dev] && pytest
```

JOSS criterion: *"Are there automated tests with sufficient
coverage of the functionality?"*

Current numbers (verify against CHANGELOG): **928 Julia tests +
149 Python tests** at HEAD (May 2026). Coverage spans IR,
validators, renderers, LLM providers (mocked), templates, corpus,
benchmark scoring, runs-DB longitudinal layer, cross-language
consistency, and migration.

### 4. Documentation (5 min)

JOSS criterion: *"Is the documentation sufficient that a
proficient user can use the software?"*

Walk this map; each link is one JOSS-relevant artifact:

- **Statement of need:** [`README.md`](../README.md) opening; also
  [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md)
  for the design rationale.
- **Installation:** [`README.md`](../README.md) "Getting started"
  section; also
  [`docs/USER_PROFILE_GRAD_STUDENT.md`](USER_PROFILE_GRAD_STUDENT.md)
  pre-flight.
- **Quick-start:** the Pluto walkthrough notebooks at
  [`examples/walkthrough_v15_methods.jl`](../examples/walkthrough_v15_methods.jl)
  (paper → script) and
  [`examples/study_validation_gates.jl`](../examples/study_validation_gates.jl)
  (interactive 5-gate validator).
- **API reference:** [`docs/IR.md`](IR.md) is auto-generated from
  the canonical schema; [`docs/BENCHMARK_AXES.md`](BENCHMARK_AXES.md)
  for the scoring API.
- **Use cases:** [`docs/CANCER_USE_CASES.md`](CANCER_USE_CASES.md),
  [`docs/MATERIALS_USE_CASES.md`](MATERIALS_USE_CASES.md),
  [`docs/PROTEIN_ENGINEERING_USE_CASES.md`](PROTEIN_ENGINEERING_USE_CASES.md).
- **Contribution guidelines:** [`docs/POWER_USERS.md`](POWER_USERS.md)
  (extending), [`AGENTS.md`](../AGENTS.md) (hard rules + dev
  pattern), [`CONTRIBUTING.md`](../CONTRIBUTING.md) (process).
- **License:** [`LICENSE`](../LICENSE) (Apache 2.0).
- **Community guidelines:** [`CONTRIBUTING.md`](../CONTRIBUTING.md);
  also [`docs/USER_PROFILES.md`](USER_PROFILES.md) for adopter
  onboarding.

### 5. Software paper / preprint (5 min)

JOSS criterion: *"Does the paper place the software in the context
of related work?"*

Crucible's strategic context lives in:

- [`musings/scaling_modes.md`](../musings/scaling_modes.md) — the
  academic / OSS / business scaling analysis.
- [`musings/ecosystem_alternatives.md`](../musings/ecosystem_alternatives.md)
  — Python vs. Julia vs. others; explains language choice.
- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) —
  the empirical positioning vs. "naive LLM writes Python."

For the JOSS submission proper, see the methods-paper draft (in
preparation per
[`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 1).

## The deeper review (3-4 hours)

For a thorough review, exercise each criterion with depth:

### Statement of need

Read in this order:
1. [`README.md`](../README.md) "Getting started" + opening paragraphs.
2. [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md)
   — the load-bearing decision.
3. [`musings/scaling_modes.md`](../musings/scaling_modes.md) — who
   the software is for.

The need: MD reproductions fail because Methods sections are
human-readable but not machine-runnable, and naive "LLM writes
Python" produces silently-wrong code. Crucible's wedge is the IR +
validation gates that make the LLM's hallucinations rejectable
before runtime.

### Installation + portability

- Julia 1.10 / 1.11 / 1.12 in CI matrix
  ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)).
- Python 3.10+ (declared in `pyproject.toml`).
- Manifest.toml committed for reproducibility (per project policy
  in `docs/PLAN.md` v0.3 #14).
- macOS / Linux supported; Windows experimental (warning issued
  by `run_directory` per OS-detection).

The pre-commit aggregator at
[`tools/check_workspace.py`](../tools/check_workspace.py) catches 5
cross-file consistency invariants — useful to know exists.

### Functionality + correctness

The hard rules in [`AGENTS.md`](../AGENTS.md) are the project's
correctness guarantees. Worth reading:

1. The LLM never invents force-field parameters.
2. The IR is the contract.
3. Renderers are the only thing that converts units.
4. BYO-topology gate (auto-build for canonical residues only).
5. Gates run sequentially; no skipping.

The hallucination benchmark
([`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md))
is the empirical test of the LLM's correctness. Note: the
framework refuses to score `needs_verification` entries — the
project's stance is *honest empty over confident wrong*. This is
relevant if you're skeptical of LLM-driven scientific software.

### Tests + CI

- 928 Julia tests; 149 Python tests at HEAD.
- Cross-language consistency tests
  ([`python/tests/test_cross_language_consistency.py`](../python/tests/test_cross_language_consistency.py))
  pin the IR's wire-format invariant across both ports.
- Migration smoke
  ([`tools/migration_smoke.jl`](../tools/migration_smoke.jl)) walks
  every fixture through every registered migration target.
- Live-OpenMM CI cell exists but pinned to one matrix entry to keep
  build time reasonable.

The failure modes the project deliberately doesn't test are
documented in
[`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md)
"What's not in scope" (script correctness, FE convergence, ligand
parameterization fidelity).

### Documentation completeness

Use the [`docs/USER_PROFILES.md`](USER_PROFILES.md) index as the
review map. Five user profiles each have a dedicated 30-minute
path doc; the docs are deliberately task-oriented (companion to
the reading-oriented [`docs/HOW_TO_READ.md`](HOW_TO_READ.md)).

If a profile's path doesn't take ≤ 30 minutes for the median user,
that's a doc-quality bug (file an issue).

## Likely review findings (review-prep cheat sheet)

These are the questions that come up most in scientific-software
reviews; the answers are here so you don't need to re-derive them:

- **"How does the LLM avoid making up plausible-but-wrong
  parameters?"** Hard rule §1 (never invents FF params). The IR is
  enum-typed; the JSON Schema rejects out-of-allowlist values
  before they reach the renderer. See Gate 1 in
  [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md).
- **"Why JSON Schema instead of protobuf?"**
  [`musings/why_not_protobuf.md`](../musings/why_not_protobuf.md).
- **"Why Julia for the core?"**
  [`musings/ecosystem_alternatives.md`](../musings/ecosystem_alternatives.md).
- **"What happens to historical transcripts when the IR bumps?"**
  Migration framework — see
  [`python/crucible/migrate.py`](../python/crucible/migrate.py) and
  [`src/spec/Migrations.jl`](../src/spec/Migrations.jl) for the two
  parallel chains; cross-language smoke test catches drift.
- **"Is the validation framework testable?"**
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) +
  the verifier CLI. Verifying a paper is a one-command interactive
  flow.
- **"What's the contributor onboarding cost?"**
  [`docs/POWER_USERS.md`](POWER_USERS.md) (9-step checklist for
  adding a stage type — most invasive change). Schema bumps are
  documented as coordinated PRs.

## Failure modes specific to this profile

- **"I can't run Julia in my environment."** The pure-Python
  bindings ship with `pip install -e python` and exercise the IR +
  validation + corpus + benchmark layers without Julia. The
  cross-language smoke skips when Julia isn't on PATH.
  Documentation review can proceed without running anything.
- **"The README is too dense."** Skip to
  [`docs/USER_PROFILES.md`](USER_PROFILES.md) and pick the profile
  closest to the reviewer-as-adopter (probably grad student or
  reproducibility researcher).
- **"I want to evaluate the JOSS-paper draft, not the software."**
  The paper draft is in preparation per
  [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 1; reach out
  to the maintainer for the latest. The hallucination benchmark is
  the empirical core that the paper will cite.

## When to read X next

- *I want to compare against another protocol-extraction tool* —
  the field is small; the natural comparand is a hand-coded
  protocol-extraction script (the bar Crucible is being measured
  against). The benchmark
  ([`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md))
  is the apples-to-apples comparison artifact.
- *I'm unconvinced by the IR-first design* — read
  [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md)
  and the open issues that try to relitigate it. The musing format
  is itself a deliberate choice — every load-bearing decision has
  a durable record so it doesn't get re-fought.
- *I want to write the review now* — the JOSS-criteria checklist
  earlier in this doc is structured to be filled in linearly.

## See also

- [`AGENTS.md`](../AGENTS.md) — the hard rules; the closest thing
  Crucible has to a "correctness specification."
- [`docs/PLAN.md`](PLAN.md) — architecture + roadmap; the JOSS
  paper's technical core.
- [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 1 — the
  methods-paper milestone the JOSS submission anchors to.
