# Hallucination benchmark

How accurately does Crucible's LLM transpile reproduce the molecular-dynamics
protocol of a published paper? This page is the canonical answer — and the
campaign's anchor (asset #2 in [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md)).

> **Status: framework shipped (v1.31), seed set in verification.** The
> framework runs end-to-end against a mock transpile; real LLM scores
> publish once the seed set is human-verified per
> [`python/crucible/benchmark/papers.py`](../python/crucible/benchmark/papers.py).
> Phase A weeks 2-3 of [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md).

## Why this matters

Every comp-chem PI and pharma CADD lead has been burned by an LLM that
produces a plausible-looking-but-physically-wrong simulation script. The
technical-feasibility expert in the salt-mines verdict put it bluntly:
*"a false-pass validator is worse than no validator."* This benchmark is
the only credible answer to the silent-correctness objection — the
positioning wedge of [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) is
provenance + a 5-gate validator, and this page is the empirical evidence
behind that wedge.

## Methodology

Each entry is a `(paper, ground-truth-protocol)` pair. The LLM is fed
the paper's text (Methods section preferred; full text or abstract as
fallback) and emits an `MDSpec`. The spec is graded on 8 binary axes:

| Axis | What it measures |
|---|---|
| `protein_ff` | Protein force field (e.g. `amber14sb`) |
| `water_model` | Water model (e.g. `TIP3P`) |
| `ensemble` | Production-stage ensemble (NVE / NVT / NPT) |
| `dt_fs` | Integration timestep |
| `temperature_K` | Production temperature |
| `duration_ns` | Production duration |
| `pressure_bar` | Barostat pressure (NPT only) |
| `fep_lambda_count` | Number of FEP λ-windows (FEP papers only) |

`None` ground truth (when the paper deliberately doesn't specify a knob)
drops the axis from both numerator and denominator. **No partial credit**
— the wedge is "did the LLM get the protocol right or not?", and partial
credit makes that signal noisy.

Full scoring code:
[`python/crucible/benchmark/scorer.py`](../python/crucible/benchmark/scorer.py).

## What's not in scope

- **Generated-script correctness.** That's Gates 1-4 of the validator
  ([`docs/PLAN.md`](PLAN.md)) — separate question, separate test surface.
- **Free-energy convergence.** A correct protocol is necessary but not
  sufficient for a converged ΔG. Convergence is downstream of the LLM
  step; this benchmark stops at the IR.
- **Ligand parameterization fidelity.** Crucible deliberately punts to
  OpenFF / GAFF for ligand FFs; the LLM doesn't pick atom types. See
  [`AGENTS.md`](../AGENTS.md) §4 (the BYO-topology hard rule).

## Honesty constraints (do not compromise)

- **No fabricated ground truth.** Every entry's `ExpectedProtocol` must
  be cross-checked against the original Methods section by a human
  before it counts. The framework enforces this — `score()` raises on
  `needs_verification` entries unless `allow_unverified=True` is set
  for dry-run measurement.
- **No cherry-picking.** The seed set is published intact, including
  the papers Crucible loses on. Hiding losses is worse than reporting
  them.
- **No pretrained-on-the-paper effects.** When known, the report flags
  papers that are likely in the LLM's training set vs. ones that aren't
  (the latter is the harder, more honest test).

## Seed set (5 papers, expanding to 20)

The starting set covers the methodological core of MD as a discipline:

1. **Lindorff-Larsen et al. 2010** — `ff99SB-ILDN` introduction.
   [10.1126/science.1187409](https://doi.org/10.1126/science.1187409)
2. **Mobley, Chodera, Dill 2007** — alchemical FEP reference.
   [10.1021/jp067192x](https://doi.org/10.1021/jp067192x)
3. **Sugita & Okamoto 1999** — REMD foundational paper.
   [10.1016/S0009-2614(99)01123-9](https://doi.org/10.1016/S0009-2614(99)01123-9)
4. **Wang et al. 2015** — FEP+ landmark.
   [10.1021/ja512751q](https://doi.org/10.1021/ja512751q)
5. **Salomon-Ferrer et al. 2013** — AMBER on GPUs.
   [10.1021/ct400314y](https://doi.org/10.1021/ct400314y)

Coverage: 1 methodology, 1 alchemical FEP, 1 REMD, 1 modern FEP+, 1
GPU-tooling. Picked for high public visibility + clearly-stated Methods
sections + diversity across MD subfields.

Expansion target: 20 total, adding cancer-area FEP (kinase + Bcl-2
patterns from [`docs/CANCER_USE_CASES.md`](CANCER_USE_CASES.md)),
membrane-protein NPT, and metadynamics CV-driven sampling.

## Reproduce

```bash
# Verification status of the seed set
python -m crucible benchmark status

# Smoke run with a mock transpile (vanilla template; CI-friendly)
python -m crucible benchmark run --mock --allow-unverified --out /tmp/runs.jsonl

# Render the markdown report
python -m crucible benchmark report /tmp/runs.jsonl --out docs/HALLUCINATION_BENCHMARK.md

# When ANTHROPIC_API_KEY (or local LLM) is set: real run
python -m crucible benchmark run --verified-only --out runs/2026-Q2.jsonl
python -m crucible benchmark report runs/2026-Q2.jsonl
```

## Adding a paper

See [`python/crucible/benchmark/papers.py`](../python/crucible/benchmark/papers.py)
for the full checklist. Short version:

1. Read the paper's Methods section.
2. Append a `BenchmarkEntry` to `_SEED_ENTRIES`. Set every axis you can
   verify; leave unstated knobs as `None`.
3. Set `status="verified"` and `verified_by="<initials> <date>"`.
4. Open a PR. The framework's tests will exercise the new entry.

## See also

- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md) —
  Phase A weeks 2-3 (this page is the deliverable).
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) — campaign asset #2.
- [`docs/CORPUS_DESIGN.md`](CORPUS_DESIGN.md) — the OpenAlex-backed
  corpus that feeds the seed-set expansion.
- [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md) —
  why the IR is what makes this benchmark possible (LLM emits JSON,
  not Python; the 8 axes are JSON paths, not regex against Python source).
- `~/Projects/salt-mines/reports/crucible.verdict.md` — the panel
  verdict that anchors the "build a hallucination benchmark"
  recommendation.
