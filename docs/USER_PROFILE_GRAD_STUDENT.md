# User profile — grad student / postdoc

> **You leave with:** a runnable OpenMM script reproducing the MD
> protocol from a published paper, plus a 5-gate health report
> showing what the LLM extracted vs. what it guessed. Total time:
> ≤ 1 hour from a fresh checkout to a green `crucible health`.

This profile is for the most common adopter pattern: a grad student
or postdoc who's read a paper, wants to reproduce its MD, and is
tired of hand-translating Methods sections into Python. PI-level
adopters have the same path; the difference is who pays for the
GPU.

## Pre-flight (15 minutes once)

What you need:

- Julia 1.10+ (`curl -fsSL https://install.julialang.org | sh`)
- Python 3.10+ (you almost certainly already have this)
- A real paper PDF or Methods-section text. **Bring this with you.**
- Optional: `ANTHROPIC_API_KEY` if you have one; otherwise use the
  `--mock` path or set up a local LLM
  ([`docs/ON_PREM.md`](ON_PREM.md))

```bash
git clone https://github.com/j4qfrost/crucible
cd crucible
julia --project -e 'using Pkg; Pkg.instantiate()'   # ~3 min first time
pip install -e python                                # ~1 min
```

Smoke-test the install:

```bash
crucible doctor               # checks Julia + Python + backends
python -m crucible spec-describe   # prints schema + allowlists
```

If `crucible doctor` complains, fix that before going further. The
project assumes a working install — there's no "demo mode."

## The 30-minute path (the artifact you brag about)

```bash
# 1. Save the paper's Methods section to a file.
$ cat > /tmp/methods.txt <<'EOF'
The complex was solvated in TIP3P water with 150 mM NaCl, parameterized
with AMBER ff14SB for the protein and OpenFF Sage 2.2 for the ligand.
Energy minimization (2000 steepest-descent steps) was followed by 0.5 ns
NVT equilibration at 310 K and 2 ns NPT equilibration at 310 K and 1 bar
with Monte-Carlo barostat. Production was 50 ns NPT, 2 fs timestep,
Langevin thermostat at 1 ps^-1, h-bond constraints via SHAKE.
EOF

# 2. LLM transpile (uses ANTHROPIC_API_KEY or --provider local).
$ crucible transpile --paper /tmp/methods.txt --out /tmp/spec.json

# 3. Inspect what the LLM extracted vs. guessed.
$ crucible explain /tmp/spec.json
$ crucible coverage /tmp/spec.json

# 4. Run the 5-gate health check.
$ crucible health /tmp/spec.json
✓ Gate 1: schema
✓ Gate 2: semantic
✓ Gate 3: backend loadability
…

# 5. Render a runnable OpenMM script.
$ crucible render /tmp/spec.json --backend openmm > /tmp/run.py

# 6. Look at run.py. Compare to a script you've written by hand.
#    Notice: every default has a comment citing the source.
```

That's the artifact. You now have a script that's traceable from
paper → IR → script — and the gates caught any silent semantic
errors (NPT-without-barostat, dt-too-large, NVT-with-pressure, etc.)
before you ran a single MD step.

## The first-week path

Once the smoke works, integrate into your real workflow.

### Day 1 — your real paper

Repeat the 30-minute path with your actual paper of interest. Pay
attention to:

- Which fields the LLM marks `assumed` (low confidence). These are
  likely the ones the paper didn't state explicitly. Check them
  against the paper.
- Lint warnings (`crucible lint /tmp/spec.json`). The benchmark
  scoring treats your spec the same way.

### Day 2-3 — preview run

Don't allocate GPU time for a 100 ns run before you've smoke-tested
on CPU:

```bash
# Run 1000 steps on CPU; assert energies finite, T within ±50 K.
crucible run /tmp/spec.json --workdir /tmp/preview \
    --backend openmm --preview --n-steps 1000
```

If the preview catches a problem — wrong topology load, bad atom
selection, etc. — fix it now. Production GPU time is too expensive
to discover bugs in.

### Day 4-5 — production

```bash
# Real run; use a real workdir under your group's storage.
CRUCIBLE_SEED=42 CRUCIBLE_PRECISION=mixed \
    crucible run /tmp/spec.json --workdir ~/scratch/run01 --backend openmm
```

Crucible streams progress events; tail `~/scratch/run01/events.jsonl`
in another terminal to watch.

### Day 6-7 — analysis

Crucible doesn't replace your analysis pipeline (mdtraj, MDAnalysis,
PyEMMA, etc.). It gives you a `trajectory.dcd` + `state.xml` plus
the original spec.json. Keep all three together for reproducibility.

The Pluto walkthrough notebooks at
[`examples/walkthrough_v15_methods.jl`](../examples/walkthrough_v15_methods.jl)
+ [`examples/study_validation_gates.jl`](../examples/study_validation_gates.jl)
show the same workflow with reactive cells you can edit.

## Failure modes specific to this profile

- **"My paper says OPLS3 but Crucible doesn't have it."** Crucible's
  protein-FF allowlist is in `python/crucible/spec.py:PROTEIN_FF`.
  OPLS3 isn't in there because Schrödinger's parameters aren't
  freely redistributable. Workaround: use `amber14sb` and document
  the substitution as a known limitation (your reproduction will
  diverge from the paper's exact result).
- **"The LLM didn't pick up my paper's specific salt concentration."**
  Add it to the Methods snippet you feed in. The LLM only knows
  what's in the text. If the paper says "physiological salt" without
  a number, the LLM will (correctly) guess and tag it `assumed`.
- **"`crucible health` keeps failing on Gate 3."** Gate 3 is
  backend loadability — usually a topology/coordinates path issue.
  Check your `system.source.topology` and `coordinates` paths in
  `spec.json`. Crucible doesn't auto-build topologies (BYO-topology
  rule, AGENTS.md §4); you supply the `.parm7` and `.rst7`.
- **"I don't have an API budget for LLM calls."** Use the local-LLM
  path: [`docs/ON_PREM.md`](ON_PREM.md) walks through Ollama with
  Qwen2.5-Coder 7B. Runs on consumer GPU; sufficient for the
  protocol-extraction task.
- **"My production run crashed at hour 3 with non-finite energies."**
  This is what the preview run was meant to catch. Re-check Gate 4
  output from the preview; the bug is usually in how the topology
  was prepared (clashing residues, missing hydrogens, incorrect
  termini).

## When to read X next

Pick based on what just happened:

- *Production run completed cleanly* → analysis tutorials in your
  field; Crucible's job is done.
- *Production run was wrong* →
  [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) for
  what kinds of errors are common, and
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) for
  the systematic-verification procedure.
- *I want to add my paper to the benchmark* →
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) +
  `python -m crucible benchmark add --paper-id … --doi … --title …`.
- *I'm running a lot of papers in batch* →
  [`docs/CORPUS_DESIGN.md`](CORPUS_DESIGN.md) and
  `python -m crucible corpus fetch --author "Your PI Name"`.
- *I want to extend the IR* →
  [`docs/POWER_USERS.md`](POWER_USERS.md).

## See also

- [`docs/HOW_TO_READ.md`](HOW_TO_READ.md#for-newcomers-to-md) — the
  reading-side companion to this task-side doc.
- [`docs/GLOSSARY.md`](GLOSSARY.md) — terms you'll meet (MDSpec,
  IR, gates, provenance) explained without circular references.
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) Tier 1 messaging
  — the academic OSS framing this profile sits inside.
