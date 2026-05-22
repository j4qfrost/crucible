# Commercial validation plan (180-day sprint)

Companion to [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md). The strategic
18-month plan keeps optionality across academia, OSS, and business.
**This** plan is the 180-day operational layer below it: explicit kill
criteria, a weekly cadence, capped spend, and a single binary
go/no-go at the 6-month mark on the *commercial* path. If the
commercial bet doesn't clear the gate, the project pivots cleanly to
the academic/OSS path (Phase 2a/2b in the strategic plan), which the
work below leaves intact regardless.

This plan operationalizes the salt-mines verdict from
`~/Projects/salt-mines/reports/2026-04-28` (run against 7 originated
projects on 2026-04-28; the four-expert panel — financial / risk /
market / technical-feasibility — produced the action items + scores
this plan is built on).

## Source verdict (one-paragraph summary)

The salt-mines panel ranked Crucible #2 by `biggest` (4.56) and #2 by
`riskiest` (36.05) of 7 projects. Expected return E=1.99×, p50=0.96×,
**p90=8.25× (highest of the field)**, p10=0.085 — i.e. a meaningful
chance of near-total loss. Modal outcome (45%) is **stall, $0
revenue**, driven by *8 hrs/week founder bandwidth + zero customer
pipeline*. Variance is dominated by three brittle links: LLM
extraction → IR → renderer. Pharma IP policies often forbid sending
unpublished protocols to third-party LLM APIs, which can kill
enterprise deals before they start.

```
| metric          | value  | reading                                    |
|-----------------|--------|--------------------------------------------|
| E (return mult) | 1.99×  | positive expected value                    |
| p10             | 0.085  | near-total loss is plausible               |
| p50             | 0.96×  | median outcome is slightly under break-even|
| p90             | 8.25×  | best in the portfolio of 7                 |
| sharpe-like     | 0.148  | upside is real but heavily prob-discounted |
| capital_needed  | $4,750 | small absolute, large relative to bandwidth|
| time_horizon    | 27 mo  | longer than the 6-mo commercial gate       |
| confidence      | 0.46   | panel hedges meaningfully                  |
```

The panel's bottom-line: "Treat the next 90 days as a
**commercial-validation sprint**, not a build sprint."

## The 6-month commercial gate

> **By 2026-10-29: one signed LOI or one paid pilot, or pivot to the
> academic/OSS path.**

This date is the load-bearing constraint of the plan. Every milestone
below either advances toward the gate or falls outside the commercial
hypothesis. The pivot is *not* a failure — it is the deliberate fork
to Phase 2a/2b of `docs/ADOPTION_PLAN.md`, which the panel rated as a
modal-30% scenario worth ~2× return on the same artifact, just on a
different distribution channel.

## Constraints (load-bearing; everything below derives from these)

- **8 hrs/week founder bandwidth.** Not 16, not 40. Every deliverable
  is sized against this.
- **$5K capital cap, tranched.** Spend gates below.
- **No paid sales staff.** All outreach is founder-direct.
- **Single-stream attention.** Don't run salt-mines pivots and
  Crucible commercial sprint concurrently — pick one as primary
  through the 6-month gate.
- **Pharma IP constraint is real.** Anthropic-API-only is a deal
  blocker for ~half the addressable buyers. Local-LLM mode unblocks
  the conversation; this is non-optional for commercial validation.

## Spend allocation ($5K cap, tranched)

Per panel recommendation, with explicit gates:

| Tranche | Cap   | Trigger to release          | Allocation                          |
|---------|-------|------------------------------|-------------------------------------|
| 1       | $1.5K | unlock immediately           | LLM credits + cloud for benchmark   |
| 2       | $1.5K | ≥3 warm leads + ≥1 demo call | one conference (ACS COMP or RSE)    |
| 3       | $2.0K | first paid pilot or LOI      | reserve — pilot infrastructure      |

