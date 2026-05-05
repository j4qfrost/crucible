# User profile — pharma CADD scientist (POC eval)

> **You leave with:** a 30-day evaluation deck for management. Includes:
> a scored benchmark across 10 of your internal protocols, an on-prem
> deployment against your IT-policy threat model, and a written
> per-axis accuracy comparison vs. your manual baseline.

This profile is for the audience the commercial-validation plan
([`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md))
calls Tier 2: a CADD scientist or computational lead at a pharma /
biotech who has been asked to evaluate Crucible alongside (or
instead of) Schrödinger's tooling, OpenEye, internal scripts, etc.

The decision criteria you're being graded against:

1. **Does it produce simulations that match what we'd write by hand?**
   (accuracy)
2. **Will our IP-policy team allow it?** (on-prem story)
3. **What's the integration cost into our existing pipeline?**
   (architectural fit)
4. **What happens if it gets two protocols wrong?**
   (failure mode + remediation)

This doc is structured around those four questions.

## Pre-flight (1 day, including IT review)

What you need before the 30-day clock starts:

- A single GPU workstation or dev VM. **No production data yet.**
- Approval from IT to install:
  - Julia 1.10+ (Apache 2.0, no telemetry)
  - Python 3.10+ (already approved everywhere)
  - DuckDB (MIT, embedded, no network)
  - Ollama OR vLLM OR llama.cpp (your choice; all permissive
    licenses) — see [`docs/ON_PREM.md`](ON_PREM.md)
- Approval to download a 7B-parameter open-weights model (Qwen2.5-Coder
  recommended; Llama 3.1 alternative). One-time download; no
  inference traffic to external services after that.

A pre-completed network-policy preflight is in
[`docs/ON_PREM.md`](ON_PREM.md#network-policy-preflight) — hand it
to your IT/security team for the audit pass.

## The 30-day path

A week-by-week plan that produces the four-question answer set above.

### Week 1 — install + accuracy baseline

- **Days 1-2:** Install per [`docs/ON_PREM.md`](ON_PREM.md). Run
  `crucible doctor` + `python -m crucible spec-describe`. Confirm
  the local-LLM path responds:
  ```bash
  echo "Methods: amber14sb, TIP3P, NPT, 2 fs, 300 K, 10 ns" | \
      crucible transpile --paper - --provider local
  ```
- **Days 3-5:** Run the public benchmark
  ([`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md))
  against your local model:
  ```bash
  python -m crucible benchmark run --verified-only \
      --corpus-db ~/eval/runs.duckdb \
      --llm-model qwen2.5-coder-7b \
      --out ~/eval/week1-runs.jsonl
  python -m crucible benchmark report ~/eval/week1-runs.jsonl \
      --out ~/eval/week1-report.md
  ```
  This calibrates Crucible's accuracy on a public dataset before
  you point it at your IP.

### Week 2 — internal protocol baseline

- **Days 6-8:** Pick 10 of your team's internal MD protocols. For
  each: extract the Methods-equivalent text (could be a SOP doc,
  a paper draft, or an `mdp` file with a comment header). Save as
  `~/eval/papers/<id>.txt`.
- **Days 9-10:** Stub each as a `BenchmarkEntry` via
  `python -m crucible benchmark add --paper-id <id> --doi internal/<id> --title "…"`.
  Verify each per
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md). The
  10 entries are now the eval ground truth.

### Week 3 — accuracy + iteration

- **Days 11-13:** Run the benchmark against your 10 internal
  protocols:
  ```bash
  python -m crucible benchmark run --verified-only \
      --papers-dir ~/eval/papers \
      --corpus-db ~/eval/runs.duckdb \
      --llm-model qwen2.5-coder-7b \
      --out ~/eval/week3-runs.jsonl
  ```
  Inspect per-axis accuracy:
  ```bash
  python -m crucible benchmark runs-stats ~/eval/runs.duckdb
  ```
- **Days 14-17:** For axes the LLM consistently misses, decide:
  - **Prompt fix:** edit the system prompt in
    `src/llm/Provider.jl:TRANSPILE_SYSTEM_PROMPT`. Re-run.
  - **Schema gap:** an axis isn't in the IR (e.g. OPLS3 protein FF).
    File it as a known limitation; document the workaround.
  - **Model swap:** try the 32B variant or Llama 3.1 70B (needs
    A100-class GPU). Re-run.

### Week 4 — written eval

- **Days 18-25:** Write the eval doc. Template structure:
  ```markdown
  # Crucible Eval — <YourCompany>

  ## TL;DR for management
  - Crucible scored X/Y axes correctly across 10 internal protocols.
  - On-prem deployment passes our IT preflight.
  - Per-protocol time-to-script: ~Z seconds (vs ~Q minutes by hand).
  - Recommendation: pilot / pass / re-eval next quarter.

  ## Methodology
  - Model: qwen2.5-coder-7b on local A100.
  - Public benchmark accuracy: see week1-report.md.
  - Internal benchmark accuracy: see week3-report.md.

  ## Per-axis accuracy
  …pulled from `runs-stats` JSON…

  ## Failure modes observed
  …a list of categories, not a list of incidents…

  ## Cost model
  - Compute: <X> GPU-hours/month for protocol-extraction.
  - Maintenance: <Y> FTE-hours/month estimated.
  ```
