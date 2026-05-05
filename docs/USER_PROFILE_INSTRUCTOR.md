# User profile — instructor / TA

> **You leave with:** a Pluto walkthrough notebook + a 1-week course
> module that takes students from "what is MD?" to "I just reproduced
> a published protocol." Designed for a single 90-minute lab session
> + asynchronous follow-up reading.

This profile is for someone teaching a comp-chem or biophysics course
who wants Crucible as a homework / lab tool — *not* the centerpiece
of a research project. The instructor's needs differ from a
researcher's: every error message has to be debuggable by a 3rd-year
student in office hours, every example has to run on a laptop, and
the 5-gate validation framework has to be a teachable artifact, not
a black box.

## Pre-flight (1 lab session of TA prep)

What you need before assigning anything:

- All students need: Julia 1.10+, Python 3.10+. **Don't** require
  ANTHROPIC_API_KEY — students won't have one and shouldn't pay
  for one. Use the local-LLM path or `--mock` for didactic runs.
- A shared lab machine (or a department GPU cluster) with Crucible
  pre-installed. Don't make 30 students each install Julia.
- The two existing Pluto walkthroughs already in the repo:
  - [`examples/walkthrough_v15_methods.jl`](../examples/walkthrough_v15_methods.jl)
    — paper → IR → script. The flagship pedagogical artifact.
  - [`examples/study_validation_gates.jl`](../examples/study_validation_gates.jl)
    — interactive 5-gate validator with sliders that break each
    gate intentionally.

Run both notebooks yourself first. They're the lab session; if you
can't drive them, students can't either.

## The 30-minute path (your prep, before students arrive)

```bash
git clone https://github.com/j4qfrost/crucible
cd crucible
julia --project -e 'using Pkg; Pkg.instantiate()'

# Open the validation-gates walkthrough.
julia --project -e 'using Pluto; Pluto.run(notebook="examples/study_validation_gates.jl")'
```

Drive every cell. Notice:
- Sliders that mutate the spec (timestep, ensemble, water model).
- Each slider change triggers re-validation; students see the gate
  flip from green to red in real time.
- The error messages are the lecture. Every gate failure cites the
  IR field that violated, not a stack trace.

This notebook is the lab. The lecture is the theory behind why each
gate exists.

## A 1-week course module

Five 50-minute lectures + one 90-minute lab + one homework set.

### Lecture 1 — what is MD, and why protocols matter

- Standard MD-101 content (most courses already cover this).
- New: introduce the *protocol* as the unit of reproducibility. A
  paper's Methods section is not just text; it's a program.
- Reading: [`docs/HOW_TO_READ.md`](HOW_TO_READ.md#for-newcomers-to-md).

### Lecture 2 — the IR-as-contract decision

- Motivating problem: why does naive "LLM writes Python" fail at
  reproducing MD? Hallucinations on FF names, wrong units, missing
  barostat.
- Solution: typed IR + validation gates. The LLM's hallucination
  surface collapses to a finite enum/numeric space.
- Reading: [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md).
  Worth a full read for the class.
- Homework set up: students will reproduce a paper's Methods later
  in the week.

### Lecture 3 — the 5 gates

- Walk through each gate's failure mode with a deliberate example:
  - Gate 1: emit a spec with `protein_ff: "ff14SBz"` (typo). Schema
    rejects.
  - Gate 2: emit `ensemble: NPT, barostat: null`. Semantic rule
    rejects.
  - Gate 3: emit a spec referencing a topology that doesn't exist.
    Backend loadability rejects.
  - Gate 4: emit a spec with `dt: 10 fs`. Preview run sees energy
    blow up; rejects.
  - Gate 5: the human-confirm gate. Discuss why this exists.
- Live demo: drive `examples/study_validation_gates.jl` interactively.

### Lecture 4 — provenance + LLM-as-extractor

- The IR's provenance system: every numeric field carries `source`
  (`paper`, `paper_default`, `assumed`, `user`).
- Why this matters: when a Methods section is silent on a knob, the
  LLM has to guess. Tagging the guess lets reviewers see what was
  assumed.
- Reading: [`docs/GLOSSARY.md`](GLOSSARY.md) entries for "provenance"
  and "coverage score."
- Lab prep: each student picks a paper from your reading list to
  reproduce in the lab.

### Lecture 5 — the hallucination benchmark

- The empirical question: how good is the LLM, actually?
- Walk through [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md).
- Discuss why the benchmark refuses to score `needs_verification`
  entries (fabricated ground truth is worse than no ground truth).
- Class exercise: pick one of the seed entries, walk through the
  verification procedure together (15 minutes).

### Lab session (90 min) — paper to script

Each student:

1. Brings a paper (assigned in lecture 4 or chosen freely).
2. Extracts the Methods section to `methods.txt`.
3. Runs `crucible transpile --paper methods.txt --provider local`
   (or `--mock` for the didactic version).
4. Runs `crucible health spec.json`.
5. **Deliverable:** a one-paragraph write-up of (a) what the LLM
   extracted correctly, (b) what it got wrong, (c) what the gates
   caught.

Office hours TAs should have read
[`docs/USER_PROFILE_GRAD_STUDENT.md`](USER_PROFILE_GRAD_STUDENT.md)
and the failure-modes section in particular.

### Homework — verify a benchmark seed entry

Take one of the 5 entries in `python/crucible/benchmark/papers.py`
that's still `needs_verification`, read the source paper (you'll
find it via DOI), and submit:

