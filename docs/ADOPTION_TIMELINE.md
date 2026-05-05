# Adoption timeline

When each [`USER_PROFILE_*.md`](USER_PROFILES.md) audience gets
actively onboarded, mapped against the 18-month
[`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) and the 180-day
[`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md).

Companion to [`docs/ADOPTION_STRATEGY_PLAYBOOK.md`](ADOPTION_STRATEGY_PLAYBOOK.md)
(the tactical *how* of writing profile docs); this doc is the
*when* of activating each profile.

## Why sequencing matters

Adopter profiles are not all activated simultaneously. Each profile
has prerequisites — campaign assets that must exist, technical
maturity that must ship, data the project must have collected.
Activating a profile before its prerequisites land produces
dropouts (the adopter hits a missing piece, leaves, doesn't come
back). Activating after the prerequisites land is wasted opportunity
cost.

The right sequencing: **activate each profile in the *first* phase
its prerequisites are met, and not before**.

## The timeline

```
Phase 0 — Stabilize        (months 0-3)
Phase 1 — Citation moat    (months 3-9)
Phase 2a — Academic        (months 9-18)
Phase 2b — OSS             (months 9-18)
Phase 2c — Business        (months 9-18)
```

| Profile | Activates | Why now |
|---|---|---|
| **Grad student / postdoc** | Phase 0 (months 0-3) | Needs only a working install + a paper. Always-on once the CLI is stable. |
| **Reproducibility-minded researcher** | Phase 0 (months 0-3) | Same prerequisites as grad student. Audit-quality output ships with the validate CLI. |
| **JOSS reviewer / scientific-software referee** | Phase 1 (months 3-9) | Prerequisite is a tagged release + the methods-paper draft. Activates the day the JOSS submission lands. |
| **Open-source maintainer** | Phase 1 (months 3-9) | Needs the contribution surface to be stable + the schema-bump runbook. Both shipped by v1.40. |
| **Instructor / TA** | Phase 2a (months 9-18) | Needs the Pluto walkthroughs + GLOSSARY + at least one published reproducibility paper to cite. Walkthroughs ship in Phase 1; the paper is Phase 1 endgame. |
| **Pharma CADD scientist (POC eval)** | Phase 2c (months 9-18) | Needs on-prem mode (shipped v1.34) + the hallucination benchmark with verified entries (the verification work is the gating piece). Pilot conversations open after the first benchmark publication. |
| **Data engineer / MLOps** | Phase 2c (months 9-18) | Needs the option-3 fine-tune flywheel data layer (shipped v1.45-v1.48) + a non-trivial corpus to train on (Phase 2 is when the transcripts hit critical mass). |

## Per-phase activation playbook

### Phase 0 (months 0-3) — Stabilize

Active profiles: grad student / postdoc, reproducibility researcher.

What to do:
- **Onboard one grad student per month manually.** Walk them through
  the 30-minute path; record the failure modes; update the profile
  doc.
- **Get one reproducibility audit submitted to a peer-reviewed
  venue.** This is the credibility seed for Phase 1.
- **Don't activate any other profiles.** No campaign emails to
  pharma; no Discord blast; no ACS COMP submission.

Why restraint: pre-Phase-1, there's no paper to cite, no benchmark
to point at, and no on-prem story for security review. Activating
pharma now produces dropouts; activating instructors now means
they'll teach material that will be obsolete by Phase 2.

### Phase 1 (months 3-9) — Citation moat

Active profiles: + JOSS reviewer, + open-source maintainer.

What to do:
- **Submit the methods paper.** JOSS or a domain venue
  (J. Chem. Inf. Model., J. Chem. Theory Comput., or similar).
- **Recruit 2-3 OSS contributors actively.** Use the
  [`docs/POWER_USERS.md`](POWER_USERS.md) onboarding doc; pair
  them on a real PR.
- **Stop manually-onboarding grad students one at a time.** Replace
  with a self-serve `USER_PROFILE_GRAD_STUDENT.md` + a Discord/Matrix
  channel (per Phase 0 deliverable).
- **Continue restraint on Tier 2 / Tier 3 personas.** The cold-email
  campaign in `docs/CAMPAIGN_2026Q2.md` is gated on the methods
  paper publishing.

### Phase 2a — Academic emphasis