**Hard rule: do not spend Tranche 2 on a booth.** Conferences are
relationship leverage, not lead-gen tables. The financial_analyst's
ranking specifically downgrades booth spend.

### Warm-lead qualification rubric

Tranche 2 releases on "≥3 warm leads," and the Phase A success
metrics and kill criteria all key off warm-lead count. "Warm" must
therefore be a defined, observable state — not a gut call. A lead is
scored on the **observable actions it has taken**, not on how
promising the conversation felt.

| Tier | Definition | Observable criteria (the lead has done these) | Counts as |
|---|---|---|---|
| **Cold** | Identified target, no contact or no response. | On the outreach list; ≤1 outreach touch; no reply. | not a lead |
| **Lukewarm** | Two-way contact, but no commitment of their time or budget. | Replied to outreach (even a "not now"); *or* opened/completed the Loom; *or* asked a clarifying question. | pipeline only |
| **Warm** | Has invested their own time or named a concrete path forward. **Two or more** of the criteria at right. | Held a 15-min+ call; *and/or* requested a follow-up or a deeper demo; *and/or* named a budget number or a timeline; *and/or* introduced you onward to a colleague or decision-maker; *and/or* asked for the POC scope doc. | toward the ≥3 trigger |
| **Hot** | Warm, plus a near-close signal. | Verbally agreed to a pilot, asked for an LOI/POC draft, or looped in procurement. | toward Phase B "near close" |

Rules for applying the rubric:

- **Warm = two or more warm-tier criteria.** A single 15-minute
  call with no follow-up request is *lukewarm* — a polite meeting is
  not commitment. Two independent signals (call + budget mention,
  or demo request + onward intro) clear the bar.
- **Score the action, not the affect.** "They sounded really
  interested" is not a criterion. "They asked for the POC scope
  doc" is.
- **Record the tier in `outreach.csv`** with the date it changed
  and which criterion moved it. The warm-lead *count* the spend
  tranches and kill criteria cite is a `COUNT` over this column —
  it must be reconstructable from the sheet, not from memory.
- **Decay.** A warm lead with no two-way contact for 6 weeks
  reverts to lukewarm until re-engaged. Stale leads don't keep
  Tranche 2 unlocked.

## Phase A — 90-day commercial validation sprint (weeks 1–13)

The next 13 weeks are concrete, weekly-cadenced, and prioritize
*evidence collection* over *feature building*. Every week ships
artifacts the panel will recognize as commercial signal.

### Week 1 (immediate) — outreach + benchmark scoping

- [ ] **10 cold emails** to comp-chem PIs at top-30 US/EU schools.
      Template: 60-second Loom + one paragraph + ask for a 15-min call.
      Track in a single sheet (`outreach.csv`).
- [ ] **5 cold emails** to pharma CADD leads (LinkedIn → email pattern).
      Same template; explicit mention of on-prem mode roadmap.
- [ ] **Pick 20 published MD papers** with ground-truth protocols
      (kinase FEP, GPCR membrane, FEP+ benchmarks). Build the URL/DOI
      list. This becomes the hallucination benchmark dataset.
- [ ] **Local-LLM mode scoping doc** — 1-page spec of the Ollama path.
      Don't implement yet; gate on Week-3 demo signal.

Owner: solo. Wall-clock: ~6 hrs (within bandwidth).

### Weeks 2–3 — hallucination benchmark v1

- [ ] **Run Crucible against the 20 papers.** Capture
      `(paper, MDSpec, ground_truth_diff)` for each.
- [ ] **Per-paper accuracy score** — exact-match on
      protein FF, water model, ensemble, dt, T, duration, NPT
      pressure, FEP λ-window count. Eight binary axes, score = sum.
- [ ] **Publish results as a docs page** at
      `docs/HALLUCINATION_BENCHMARK.md`. Aggregate score table + per-paper
      detail. Honest about misses; don't cherry-pick.
- [ ] **First demo calls land** (3–5 of the 15 cold emails). Note
      objections in `outreach.csv` for pattern-matching.

