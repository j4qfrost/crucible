# Adoption plan

Operational 18-month plan for taking Crucible from "personal project
shipping daily" to "real adoption in academia, OSS, and (optionally)
business." Companion to [`musings/scaling_modes.md`](../musings/scaling_modes.md),
which is the *analysis* this plan is the *response* to.

## Constraints

The plan assumes:

- **One full-time maintainer.** Not two. If two materializes the
  plan accelerates ~2x; if zero materializes the plan stops
  cleanly with the current state already useful as a citable
  artifact.
- **No external funding committed.** Plan stays sustainable on a
  side-project rhythm; doesn't promise milestones that require
  hiring or services.
- **No business decision made yet.** Phases 0 and 1 keep all three
  scaling modes (academia, OSS, business) viable. Phase 2+ branches
  by mode after a deliberate go/no-go.

## Plan at a glance

| Phase | Window | Goal | Bottom-line investment |
|---|---|---|---|
| **0. Stabilize** | 0–3 months | First usable release; CI bulletproof; bus-factor mitigation | ~6 weeks of part-time work |
| **1. Citation moat** | 3–9 months | Methods paper published; one published downstream user | ~12 weeks of part-time work |
| **2a. Academic emphasis** | 9–18 months | 10 active groups; 5 papers in flight | sustained part-time |
| **2b. OSS emphasis** | 9–18 months | 1k stars; 5 active contributors; v2 runtime path real | sustained part-time |
| **2c. Business emphasis** | 9–18 months | Open-core managed pilot with 1–2 design partners | needs co-founder + funding decision |

Phases 0 and 1 are sequential and unconditional. Phase 2 branches
based on what's working at the 9-month mark.

---

## Phase 0 — Stabilize (0–3 months)

**Why first.** Adoption requires confidence that the project won't
break under your feet. Three things move the needle: a tagged
release, a published methods paper draft, and CI that catches
regressions before users do.

### Deliverables

| # | Deliverable | Owner | Dependency | Effort |
|---|---|---|---|---|
| 0.1 | Tag `v1.0.0` with a short release-notes summary linking the use-case docs | maintainer | nothing | 1 day |
| 0.2 | Publish to JuliaRegistry | maintainer | 0.1 | 2 days |
| 0.3 | Ensure both CI pipelines (GH Actions + Woodpecker) are green at the tagged commit; no skipped tests | maintainer | nothing | already done |
| 0.4 | First-touch onboarding QA: have one person who's never seen the project run `examples/starter_session.sh` and report what broke | external collaborator | finding the person | 1 week wall-clock |
| 0.5 | Update `README.md` so the first 30 seconds of reading commits to one of three messages: "this is what it does, here's the elevator-pitch use case, here's how to start" | maintainer | nothing | 2 days |
| 0.6 | Set up a project Discord/Matrix/Slack channel for early adopters | maintainer | external account | 2 days |
| 0.7 | Bus-factor mitigation: write `docs/MAINTAINER_RUNBOOK.md` covering "what does shipping a release look like, what does triaging an issue look like, what's the schema-bump checklist" | maintainer | nothing | 3 days |

### Decision gate at end of Phase 0

If the QA pass (0.4) reveals show-stoppers (install fails, tests
flaky, docs unfindable), Phase 1 doesn't start until those are
fixed. Common case: 1–2 weeks of follow-up work before declaring
"v1.0.0 is real."

### Risks

- **Procrastinated tagging.** It's easy to keep adding features and
  never declare a release. The discipline: tag `v1.0.0` even if it
  feels premature. Future versions can iterate. The tagged release
  is what other people can build against.
- **JOSS / journal review takes longer than the maintainer's
  attention span.** Mitigation: write the paper draft *during*
  Phase 0, even though submission is in Phase 1.

---

## Phase 1 — Citation moat (3–9 months)

**Why second.** Without a published reference, academic adoption is
near-zero. Without a documented case study, business inquiries are
unanchored. One paper unlocks both. The OSS community gains a
canonical "if you cite the project, cite this" target.

### Deliverables

