# Scaling modes (academia / business / open source)

How does Crucible scale as a product? Three distinct modes with
different bottlenecks, different timelines, and different failure
patterns. This musing is the durable architectural-decision record
behind each — what works in Crucible's favor in each mode, what
doesn't, and how the modes interact.

The companion to this is [`docs/ADOPTION_PLAN.md`](../docs/ADOPTION_PLAN.md),
which is the *operational* version (phases, milestones, decision
gates). This musing is the analysis that informs the plan — re-read
when you're tempted to do something the plan doesn't cover, or when
the plan is failing and you want to know if it's the right strategy
or the right execution that's broken.

## Academia

### How it scales

The canonical academic vector: a PhD student picks up the project
because it solves a real grad-school pain (going from "my advisor
said run MD" to a defensible ΔG number takes months without it).
The student uses it for their thesis, cites the paper, and brings it
to their postdoc lab. Same path Gromacs, NAMD, OpenMM, BioSimSpace
all took.

### What works in Crucible's favor

- **IR-as-contract is exactly the right shape for academic
  reproducibility.** A spec is deterministic, auditable, fixture-able.
  Two labs comparing results can diff specs cleanly — far better than
  diffing two ad-hoc Python scripts. Reproducibility crisis pressure
  is real and growing in computational chemistry; this is genuinely
  differentiated.
- **The use-case docs (cancer / materials / protein engineering)
  lower the cold-start cost** for a thesis project. A grad student
  can identify "this template matches my thesis question" in
  30 minutes; learning OpenMM's API to do the same takes weeks.
- **Provenance + lint catches the "I forgot what temperature I used
  in figure 3" problem** that haunts published MD work. PIs notice
  this.

### What doesn't scale well

- **Julia + Python bilingual.** ~95% of computational chemistry
  groups are Python-only. The optional Julia layer is real friction
  for adoption. Mitigation today: "you only need to install Python;
  Julia runs in a docker container." Still a sales pitch.
- **Bus factor.** Single-maintainer projects in academia regularly
  orphan when the maintainer graduates. The architectural-decision
  records mitigate this (another senior engineer could pick up
  cold), but won't substitute for ongoing care.
- **Citation moat is weak today.** Schrödinger Maestro / OpenMM /
  Gromacs have thousands of citations. Crucible has zero. A first
  methods paper is a precondition for academic adoption — without
  it, PIs default to known stacks.

### Realistic 5-year ceiling

50–200 active groups, ~5–20 published papers using it as primary
tool, mostly drug-discovery + protein-engineering. Materials
adoption is harder because the metals/EAM gap is real and the
alternatives (LAMMPS, NAMD) are entrenched.

## Private business

### Multiple plausible revenue models

| Model | Mechanism | Comparable | Realistic ARR ceiling |
|---|---|---|---|
| **Open core + hosted runtime** | Free CLI; paid managed GPU pool, billing per-run, central LLM-API costs, team transcripts + audit | Anyscale (Ray), Modal Labs | $10–50M |
| **Pharma enterprise license** | On-prem, audited, FDA-submission-grade. $500K–$5M/year per pharma, consulting bundled | Schrödinger ($200M+ ARR) | Order of magnitude smaller; $20–100M is plausible after years of penetration |
| **Vertical SaaS** | "Antibody affinity maturation as a service"; one template wrapped in a turnkey UI for non-MD users | Genesis Therapeutics (kinase-focused) | $5–20M per vertical |
| **Consulting/services** | Help pharma adopt + extend the IR for their targets | Boutique computational-chemistry shops | $1–3M |

### What works in Crucible's favor

- **Provenance + audit-trail is FDA-relevant.** Computational
  predictions in regulatory submissions need traceability;
  Crucible's `cite` + `coverage` + `lint` triple is unusually
  well-suited. This is rare in MD tooling.
- **Five-gate validation pipeline maps to GLP compliance vocabulary.**
  "We refuse to run if validation fails" is a sentence pharma QA
  understands.
- **LLM extraction layer leapfrogs a typical pharma adoption
  blocker.** Most pharma scientists won't write OpenMM scripts; if
  they can paste a paper and get a runnable spec, that opens a
  much larger user base.

### What doesn't scale well

- **Schrödinger moat is brutal.** 30-year head start, validated
  workflows, ~80% of large pharma uses Maestro for ligand design.
  Displacing them requires either a 10× capability advantage
  (none in sight) or a different price point (open core can
  deliver).
- **Pharma compute is mostly on-prem.** Limits SaaS appeal. The
  hosted-runtime model loses to "we already have 10,000 GPU
  hours/year on our cluster."
- **Sales-and-domain investment is substantial.** A serious pharma
  play needs ex-Schrödinger sales people, FDA-veteran regulatory
  consultants, and a head of strategic accounts. None of that is
  built.
- **Drug-discovery is consolidating.** Big pharma absorbs biotech;
  smaller customers vanish. Strategic accounts are 5–10 customers
  globally.

### Realistic 5-year ceiling

$20–50M ARR via open-core + hosted runtime + 1–2 pharma enterprise
deployments. Order of magnitude smaller than Schrödinger; but a
real business.

## Open source

### How it scales

GitHub stars → contributor inflow → templates for new domains →
published papers → more stars. The flywheel works if and only if:
(a) the maintainer keeps reviewing PRs, (b) the architecture stays
stable enough that contributors can extend without rewriting, (c)
the schema versioning discipline holds.

### What works in Crucible's favor

- **The architectural-decision records (this whole `musings/`
  directory) are unusually thorough.** Most OSS projects' "why we
  did it this way" is buried in PR threads from three years ago.
  Crucible has it as load-bearing documentation. Lowers contributor
  onboarding cost dramatically.
- **Schema migration framework + `tools/migration_smoke.jl` CI
  step** mean schema bumps don't break downstream tooling. Rare;
  most research-software either freezes the schema (rigidity) or
  breaks it casually (instability).
- **The IR is the contract.** Contributors can add stage types,
  source types, observables, force fields without touching the
  renderer. Extension surface is uncommonly clean.
- **Multi-vendor LLM abstraction.** No vendor lock-in. If
  Anthropic raises prices 10×, swap in Ollama. Unusual hedge.

### What doesn't scale well

- **Julia community size.** ~100k Julia users globally; Python
  has millions. Recruiting Julia contributors is genuinely harder.
  Mitigation: the renderer's output is Python (anyone can read
  `run_openmm.py`); the LLM transpile path is provider-agnostic and
  could in principle have Python bindings.
