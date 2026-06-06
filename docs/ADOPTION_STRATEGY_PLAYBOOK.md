# Adoption strategy playbook

Distilled from building the
[`docs/USER_PROFILES.md`](USER_PROFILES.md) index in v1.57–v1.58.
This file is the *meta*-doc: patterns that emerged while writing
the seven profile docs, useful for anyone adding the eighth (or
applying the same shape to a different project).

Companion to
[`musings/scaling_modes.md`](../musings/scaling_modes.md) (the
*strategic* analysis of academia / OSS / business modes) and
[`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) (the *operational*
campaign for one specific quarter). This doc is the *tactical*
playbook for how individual adoption-doc artifacts are shaped and
sequenced.

## Three orthogonal axes for adoption docs

Every Crucible adopter's path falls along three independent axes.
Mixing the axes produces unhelpfully-generic docs; separating them
produces docs that actually help a specific person.

| Axis | What it asks | Dimension |
|---|---|---|
| **Role** | "Who is the reader?" | grad student / pharma CADD / instructor / etc. |
| **Outcome** | "What artifact do they leave with?" | runnable script / eval doc / course module / audit report |
| **Cadence** | "How long until first value?" | 30 min / 1 day / 1 week / 1 month |

The user-profile docs in v1.57–v1.58 are organized by **role** as
the primary axis. The reading-oriented
[`docs/HOW_TO_READ.md`](HOW_TO_READ.md) is also organized by role.
The campaign doc
([`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md)) cuts by **outcome**
(reach / convert / pilot). The musings cut by **decision** (a
fourth axis we don't use for adoption docs).

Orienting around role is correct for adoption because it matches
how adopters self-identify. But the secondary axis matters too —
without an outcome, a profile doc devolves into a tour.

## The shape that worked for v1.57–v1.58

Six sections, in this order, for every `USER_PROFILE_*.md`:

1. **One-paragraph hook.** "You leave with X." Concrete artifact.
   *Not* "you'll understand the framework."
2. **Pre-flight.** Exact installs and accounts. Time-bounded.
3. **The 30-minute path.** Fastest way to a real artifact. Single-
   take terminal commands. No prose-heavy explanation between
   steps.
4. **The first-week path.** What comes after smoke. Day-by-day
   layout when the cadence is multi-day; section-by-section when
   it's parallel work.
5. **Failure modes specific to this profile.** Real pain points
   from real adopters in this role. Anti-patterns explicit.
6. **When to read X next.** Pointers to other docs, framed
   conditionally ("if production run was wrong → go here").

The 30-minute path is the load-bearing section. If the median
adopter in that role takes more than 30 minutes to produce
*anything*, the profile doc has failed regardless of how
beautifully the rest is written.

## Time-to-value calibration

The seven profiles in the index span four cadences. Calibration
that emerged:

| Cadence | What's possible |
|---|---|
| ≤ 30 minutes | One specific artifact (a transpiled spec, a coverage report, a passing health gate). |
| 1 day | An audit-quality output worth showing to a colleague. |
| 1 week | A course module / an internal eval baseline / a deployed pipeline. |
| 30 days | A management-grade decision artifact (POC eval, pilot scope). |

Don't write a profile doc that promises a sub-30-minute artifact
for something that genuinely takes a day. Don't pad a one-day
artifact into a one-week doc. Calibration honesty is what makes
the docs trustworthy.

## What goes in each section

### Pre-flight

- Exact commands (the reader copy-pastes; they don't reinvent).
- Time-bounds ("15 minutes," "1 hour"). Don't say "should be
  quick."
- Required vs. optional credentials. `ANTHROPIC_API_KEY` is
  optional for most profiles; on-prem mode is the documented
  alternative.
- One smoke check that asserts the install works. If `crucible
  doctor` fails, the rest of the doc is wasted.

### The 30-minute path

- Single shell session. Show the prompt (`$`).
- Output is the artifact, not the explanation. Show 3 lines of
  expected output; don't narrate the flags.
- One callout per gotcha, inline. "Notice: every default has a
  comment citing the source."
- End with a one-line summary of what the reader has produced.
  "That's the artifact. You now have a script that's traceable
  from paper → IR → script."

### Failure modes specific to this profile

- Format: bold question in quotes ("My paper says OPLS3 but
  Crucible doesn't have it."), then 1-3 sentences of answer.
- Real failures, not anticipated ones. If an adopter hasn't yet
  hit a particular failure mode, omit it (or move to a
  speculative-failures section flagged as such).
- Pointers to root-cause docs ("see AGENTS.md §4 for the
  BYO-topology rule") rather than restating the rule inline.

### When to read X next

- Conditional pointers, not a flat list. "If production run was
  wrong → docs/HALLUCINATION_BENCHMARK.md." Not "see also: the
  benchmark."
- Cross-reference back into the same profile when relevant.
  "Re-read the preview-run section above."
- Limit to ~5 entries. Long lists imply the doc didn't accomplish
  what it set out to.

## Profile-shape anti-patterns

What I avoided while writing v1.57–v1.58, with names so future
contributors can call them out:

### The Tour

A profile doc that walks the reader through every feature without
producing any specific artifact. Identifiable by section headers
like "Templates," "Validation Gates," "The Renderer." Replace with
sections that describe outcomes: "Reproducing a Methods section,"
"Auditing a published claim."

### The Pre-Flight Inflation

A pre-flight section that grows beyond 15 minutes for the median
case. If the install needs 2 hours of IT review, that's a real
constraint — call it out in the *outcome* (e.g. the pharma POC
profile's 30-day clock starts AFTER IT approval) rather than in
pre-flight.

### The Aspirational Failure Mode

A failure-modes section listing problems no real adopter has
actually hit yet. Failure-modes lists should be evidence-based;
"speculative failures" can live in a separate section if they
matter, clearly labeled.

### The Endless Cross-Reference

A profile doc that's mostly links to other docs. The 30-minute
path should be self-contained — copy-pasteable from the doc
without opening a second tab. Cross-references are for the
*after* state, not the *during*.

### The Missing Outcome

A profile doc whose hook says "you'll understand X" instead of "you
leave with X." Knowledge isn't an artifact; commit to a concrete
deliverable in the hook.

## When to add a profile

The bar is *real adopter, real outcome, real time-to-value
measurement*. Specifically:

1. **Real adopter.** You've spoken to (or watched) at least one
   person in that role. Speculative profiles are worse than no
   profile because they lock in wrong assumptions.
2. **Real outcome.** The artifact in the hook is concrete and
   testable. "A coverage report" passes; "an understanding of
   provenance" fails.
3. **Real time-to-value measurement.** You've watched the median
   adopter complete the 30-minute path. If you don't have data,
   profile from observation; don't guess.

If any of those is missing, write the doc as a draft (status:
`speculative`) and don't link it from the index until you have
the data.

## How profiles compose with reading guides

The split between
[`docs/USER_PROFILES.md`](USER_PROFILES.md) (task-oriented) and
[`docs/HOW_TO_READ.md`](HOW_TO_READ.md) (reading-oriented) is
deliberate. They serve different needs:

| Need | Doc |
|---|---|
| "I want to *do* something specific with Crucible." | `USER_PROFILES.md` |
| "I want to *understand* Crucible before I commit to using it." | `HOW_TO_READ.md` |
| "I want to *contribute* to Crucible." | `POWER_USERS.md` |

The same person may need different docs at different points. A
grad student starts at `USER_PROFILE_GRAD_STUDENT.md` for first
artifact, then drifts to `HOW_TO_READ.md` when they need to
understand *why* the IR is JSON, then to `POWER_USERS.md` when they
want to add a new lint rule. That's the intended flow.

## Sequencing future profile work

The seven shipped in v1.57–v1.58 cover the most-common adopter
patterns we have evidence for. Roles that are *plausible* but where
we don't yet have evidence:

- **HPC / cluster admin** — deploying Crucible at scale. Plausible
  but no one has asked yet. Wait.
- **Wet-lab biologist** — uses MD downstream of structural-bio
  experiments. Plausible; not yet seen. Wait.
- **AI/ML researcher (non-chemistry)** — interested in the
  IR-as-contract pattern as an applicable architecture. Plausible
  in adjacent domains. Wait.
- **Conference attendee skimming the project** — 5-minute first
  impression. Could be its own doc; the README's "30 seconds of
  reading" section
  ([`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 0) handles
  this surface today.

Add these only when a real adopter surfaces. Each speculative
profile is an opportunity to build a wrong assumption into the doc
set; the project benefits more from accurate-narrow than
speculative-broad.

## Maintenance

When a profile's 30-minute path drifts:

1. Run the path yourself end-to-end. If it now takes 45 minutes,
   that's a regression — fix the path, not the time bound.
2. Update failure modes when an adopter surfaces a new one.
   Prune failure modes that haven't been hit in 6+ months (the
   doc gets shorter; the project's stability gets visible).
3. Update next-reads when a referenced doc renames or moves.
4. If a profile's role description is stale (e.g. "pharma CADD
   scientist" becomes outdated as the field shifts toward
   AI-first biotech), update the role rather than retiring the
   profile.

The profile docs aren't release-pinned; they should track the
current state of the project. CI doesn't enforce 30-minute
path correctness (yet) — manual testing during onboarding sessions
is the real check.

## See also

- [`docs/USER_PROFILES.md`](USER_PROFILES.md) — the index this
  playbook explains.
- [`musings/scaling_modes.md`](../musings/scaling_modes.md) —
  the strategic frame the profile docs sit inside.
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) — the
  operational campaign that targets some of the same audiences
  through outreach rather than docs.
- [`docs/FEEDBACK_LOOP.md`](FEEDBACK_LOOP.md) — the maintenance
  contract for the plan + campaign docs: how real adopter signal
  flows back in and revises them. The "Maintenance" section above
  is the profile-doc slice of that loop.
- [`docs/POWER_USERS.md`](POWER_USERS.md) — the contributor
  onboarding doc (third orthogonal axis, alongside profile and
  reading guides).