- **Days 26-30:** Present to management. The eval ships regardless
  of go/no-go decision — the data is reusable (negative results are
  signal, not failure).

## Failure modes specific to this profile

- **"Our IP team blocks installing anything that does HTTP."** The
  base Crucible CLI does no outbound HTTP (`crucible doctor`
  verifies). The LLM client (Anthropic / local) is the only HTTP
  surface; switch to local and you're network-isolated. The
  network-policy preflight in [`docs/ON_PREM.md`](ON_PREM.md) is
  exactly this audit.
- **"Qwen2.5-Coder 7B keeps misreading our internal SOP format."**
  Internal SOPs often use abbreviations the model wasn't trained
  on. Two options: rewrite the SOP excerpt as a Methods-section
  paragraph (5 minutes per SOP), or fine-tune the local model on
  ~20-50 (SOP, MDSpec) pairs (multi-week effort; usually not worth
  it for a 30-day POC).
- **"The benchmark doesn't measure what we care about."** The 10
  axes are listed in [`docs/BENCHMARK_AXES.md`](BENCHMARK_AXES.md).
  If you need an axis we don't have (e.g. RESTRAINTS_K), it's a
  schema bump — see [`docs/POWER_USERS.md`](POWER_USERS.md). For
  the POC, document the axis-coverage gap and grade against the
  axes that do exist.
- **"We need a Schrödinger format-compatible export."** Crucible
  emits OpenMM scripts (and Molly.jl for the native-Julia path).
  GROMACS export is scoped
  ([`docs/GROMACS_SCOPING.md`](GROMACS_SCOPING.md)) but not
  shipped. Schrödinger format export is not on the roadmap unless
  a pilot specifically requests it. Workaround for the POC: use
  the OpenMM script as the canonical, hand-port to your engine if
  needed.
- **"Our internal protocols use a custom force field."** Crucible
  can't validate parameters it doesn't know about. The MDSpec's
  `force_field.protein` is an enum; if your custom FF isn't in
  the allowlist, document this as a schema gap. Workaround: pick
  the closest allowed FF, document the substitution as a "would
  diverge from in-house results."

## What this POC explicitly is and isn't

**Is**: a measurement of how accurately Crucible extracts MD
protocols from text in your specific domain. The deliverable is the
eval doc; the methodology is reproducible.

**Isn't**:
- A guarantee Crucible will produce *converged* simulations. Crucible
  emits the script; convergence is your team's problem (and the
  paper's). The benchmark's `duration_ns` axis grades whether the
  LLM extracted the right duration, not whether that duration is
  scientifically sufficient.
- A free-energy-method validation. FEP-window count is one of the
  10 axes; the actual ΔG calculation isn't graded.
- A ligand-parameterization audit. Crucible defers to OpenFF /
  GAFF; the BYO-topology rule (AGENTS.md §4) means LP correctness
  is upstream of the benchmark.

If your management wants any of the above, scope a separate POC
specifically for that — Crucible's wedge is protocol fidelity, not
end-to-end correctness.

## Pilot scope after a successful POC

If the eval lands in "go," the next step is a paid 30-day pilot
scoped per [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
Phase B Track 1: $5K-$15K fixed fee, written eval as deliverable,
no ongoing commitment. Reach out to the maintainer with your eval
doc — your week-3 numbers are the conversation-starter.

## When to read X next

- *Eval lands "go"* → [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  Phase B for the pilot scope.
- *Eval lands "no-go"* →
  [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) Tier 2 messaging
  to articulate what gap killed it. Negative-result feedback is
  the most useful thing you can send the maintainer.
- *Want to change an axis the LLM keeps missing* →
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) for
  the verification procedure;
  [`docs/POWER_USERS.md`](POWER_USERS.md) for adding new axes.
- *Want to add custom adapters for your internal SOP format* →
  [`src/adapters/`](../src/adapters/) — `PDFAdapter`, `ArxivAdapter`,
  `BioRxivAdapter`, `NotesAdapter` are the existing patterns.

## See also

- [`docs/ON_PREM.md`](ON_PREM.md) — the local-LLM mode docs and
  IT-preflight script.
- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) —
  the public benchmark you'll calibrate against in week 1.
- [`docs/BENCHMARK_AXES.md`](BENCHMARK_AXES.md) — what each of the
  10 axes means.
- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  Phase B — the post-POC commercial path.
- `~/Projects/salt-mines/reports/crucible.verdict.md` — the panel
  verdict that originated the on-prem-mode and benchmark
  recommendations.