This is the technical-feasibility expert's #1 action item:
"a false-pass validator is worse than no validator." A published
benchmark is the only credible answer.

### Weeks 4–6 — local-LLM mode (gated on Week-3 signal)

- [ ] **If demo calls surfaced ≥1 IP-policy block:** implement the
      `LocalProvider` (`src/llm/LocalProvider.jl`) backed by Ollama
      against `qwen2.5:7b-instruct` or `gemma3:9b`. The schema-bind path
      mirrors `AnthropicProvider`; use Ollama's structured-output flag.
- [ ] **End-to-end smoke** — run the 20-paper benchmark with the local
      model. Accuracy will be lower than Claude; capture the delta.
- [ ] **Document** at `docs/ON_PREM.md`: install path, hardware ask
      (consumer GPU sufficient for Qwen2.5-7B), expected accuracy
      tradeoff vs Claude. **This document is the pharma IP unlock.**
- [ ] **If demo calls did *not* surface IP block:** skip local-LLM,
      reallocate bandwidth to weeks 7–9 GROMACS scoping.

Decision lives at the end of Week 3; track in `commercial-log.md`.

### Weeks 7–9 — GROMACS exporter scoping

- [ ] **Add a GROMACS renderer stub** at `src/backends/GROMACSBackend.jl`.
      Render the 13 templates; assert schema validity; do not yet
      implement `run!`. Coverage: ~70% of MD-paper protocols (the
      excluded 30% are FEP+/REST2-specific).
- [ ] **Document supported subset** at
      `docs/GROMACS_SUBSET.md`. Be explicit about what's not yet
      runnable.
- [ ] **Outreach round 2** — second batch of 10 cold emails, this
      time citing the benchmark + GROMACS path. Refined pitch:
      *"protocol-extraction-as-a-service, not Julia evangelism."*

This is the technical-feasibility expert's TAM-cap concern: Julia +
OpenMM only excludes the GROMACS half of the field. Even a partial
exporter de-risks the Julia-adoption objection.

### Weeks 10–13 — pilot conversion push

- [ ] **5 deep follow-ups** with the most-engaged warm leads. Goal:
      one signed LOI or one paid POC scope.
- [ ] **Public publication of the benchmark** — a blog post or arXiv
      preprint. Title: *"Accuracy of LLM-extracted molecular-dynamics
      protocols: a 20-paper benchmark."* This doubles as the citation
      moat in `docs/ADOPTION_PLAN.md` Phase 1.
- [ ] **First decision checkpoint** at Week 13. Status report against
      Phase A goals (table below).

### Phase A success metrics (week-13 checkpoint)

| Signal                                   | Threshold                  | If miss…                              |
|------------------------------------------|----------------------------|----------------------------------------|
| Cold emails sent                         | ≥30                        | acknowledge bandwidth gap              |
| Demo calls held                          | ≥3                         | refine pitch; extend Phase A by 4 wks  |
| Hallucination benchmark published        | yes                        | block — non-negotiable                 |
| Local-LLM mode (if Week-3 signal)        | demo-able                  | block on pharma conversations          |
| GROMACS-exporter renderer (subset)       | ≥10/13 templates compile   | revise scope                           |
| Warm leads on the verge of LOI           | ≥1                         | reassess gate at Week 26               |

## Phase B — 90–180-day pilot conversion or pivot (weeks 14–26)

Two parallel tracks, gated on Phase A signal:

### Track 1: pursue the LOI (if Phase A surfaced ≥1 warm lead near close)

- [ ] **Pilot scope doc** — 1-page describing what a 30-day paid POC
      looks like. Pricing: $5K–$15K for protocol-extraction-as-a-service
      against the buyer's internal paper backlog.
- [ ] **Reference architecture for on-prem deployment** — single-node
      Docker compose, Ollama + Crucible, ~2-hour install. Sized for
      a pharma desktop or a single-GPU workstation.