Active profiles: + instructor / TA.

What to do:
- **Course-adoption push.** The Pluto walkthroughs ship in Phase 1;
  by Phase 2 they're the load-bearing pedagogical artifact. Reach
  out to course coordinators in adjacent fields (biophysics,
  comp-chem, structural bio).
- **Annual training workshops.** ~1-day online or in-person at
  ACS COMP / Telluride / CECAM venues. Each workshop is one
  cohort of `USER_PROFILE_INSTRUCTOR.md` adopters.
- **Track the academic-paper count.** The lagging indicator:
  papers cite Crucible in their Methods section.

### Phase 2b — OSS emphasis

Active profiles: + serious-OSS contributors (already-active
maintainers + power users escalating).

What to do:
- **Drop maintainer-onboarding friction.** Pair every new
  contributor on their first PR; promote anyone with 3+ merged
  PRs to active-reviewer status.
- **Decide on the Phase 2b deliverables** — which of the deferred
  items in [`docs/PLAN.md`](PLAN.md) v1 (SMILES → ligand params,
  PDBFixer auto-build, LocalProvider wired, Genie web frontend)
  ship.

### Phase 2c — Business emphasis

Active profiles: + pharma CADD scientist (POC eval), + data engineer
/ MLOps.

What to do:
- **Q2 campaign motion** ([`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md))
  goes live. Cold emails to Tier 2 personas; conference attendance;
  Practical Cheminformatics guest post.
- **First paid POC.** $5K-$15K fixed fee; 30-day deliverable. The
  `USER_PROFILE_PHARMA_POC.md` doc walks the eval.
- **First fine-tune corpus customer.** The data engineer profile
  exists for the case where a research lab or biotech wants the
  raw `(paper, MDSpec)` pairs to train their own model.

## What not to do, ordered by phase

Each phase has activation anti-patterns that produce dropouts.
Documenting them prevents the next maintainer from re-deriving:

### In Phase 0, do not:
- Submit to JOSS (no published methods paper to cite; reviewers
  bounce).
- Activate the instructor profile (the Pluto walkthroughs aren't
  polished yet; students struggle).
- Cold-email pharma CADD leads (no on-prem story; eval bounces in
  IT review).

### In Phase 1, do not:
- Pitch a 30-day pilot before the methods paper publishes (you
  have no third-party validation; the pilot bounces in management
  review).
- Add user-profile docs for roles you haven't observed (you'll
  encode wrong assumptions; revising later is costlier than not
  shipping).

### In Phase 2c, do not:
- Onboard a pharma POC against an unverified benchmark seed set
  (the eval will surface "Crucible's own benchmark is unverified"
  — credibility-killing).
- Skip the on-prem preflight in the pharma conversation. The
  IP-policy block is the #1 pharma deal-killer per the salt-mines
  panel.

## Cross-references

| Activate at | Doc to walk them through | Doc that gates the activation |
|---|---|---|
| Phase 0 | `USER_PROFILE_GRAD_STUDENT.md` | `README.md` (install must be ≤15 min) |
| Phase 0 | `USER_PROFILE_REPRODUCIBILITY_RESEARCHER.md` | Validate + coverage CLIs |
| Phase 1 | `USER_PROFILE_JOSS_REVIEWER.md` | Methods paper draft |
| Phase 1 | `POWER_USERS.md` | Schema-bump runbook |
| Phase 2a | `USER_PROFILE_INSTRUCTOR.md` | `examples/study_validation_gates.jl` |
| Phase 2c | `USER_PROFILE_PHARMA_POC.md` | `docs/ON_PREM.md` + `docs/HALLUCINATION_BENCHMARK.md` |
| Phase 2c | `USER_PROFILE_DATA_ENGINEER.md` | `python -m crucible benchmark export-jsonl` |

## See also

- [`docs/USER_PROFILES.md`](USER_PROFILES.md) — the index this
  timeline activates.
- [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) — the 18-month
  strategic plan that defines Phase 0 / 1 / 2.
- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  — the 180-day operational layer for Phase 2c.
- [`docs/ADOPTION_STRATEGY_PLAYBOOK.md`](ADOPTION_STRATEGY_PLAYBOOK.md)
  — the *how* (writing the docs) to this doc's *when*
  (activating them).
