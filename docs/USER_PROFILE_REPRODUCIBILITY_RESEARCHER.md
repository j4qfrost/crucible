# User profile — reproducibility-minded researcher

> **You leave with:** a structured diff between a published MD
> protocol and your reproduction attempt. Includes which fields
> matched, which the LLM had to guess, and which the paper
> deliberately left unspecified. Audit-quality output suitable for
> a journal-club discussion or a referee report.

This profile is for someone who's read a published paper and wants
to *check* it — not extend it. Could be:

- A graduate student running an MD protocols course's "reproduce
  this paper" assignment.
- A paper referee checking that a Methods section is sufficient to
  reproduce the work.
- A senior researcher revisiting a published claim that doesn't
  replicate in their lab.
- An author preparing a paper revision who wants to confirm their
  Methods section is unambiguous.

The wedge: Crucible's IR makes it explicit *which knobs the paper
states vs. assumes*. That's exactly the audit a reproducibility
review needs.

## Pre-flight (15 minutes once)

What you need:

- The published paper (PDF or open-access HTML). The Methods
  section is the load-bearing input.
- Crucible installed (per
  [`docs/USER_PROFILE_GRAD_STUDENT.md`](USER_PROFILE_GRAD_STUDENT.md)
  pre-flight).
- Optional: an `ANTHROPIC_API_KEY` or a local LLM
  ([`docs/ON_PREM.md`](ON_PREM.md)). For a single-paper audit, the
  Anthropic API cost is roughly $0.05.

## The 30-minute path — the audit artifact

```bash
# 1. Extract the paper's Methods section.
$ pdftotext -layout paper.pdf - | sed -n '/Methods/,/Results/p' \
    > methods.txt

# 2. LLM transpile.
$ crucible transpile --paper methods.txt --out spec.json

# 3. The audit-relevant view: provenance coverage.
$ crucible coverage spec.json
```

The coverage output is the artifact:

```
coverage_score: 0.74
total_numeric_fields: 23
fields_with_provenance: 17
by_source:
  paper: 12          ← stated in the Methods section
  paper_default: 4   ← implied by context
  assumed: 1         ← LLM had to guess
  user: 0
missing_paths:
  - protocol[3].friction_ps          ← NOT in the paper
  - system.solvent.padding_nm        ← NOT in the paper
  …
```

This is the audit output. For each field:

- **`paper`** — the paper stated this explicitly. Reproducing the
  protocol with this value is faithful.
- **`paper_default`** — the paper implied this (e.g. "MD with
  AMBER" → `amber14sb` is the modern default). You SHOULD note this
  in your audit; the paper authors made an implicit assumption.
- **`assumed`** — the LLM had to guess. **This is the audit's
  red-flag column.** Either the paper omitted a load-bearing knob,
  or the LLM extracted the wrong value.
- **`missing_paths`** — fields with no provenance entry at all.
  These are likely fields the IR has but the paper didn't address
  (e.g. `padding_nm` on a paper from before solvent-buffer reporting
  was standard).

### Manual cross-check

For each `assumed` or missing field, look at the paper PDF
yourself. Three outcomes:

- **The paper actually states it** — the LLM missed the extraction.
  File a benchmark issue (
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) — your
  audit IS a benchmark verification).
- **The paper deliberately omits it** — note as "paper does not
  specify" in your audit. This is a *paper* deficiency, not a
  Crucible miss.