- [ ] **Conference attendance** (Tranche 2) — ACS COMP or
      Open-Source-Software-for-Scientists. Goal: ≥10 hand-shake
      conversations, ≥3 follow-ups booked.
- [ ] **Close at least one** by Week 26.

### Track 2: maintain Phase 2a/2b optionality (always-on)

- [ ] **Monthly OSS hygiene release.** Tag once a month even with no
      headline feature, so the changelog stays unbroken.
- [ ] **One JOSS-paper-equivalent draft** in the background — the
      methods paper from `docs/ADOPTION_PLAN.md` Phase 1. Submission
      gated on Phase A benchmark publication.
- [ ] **Maintain `docs/ARCHITECTURE.md` + `docs/POWER_USERS.md` +
      `docs/HOW_TO_READ.md`** — already shipped; small touch-ups
      monthly.

If the gate fails at Week 26, Track 2 is what survives. The artifact
remains a citable, OSS-shipped, reproducibly-tested research codebase —
which is the financial_analyst's "30% scenario, ~2× return" path.
The work below the line in this document is *not* discarded if
the commercial bet doesn't land; it converts to inputs for the
strategic plan's academic/OSS phases.

## Kill criteria (must each be tested at Week 26)

The salt-mines panel was unanimous that pre-committed kill criteria
are the only protection against sunk-cost drift on 8-hr/week founder
bandwidth. Three explicit triggers:

1. **No signed LOI or paid pilot by 2026-10-29.** Commercial path
   ends; pivot to Phase 2a/2b.
2. **Per-eval LLM cost > $2 uncapped after the benchmark publishes.**
   Unit economics blocker; Sonnet-or-local-only thereafter.
3. **Founder hours sustained > 12/week for >4 weeks.** Bandwidth
   discipline failure; either deliberately scale back commercial
   activity or recruit a cofounder before continuing.

These are *and*-conditions for staying on the commercial path; any
one trip is sufficient cause to pivot.

## What this plan deliberately doesn't do

- **No fundraising activity.** A pre-seed conversation in 2026 is
  premature without ≥1 pilot revenue or ≥1 LOI; the $5K cap covers
  the validation question without it.
- **No hiring.** A part-time contractor for benchmark curation could
  accelerate Weeks 2–3 by ~2 weeks; deferred until Tranche 3
  unlocks.
- **No premium tier or self-serve product.** The hypothesis under
  test is *protocol-extraction-as-a-service*, sold person-to-person.
  Self-serve is a Phase-3 question after pilot evidence exists.
- **No new IR features.** The IR is the moat; new stage types or
  new templates only land if a pilot conversation surfaces a
  blocking gap. Resist roadmap drift.

## Signals to watch (passive instrumentation, no extra time cost)

- **GitHub stars + clones** (weekly check, 1 minute). Validates the
  OSS-path hypothesis even while pursuing commercial.
- **`outreach.csv` response rate.** <10% is a pitch problem;
  >20% is a real signal.
- **Hallucination benchmark page traffic** after Week 6 publication.
  Validates that the technical-credibility argument lands.
- **Conference attendee follow-up rate** (Track 1, post-conference).
  Pharma CADD culture is conservative; <30% follow-up is normal.
  <10% is a positioning failure.

## See also

- [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) — strategic 18-month
  plan; this doc is the 180-day operational layer below it.
- [`musings/scaling_modes.md`](../musings/scaling_modes.md) — analysis
  of the academia/OSS/business modes; salt-mines verdict mostly
  agrees with its risk weighting.
- [`musings/ecosystem_alternatives.md`](../musings/ecosystem_alternatives.md)
  — Phase 2b Python bindings (shipped v1.24); the GROMACS exporter
  scoped above is the renderer-side analog.
- `~/Projects/salt-mines/reports/run-2026-04-28.md` — full source
  verdict + per-expert reasoning.
- `~/Projects/salt-mines/reports/crucible.verdict.md` — coordinator
  synthesis specific to Crucible (the document this plan
  operationalizes).