- **MD scope creep.** Every user wants their specific use case as
  a template. A bare-bones OSS project handles this well; a
  maintainer with a day job hits PR-fatigue at ~6 active
  contributors.
- **The v2 IR scaffolding is a commitment.** Constant-pH and
  Martini IR shapes are baked in but the runtimes don't exist. A
  user who needs them is currently blocked. Either the maintainer
  keeps shipping renderer paths or those scaffoldings become
  embarrassing dead code.
- **Funding model unclear.** Pure-OSS requires either grant
  funding (academic), corporate backing (one large user pays for a
  maintainer), or sustainable side-project rhythm. None committed
  today.

### Realistic 5-year ceiling

1–3K GitHub stars, ~20 active contributors, ~50 published methods
papers using it. Stable but small relative to numpy/scipy. The
project occupies a niche (LLM-driven structured-output MD) without
an obvious competitor — both a moat and a market-size constraint.

## Cross-mode dynamics

The interesting interactions:

- **Academia → OSS feeder** (healthy). Grad students contribute
  templates, build use-case docs in their domain, become postdocs,
  evangelize. The 3 application-area docs (cancer / materials /
  protein engineering) are exactly the kind of thing that grows
  organically as users from each domain land.
- **Academia → business hiring filter** (medium-term). This is how
  Schrödinger seeded pharma. Grad students who used Maestro brought
  it to industry. Crucible could replicate this if academic
  adoption hits ~50 groups; below that the pipeline is thin.
- **OSS → business funnel (open-core)**. Pharma evaluates the
  OSS, then pays for audit/managed/regulatory features when ready
  for submission. Cleanest revenue path. Requires a clear "what's
  free, what's paid" line; the project doesn't have one drawn yet.
- **Business → OSS contributions** (lossy). When pharma uses the
  OSS, internal extensions are *sometimes* upstreamed. Open-core
  companies that are good at this build genuine moats. Pharma is
  historically less good at upstreaming than infrastructure
  companies — IP-protection instincts cut against contribution.
  Plan for ~20% upstreaming rate, not 80%.

## The actual bottleneck

The growth rate is **bottlenecked by the maintainer, not the
architecture or the market**. The architecture is unusually
well-prepared for scaling (musings, schema versioning, multi-vendor
abstraction, contributor-friendly extension points). The market
exists in all three modes. The missing piece is sustained activity:
a published methods paper, a real user-conference presence, a
documented case study where someone actually shipped a regulatory
submission using it.

Each of those takes 6–12 months of sustained work and represents a
commitment the project hasn't yet made. The adoption plan
(`docs/ADOPTION_PLAN.md`) is the operational version of "what
sustained work, in what order."

## When to revisit this musing

- **Quarterly.** The market shifts: Schrödinger acquires a
  competitor; pharma compute moves more on-prem (or off); a new
  Julia-LLM library lands; ML potentials beat AMBER on binding
  ΔG. Any of those shifts changes the analysis above. Update or
  re-derive.
- **When changing strategic direction.** If considering a fork,
  a major rewrite, or shifting the funding model, this is the
  doc that should inform whether the new direction makes sense in
  the existing scaling-mode landscape.
- **When the adoption plan is failing.** The plan is the
  hypothesis; this musing is the underlying analysis. If the plan
  isn't working, audit whether the analysis was wrong (the world
  changed) or whether execution was wrong (the world hasn't).