| # | Deliverable | Owner | Dependency | Effort |
|---|---|---|---|---|
| 1.1 | Methods paper draft for [JOSS](https://joss.theoj.org/) | maintainer | Phase 0 done | 4 weeks writing |
| 1.2 | Submit to JOSS, address reviewer feedback | maintainer | 1.1 | 4–12 weeks wall-clock for review |
| 1.3 | One end-to-end case study using a published kinase / antibody / electrolyte system, documented with full provenance + transcripts | maintainer + 1 collaborator | template applies cleanly | 4–6 weeks |
| 1.4 | "Why MDSpec" preprint or blog post — distilling the IR-as-contract argument from the musings into a 5-minute read targeted at MD practitioners | maintainer | 1.1 | 2 weeks |
| 1.5 | Conference / workshop presence: [Computational Chemistry Gordon](https://www.grc.org/computational-chemistry-conference/), or BOSC, or RSC Workshop on Molecular Simulation. Present a poster or 10-minute lightning talk | maintainer | 1.3 | 1 week prep + 1 conference attendance |
| 1.6 | Set up a citable Zenodo DOI for major releases | maintainer | 0.1 | 2 days |
| 1.7 | Cleanup: delete the v2-deferred IR scaffolding (constph, Martini renderer stubs) IF the case study didn't exercise it; OR commit to building those runtimes IF it did | maintainer | 1.3 | depends on outcome |

### Decision gate at end of Phase 1 (the 9-month branch point)

Three signals to read:

1. **Citation count after 3 months post-publication.** ≥5 citations
   = healthy academic interest; <2 = the paper isn't landing,
   regroup.
2. **Inbound from companies.** ≥3 inbound inquiries from
   biotech/pharma = business mode is real; 0 = stay academic/OSS.
3. **Returning contributors.** ≥3 GitHub contributors with merged
   PRs that aren't the maintainer = OSS mode has lift; 0 = this is
   a single-author tool.

The branching:

- **Academic-only**: 5+ citations, no contributors, no business
  inquiries. Continue Phase 2a.
- **OSS-vibrant**: 3+ contributors, citations growing. Continue
  Phase 2b.
- **Business-real**: inbound from a pharma + an MD-savvy
  technical leader interested in adopting. Co-founder /
  funding-decision territory; the maintainer alone can't pursue
  this. Phase 2c needs a partner.

A reading of "all three are weak" means the project remains
useful but doesn't demand more sustained investment than what
already exists.

### Risks

- **JOSS rejection** for not-novel-enough or scope. Mitigation:
  the IR-as-contract argument is the novel piece. The paper should
  emphasize it (and the validation gate pipeline + provenance
  system), not the templates. Reviewers will compare to BioSimSpace
  + OpenFF Evaluator; differentiate explicitly.
- **No collaborator for the case study.** Mitigation: cancer is
  the easiest target — public PDB IDs, public ligands, CCSD(T)
  reference data exists. The maintainer can do it solo if needed.
- **The conference cycle takes 6 months from submission to
  attendance.** Mitigation: submit to multiple venues; have a
  poster ready that doesn't depend on the paper being accepted
  yet.

---

## Phase 2a — Academic emphasis (9–18 months)

Branch taken if: 5+ citations / no business inquiries / weak OSS
contributor pipeline.

### Goal

10 active research groups using Crucible by 18 months. ~5 papers
citing it. One of those papers is from a Tier-1 (Schrödinger-tier)
target.

### Deliverables

- **2 more methods papers** with collaborators (one cancer, one
  protein engineering, ideally involving one of the original 1.3
  use-case systems re-applied to a new target)
- **Workshop talks at 2 venues**: BOSC + a domain-specific (e.g.
  ACS Comp Chem Section)
- **A "Crucible cookbook"** — 6–10 worked examples answering
  domain-specific questions (different from the templates, which
  are starting points; cookbook entries are end-to-end studies)
- **An academic newsletter or quarterly status update** — informal
  email or blog cadence keeping users in the loop on schema bumps,
  new features, etc. Important because users in academia don't
  watch GitHub releases
- **Consider grant funding**: NSF CSSI, DOE ASCR, or
  Chan-Zuckerberg-Initiative funding for sustainable maintenance.
  ~20 hours grant-writing per application; ~$100K–500K outcomes.

### What success looks like at 18 months

- 10+ active groups confirmed via mailing list / discord
- 5+ papers in submission or published
- A grant either submitted or funded
- The maintainer has had a "your project saved my thesis" email at
  least once

---

## Phase 2b — OSS emphasis (9–18 months)

Branch taken if: 3+ contributors with merged PRs / citations
growing / business inquiries weak.

### Goal

1k GitHub stars; 5 active contributors. The v2-deferred IR
scaffolding (constph runtime, Martini runtime) becomes real because
contributors are willing to build it.

### Deliverables

- **Triage discipline**: weekly issue/PR review, labeled and
  responded-to within 7 days. Burnout-prone; consider bringing on a
  co-maintainer.
- **Hacktoberfest-style annual contribution sprint**: identify 10
  good-first-issues, advertise it 6 weeks ahead, host a virtual
  kickoff. Realistic outcome: 3-5 net-new contributors per year.
- **A "Crucible Foundation"** governance step — formal decision
  process for breaking changes, schema bumps, new IR axes. Even if
  it's just a short markdown doc, it lowers anxiety for
  contributors who otherwise worry the maintainer will rewrite the
  thing.
- **Real v2 runtimes**: if a contributor proposes building the
  constph or Martini runtime, accept the PR with whatever
  scaffolding effort they bring. This means contributing to the
  matching upstream (openmm-constph maintainers, vermouth
  maintainers); plan for cross-project liaison effort.
- **Python bindings (or equivalent FFI)** for the IR + render
  layer. Major adoption blocker is the Julia requirement; Python
  bindings let Python-only labs use Crucible without learning
  Julia. ~6–10 weeks of work.

### What success looks like at 18 months

- 1k stars, 5 active contributors with sustained PR cadence
- 1 v2 runtime (constph or Martini) shipped by a contributor
- A governance document that contributors reference when proposing
  changes
- Python bindings released, ~30% of CLI users using them rather
  than Julia directly

---

## Phase 2c — Business emphasis (9–18 months)

Branch taken if: 3+ inbound inquiries from biotech / pharma / the
maintainer has a co-founder candidate.

### Goal

1–2 design partners using a hosted-runtime version. Soft revenue
target: $200K MRR by month 18 (= 2 design partners at $100K ARR
each, paying for managed compute + audit dashboards).

### Deliverables

- **Co-founder hired or partnered with**. Domain expertise (ex-
  Schrödinger, ex-pharma comp-chem) is the value. The maintainer
  alone can't do business development at the same time as
  technical leadership; the gap is fatal.
- **Open-core line drawn explicitly**. What stays free, what's
  paid. Default plan:
  - Free: CLI, IR, validation, render, lint, coverage, the
    transcript store (local), all use-case templates.
  - Paid: hosted runtime (managed GPU pool with billing per-run),
    team transcripts (multi-user), audit dashboard with
    submission-grade exports, FDA-21-CFR-Part-11-compatible
    workflow templates.
- **Two design-partner contracts** — one biotech (smaller, faster
  feedback), one mid-cap pharma (slower, validates regulatory
  story). LOI before paid contract.
- **Hosted-runtime infrastructure**: cloud-pool deployment, billing
  integration, customer onboarding flow. ~3 months of focused
  work, possibly with a contractor.
- **Funding decision**: bootstrap (slower, retain control) vs.
  seed round ($1–3M, faster, dilution). Driven by the co-founder
  + design-partner conversations.

### What success looks like at 18 months

- Two paying design partners with active contracts
- $200K MRR or higher
- Funding either secured or deliberately postponed
- The OSS layer remains active (open-core only works if the OSS
  layer is healthy on its own merit)

---

## What if all three branches are weak

Honest mode. If at the 9-month gate:
- citations are sparse,
- inbound business is nil,
- contributors are absent,

then the project hasn't found a market sufficient to justify
sustained investment. The right move is **graceful step-down**:

- Tag a final stable release (e.g. `v2.0.0-final`).
- Update the README to reflect maintenance mode ("This project is
  feature-complete; bug fixes only; no new features").
- Keep the architectural docs intact — future contributors can
  still benefit, even if the maintainer steps back.
- The project is *useful* even if it isn't *adopted*: a documented
  reference for IR-as-contract design in research software.

This is a real outcome and not a failure. Most research software
ends here, including projects with much higher initial investment.

## Cross-phase activities (always-on)

Regardless of mode:

- **Quarterly review** of `musings/scaling_modes.md` — has the
  market shifted? Update or re-derive.
- **Schema migration discipline.** Every release passes
  `tools/migration_smoke.jl`. No exceptions.
- **Documentation drift.** `tools/regenerate_docs.jl` runs in CI.
  Use-case docs reflect template count + name.
- **Security policy.** `SECURITY.md` is up-to-date for any path
  involving real LLM API keys or production credentials.
- **The transcript flywheel keeps logging.** Every real user
  session adds to the corpus. The fine-tune option-3 path is
  always-on background.

## How to read this plan

This plan is a hypothesis. The deliverables are unfalsifiable
checkpoints; the decision gates are explicit branches. If something
isn't working, prefer adjusting the plan over forcing the
deliverable. The musing is the analysis; the plan is the response;
the world is the test.

If three months from now this plan looks naive, the right move is
to update it and add a "what we got wrong" section. The plan
isn't sacred. The discipline is.

## See also

- [`musings/scaling_modes.md`](../musings/scaling_modes.md) — the
  underlying analysis.
- [`docs/PLAN.md`](PLAN.md) — the *technical* roadmap (features,
  architecture). This adoption plan is the *go-to-market* roadmap.
  Both must align; if they conflict, raise it.
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — what an external
  contributor needs to know. Phase 2b assumes this is current.
- [`CHANGELOG.md`](../CHANGELOG.md) — version cadence. Phase 0's
  "tag v1.0.0" requires a clean changelog.
