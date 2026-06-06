# Strategy feedback loop

Companion to [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md),
[`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md),
and [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md). Those three are
written *once* and then carry decision gates, KPI thresholds, and
calibration tables forward in time. This doc is the *maintenance
contract* for them: how real adopter evidence flows back in and
revises the plans, on a fixed cadence, with the revision recorded
the same way every other change to this repo is.

The gap this closes: the strategy docs are detailed and honest, but
nothing documents *who reads the signal* or *when the plan gets
edited in response*. Without that ritual, the plans drift from
aspirational to stale — the worst failure mode the
[`docs/ADOPTION_STRATEGY_PLAYBOOK.md`](ADOPTION_STRATEGY_PLAYBOOK.md)
calls out for the profile docs, applied one level up to the plans
themselves.

## The review cadence

Two nested rituals, aligned with the checkpoints the existing docs
already use.

| Ritual | Cadence | Trigger | Scope |
|---|---|---|---|
| **Monthly signal sweep** | First Monday of the month | calendar | Collect the signals below; note deltas; decide whether anything trips a *review* (not yet a revision). ~30 min. |
| **Quarterly strategy review** | Aligned with the campaign's week-13 checkpoint and the commercial plan's Week-13 / Week-26 gates | calendar + gate dates | Read the month's notes against the decision gates and KPI thresholds; revise the plan docs where evidence demands it. ~2 hrs. |

The quarterly review is deliberately pinned to dates the plans
*already name* — `docs/COMMERCIAL_VALIDATION_PLAN.md`'s Week-13
checkpoint (Phase A success metrics) and Week-26 kill-criteria test,
the `docs/CAMPAIGN_2026Q2.md` week-13 KPI dashboard, and
`docs/ADOPTION_PLAN.md`'s end-of-Phase gates. Don't invent a new
calendar; the feedback loop runs *on the checkpoints the plans
ship with*.

The monthly sweep is the lighter ritual. It exists so a quarterly
review is never a surprise: by the time a gate date arrives, three
monthly notes already show the trend.

## What signals get collected

All of these are signals the plan docs already name — the feedback
loop just makes "collect them on a cadence" explicit. No new
instrumentation.

| Signal | Source | Named in | What a bad reading means |
|---|---|---|---|
| **Cold-email reply rate** | `outreach.csv` | COMMERCIAL_VALIDATION_PLAN "Signals to watch"; CAMPAIGN KPI dashboard | <10% is a pitch problem; >20% is real signal. |
| **Demo calls held** | `outreach.csv` + `commercial-log.md` | COMMERCIAL_VALIDATION_PLAN Phase A metrics; CAMPAIGN KPI dashboard | <3 by Week 13 → refine pitch, extend Phase A. |
| **Warm-lead count** | `outreach.csv`, scored by the rubric in COMMERCIAL_VALIDATION_PLAN | COMMERCIAL_VALIDATION_PLAN spend tranches + Phase A metrics | <3 leaves Tranche 2 locked; <1 near-close reassesses the gate. |
| **Onboarding completion** | first-touch QA (ADOPTION_PLAN deliverable 0.4); onboarding-session notes | ADOPTION_PLAN Phase 0; ADOPTION_STRATEGY_PLAYBOOK "Maintenance" | A profile's 30-minute path that now takes 45 is a regression. |
| **Time-to-value drift** | manual run of each `USER_PROFILE_*.md` 30-minute path | ADOPTION_STRATEGY_PLAYBOOK "Maintenance" | Drift past the cadence bound (≤30 min / 1 day / 1 week / 30 days) → fix the path, not the bound. |
| **Failure modes hit** | adopter reports, demo-call objections in `outreach.csv` | ADOPTION_STRATEGY_PLAYBOOK profile-shape §5 | A new real failure mode → add it to the matching `USER_PROFILE_*.md`. |
| **Benchmark page traffic + inbound links** | GitHub Pages analytics | COMMERCIAL_VALIDATION_PLAN "Signals to watch"; CAMPAIGN asset #2 KPI | No incoming .edu/CADD-blog links after Week 6 → the credibility argument isn't landing. |
| **GitHub stars + clones** | weekly 1-minute check | COMMERCIAL_VALIDATION_PLAN "Signals to watch"; ADOPTION_PLAN Phase 1 gate | Validates the OSS-path hypothesis regardless of commercial track. |
| **Per-eval LLM cost** | benchmark run logs | COMMERCIAL_VALIDATION_PLAN kill criterion #2 | >$2 uncapped → unit-economics blocker. |
| **Founder hours/week** | self-report | COMMERCIAL_VALIDATION_PLAN kill criterion #3 | >12/week sustained for >4 weeks → bandwidth-discipline failure. |

The monthly sweep records each as a one-line delta in
`commercial-log.md` (the same log `docs/COMMERCIAL_VALIDATION_PLAN.md`
already designates for the Week-3 local-LLM decision). No dashboard,
no tooling — a flat log entry per month is the artifact.

## How each plan doc gets revised

Each plan doc has a different revision surface. Match the revision
to the doc.

### `docs/ADOPTION_PLAN.md` — decision gates

The 18-month plan's load-bearing structures are the **end-of-phase
decision gates** (Phase 0, Phase 1's 9-month branch point, the
"all three weak" step-down). Revise here when:

- A gate's *thresholds* no longer match observed reality — e.g. if
  ≥5 citations turns out to be the wrong bar for "healthy academic
  interest," edit the number and say why.
- A gate's *signals* are unmeasurable as written — replace with a
  signal the monthly sweep can actually collect.
- The plan "looks naive" — the doc itself invites a *"what we got
  wrong"* section ("How to read this plan"). Adding that section is
  a sanctioned revision, not a rewrite.

Don't silently re-baseline a gate you're about to fail. Edit the
gate *before* the checkpoint, with the evidence, or test it as
written and record the miss.

### `docs/COMMERCIAL_VALIDATION_PLAN.md` — kill criteria + spend tranches

The 180-day plan's load-bearing structures are the **kill criteria**
and the **spend-tranche triggers**. Revise here when:

- A monthly sweep shows a kill criterion is *about to* trip — the
  review surfaces it; it does not pre-emptively soften it. Kill
  criteria are "pre-committed protection against sunk-cost drift";
  weakening one needs an explicit, logged rationale.
- A spend-tranche trigger is ambiguous in practice — e.g. "≥3 warm
  leads" was under-specified until the warm-lead rubric was added.
  Tighten definitions; don't move the count.
- Phase A success-metric thresholds miss and the doc's own "If
  miss…" column prescribes a response (extend Phase A, revise
  scope, reassess at Week 26). Apply that response; record it.

### `docs/CAMPAIGN_2026Q2.md` — KPI thresholds + assets

The campaign doc's load-bearing structures are the **week-13 KPI
dashboard** and the **campaign assets table**. Revise here when:

- A KPI threshold proves mis-calibrated against the panel benchmark
  (e.g. the ≥15% reply rate) — adjust with the observed rate cited.
- An asset's single KPI is unmeasurable or the asset slipped — note
  it; the campaign is quarter-pinned, so a missed asset is recorded,
  not retroactively deleted.
- A messaging lead consistently underperforms in demo-call
  objections — revise the messaging stack, staying inside the
  campaign's honest-constraints rules (no fabricated traction, the
  35-email cap, no spam).

### `docs/USER_PROFILE_*.md` — failure modes + 30-minute paths

Per `docs/ADOPTION_STRATEGY_PLAYBOOK.md` "Maintenance": add a
failure mode when a real adopter surfaces one; prune a failure mode
unhit for 6+ months; fix a 30-minute path that has drifted past its
time bound. The feedback loop schedules this — the playbook already
defines *how*.

## Who triggers a revision, and how it is recorded

**Trigger.** The maintainer, at the quarterly strategy review, is
the only party who edits a plan doc. The monthly sweep can *flag* a
doc for review but does not itself change one — this keeps the plans
from thrashing on a single month's noise. An adopter report or a
demo-call objection is *evidence*, not a trigger; it lands in
`outreach.csv` / `commercial-log.md` and is read at the next review.

**Recording.** A strategy-doc revision is an ordinary repo change
and follows the conventions in [`AGENTS.md`](../AGENTS.md):

1. **Branch.** A `docs/`-prefixed branch (e.g.
   `docs/q3-strategy-review`).
2. **Commit.** Conventional-ish, milestone-tagged, with a body that
   explains *why* — the body should name the signal that forced the
   revision and quote the reading (e.g. "reply rate held at 7% over
   3 monthly sweeps").
3. **CHANGELOG.** Add a `### vX.YY` entry under `## Unreleased` in
   [`CHANGELOG.md`](../CHANGELOG.md) — strategy-doc revisions get a
   version bump like any other change, so the revision history is
   one linear, citable record.
4. **Checks.** `tools/check_doc_links.py` (cross-references resolve)
   and `tools/check_workspace.py` (the doc-shape + link invariants)
   must pass before the revision merges.

The result: at any point, `CHANGELOG.md` plus the git log of the
`docs/` plan files *is* the audit trail of how the strategy
responded to evidence. No separate revision log to maintain.

## Anti-patterns

Named so a future reviewer can call them out, in the spirit of the
playbook's profile-shape anti-patterns.

### The Frozen Plan

A plan doc that is never edited after it ships, so it slowly
diverges from reality until nobody trusts it. The monthly sweep
exists specifically to prevent this — a plan with no `CHANGELOG`
revisions after two quarters of real adopter activity is itself a
warning sign.

### The Silent Re-Baseline

Editing a decision gate or kill criterion *to pass it*, without
recording the evidence and rationale. This defeats the entire point
of pre-committed gates. Every threshold change must cite the signal
that justified it, in the commit body.

### The Noise Chase

Revising a plan on one month's anomalous reading. The two-tier
cadence is the guard: monthly sweeps *observe*, the quarterly review
*decides*. A signal must persist across the trend, not spike once.

### The Untraceable Revision

A plan edited directly on `main` with a vague commit message and no
`CHANGELOG` entry. The revision becomes invisible the moment it
merges. Follow the four-step recording ritual above, every time.

## See also

- [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) — strategic 18-month
  plan; its decision gates are revised through this loop.
- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  — 180-day plan; its kill criteria + spend tranches are revised
  through this loop.
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) — Q2 campaign; its
  KPI dashboard is revised through this loop.
- [`docs/ADOPTION_STRATEGY_PLAYBOOK.md`](ADOPTION_STRATEGY_PLAYBOOK.md)
  — the playbook; its "Maintenance" section defines how
  `USER_PROFILE_*.md` docs are revised.
- [`AGENTS.md`](../AGENTS.md) — branch, commit, and CHANGELOG
  conventions every revision follows.