1. A pull request adding `verified_by="<your initials> <date>"` and
   filling in the `ExpectedProtocol` axes.
2. A short write-up of which axes you set to `None` (paper didn't
   specify) and why.

This homework is real work — the project is open source and your
verified entry actually ships in the next release if accepted. (If
you don't want PRs from a class of 30, have students email the
verified entries to the TA and the TA picks one to PR.)

## Failure modes specific to this profile

- **"My students don't have GPU access."** Don't do production
  runs. The 30-minute path uses `--preview` which runs on CPU in
  ≤30 seconds. The lab artifact is the spec + the health gate
  output, not a converged trajectory.
- **"The local-LLM setup is too much for a class."** Use `--mock`
  for everything except the homework. Mock returns the vanilla
  template; the LECTURE about *what an LLM transpile would do* is
  the educational content; the actual call is a black box for the
  course.
- **"A student found a bug in Crucible."** Great. Have them open an
  issue (or a PR if they're up for it). The project explicitly
  welcomes students; the maintainer responds within a week.
- **"The 5-gate framework feels overengineered for a 50-minute
  lecture."** Cover only Gates 1-3 in the lecture. Gates 4-5 are
  worth a single slide ("there's also a runtime check + a human
  confirm gate; details in the docs"). Don't try to teach the full
  framework in one session.
- **"The Pluto walkthroughs run too slowly the first time."** Pluto
  + Julia compile on first cell evaluation; the reactive UI is
  snappy after that. Pre-warm by running each notebook once before
  the lab session — the cache survives across sessions.

## Variants for adjacent courses

- **Computational drug discovery course (3rd-4th year):** swap the
  paper assignment for one of the cancer-area templates
  ([`docs/CANCER_USE_CASES.md`](CANCER_USE_CASES.md)). The
  kinase-inhibitor FEP template is a real binding-ΔG workflow.
- **MD methodology course (grad-level):** add a lecture on
  cross-language consistency
  ([`musings/why_subprocess_over_pythoncall.md`](../musings/why_subprocess_over_pythoncall.md))
  and the schema-bump migration framework. These are real
  software-engineering tradeoffs students benefit from seeing.
- **AI/ML for science course:** the IR-as-contract decision is the
  whole lecture. Discuss why structured-output binding (JSON
  Schema) outperforms free-form generation for narrow technical
  domains.

## When to read X next

- *I want to assign more homework* → the
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md)
  procedure scales to 1-paper-per-student trivially.
- *A student wants to do their thesis on Crucible* →
  [`docs/POWER_USERS.md`](POWER_USERS.md) for the contributor
  onboarding; [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) for the
  strategic context.
- *I want to tailor the Pluto walkthrough to my syllabus* → it's
  one file (`examples/study_validation_gates.jl`); fork it.

## See also

- [`docs/HOW_TO_READ.md`](HOW_TO_READ.md) — reading guides that
  complement the task-doc you're reading now.
- [`docs/GLOSSARY.md`](GLOSSARY.md) — vocabulary for students who
  haven't seen "MDSpec," "provenance," "validation gate" before.
- [`examples/walkthrough_v15_methods.jl`](../examples/walkthrough_v15_methods.jl)
  — the second walkthrough notebook, paper → script focused.
- [`musings/scaling_modes.md`](../musings/scaling_modes.md) — the
  academic mode is the natural home for course adoption.