- **The paper implies it through context** (e.g. "we used the
  standard FF14SB defaults") — note the implicit assumption. A
  reproduction by a different reader could choose different
  defaults; the paper has a reproducibility gap.

## The first-week path (depth audit)

For audits that go beyond a single Methods section.

### Day 1-2: structural diff

If you have a known-good reference (a previous reproduction, an
FAIR-era lab notebook, the authors' deposited code):

```bash
# Compare the LLM-extracted spec against your reference.
crucible diff --intent reference.json spec.json --format json
```

The `--intent` mode reports semantic differences (different protein
FF, different ensemble) and ignores noise (key-order, comment
differences). The output is a structured list ready for your audit.

### Day 3-4: preview-run reproducibility

```bash
# Build the topology + coords from the paper's PDB. Then:
crucible run spec.json --workdir audit-preview --backend openmm \
    --preview --n-steps 10000

# Extract the energy + temperature trajectory.
tail -200 audit-preview/events.jsonl | jq '.energy_kj_mol' > energy.txt
```

If the preview run's average energy + temperature don't match what
the paper reports for its first 10 ps, that's a reproducibility
flag — most often a topology issue, occasionally a force-field
parameter divergence.

### Day 5-7: write the audit

Your audit doc should include:

1. **Headline finding.** "Of N protocol axes, K were stated
   explicitly, M were implied, P were guessed, Q were missing.
   Reproducibility verdict: green / yellow / red."
2. **Per-field table.** Pulled from `crucible coverage` JSON,
   annotated with your manual cross-check.
3. **Preview-run divergences.** What you saw in the first 10 ps
   that the paper didn't predict.
4. **Recommendations to authors** (if you're writing a referee
   report). Specific "Methods §X.Y should specify the friction
   coefficient" rather than "Methods are unclear."

## Failure modes specific to this profile

- **"The Methods section is in a Supplementary Information PDF I
  can't access."** Same workflow, but the input is the SI. Many SIs
  are open even when the main paper is paywalled. If both are
  paywalled, escalate to your library's interlibrary loan; ad-hoc
  workarounds make the audit non-reproducible.
- **"The paper uses a force field not in Crucible's allowlist
  (e.g. OPLS3)."** Not a reproducibility failure of Crucible — a
  schema gap. Document the gap in your audit ("Crucible's allowlist
  doesn't include OPLS3; substituted amber14sb for the
  reproduction; ΔG comparison invalid"). File a Crucible issue if
  you think the gap should close.
- **"`crucible coverage` says paper_default for a field I think the
  paper stated."** The LLM might have missed it. Re-read the paper
  carefully; if you find the explicit statement, file as a benchmark
  miss per
  [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md).
  Your audit becomes a verification PR.
- **"My preview run blew up at step 100."** Not a Crucible bug
  (almost certainly). Topology / coordinate prep is upstream of
  Crucible — see the BYO-topology rule (AGENTS.md §4). Your audit
  finding: the paper's described topology doesn't reproduce
  cleanly; you'll need the authors' deposited input files (or to
  rebuild from PDB very carefully) to continue.

## The audit becomes a benchmark contribution

Once you've audited a paper to "verified" quality, the same data
is the input the hallucination benchmark needs. Convert your audit
to a benchmark entry:

```bash
python -m crucible benchmark add \
    --paper-id <slug> \
    --doi <doi> \
    --title "<title>"

# Then the interactive verifier walks you through the 10 axes.
python -m crucible benchmark verify --paper-id <slug> --initials <ABC>
```

A PR with the verified entry ships in the next release. Your audit
work has compounding value beyond your own paper-of-interest.

## When to read X next

- *I want to check this paper actually runs* → re-read the
  preview-run section above; promote to a real run if the preview
  is clean.
- *I want to compare against the authors' deposited code* →
  `crucible diff --intent` is the structural diff;
  [`docs/HOW_TO_READ.md`](HOW_TO_READ.md) for navigating an
  unfamiliar codebase quickly.
- *I want to write up the methodology of my audit* →
  [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md)
  + [`docs/BENCHMARK_AXES.md`](BENCHMARK_AXES.md) cite the same
  framework you're using.

## See also

- [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) — the
  flip-side procedure when your audit becomes a benchmark
  contribution.
- [`docs/HOW_TO_READ.md`](HOW_TO_READ.md#for-the-reproducibility-minded-researcher)
  — reading-side companion.
- [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md)
  — why the IR design makes the audit clean (provenance is a
  first-class field, not a comment).
