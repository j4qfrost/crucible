# Crucible advertising campaign — 2026 Q2

Concrete creative + targeting plan that operationalizes Phase A of
[`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
("get one warm lead this week" + "build the hallucination benchmark"
become the campaign's two anchors).

This document **identifies public-figure targeting personas** and
**ships campaign assets** — copy, channel sequencing, KPIs. It does
**not** publish individual contact information; cold-email lists are
the founder's responsibility to assemble from the public surfaces
identified per persona.

## Positioning

> **One sentence:** Crucible turns a molecular-dynamics paper into a
> validated, runnable simulation script — with the protocol audit
> trail a reviewer would actually accept.
>
> **One paragraph:** Drop a paper, an arXiv ID, or a Methods excerpt
> into Crucible. An LLM extracts the simulation protocol into a
> typed intermediate representation (`MDSpec`); five validation
> gates catch the silent semantic errors that make MD reproductions
> fail (wrong force field, wrong water model, missing barostat,
> non-monotonic FEP λ); a renderer emits an OpenMM or Molly.jl
> script you can run today. Every numeric field carries provenance —
> paper / paper-default / assumed / user — so reviewers see what the
> LLM extracted vs. what it guessed.

The wedge is **provenance + validation gates**, not "LLM that writes
code." Every comp-chem PI and pharma CADD lead has been burned by
LLMs that produce plausible-looking-but-physically-wrong
simulations. Crucible's pitch is that the structured IR collapses
the hallucination surface to a finite enum/numeric space, and the
gates pre-empt the silent failures.

## GitHub-grounded ecosystem snapshot (verified 2026-04-29)

| Repo                          | Stars | Lead / org                | Why it matters for Crucible                                                       |
|-------------------------------|------:|---------------------------|-----------------------------------------------------------------------------------|
| `openmm/openmm`               | 1,900 | OpenMM org (Stanford ↔ MSKCC lineage) | Crucible's primary backend. OpenMM 8.5.1 shipped 2026-04-10.            |
| `JuliaMolSim/Molly.jl`        |   475 | JG Greener (MRC LMB)      | Crucible's native-Julia backend. Differentiable MD = unique research vector.       |
| `openforcefield/openff-toolkit` | 392 | OpenFF Initiative consortium | The ligand-FF supply chain Crucible depends on (Sage 2.2.0, Smirnoff).           |
| `choderalab/openmmtools`      |   319 | Chodera Lab (MSKCC)       | Alchemical-FEP infrastructure under FEPStage. Andrea Rizzi + John Chodera as leads. |

The implication: there are **no projects in this space with > 2k
GitHub stars except OpenMM itself**, and the active maintainer pool
across all four is < 30 people. The "key figures" list below is
short by construction — comp-chem MD is a small, deep field.

## Key figures map (3-tier targeting)

Public-domain, role-and-affiliation-only. The LinkedIn surface for
each is named so the founder can find them; **no contact info
listed**. Each persona has an "angle that resonates" — the
positioning slice most likely to hook them based on their public
work.

### Tier 1 — Academic OSS leadership (10 people)

The labs that ship the upstream tooling Crucible depends on.
Winning their respect makes Crucible's positioning credible
field-wide. Cold reach: 10/10 reachable via lab page + Twitter/X +
GitHub; 8/10 reachable via LinkedIn.

| Persona | Lab / role | Public surface | Angle that resonates |
|---|---|---|---|
| **John Chodera** | MSKCC, alchemical FEP / `openmmtools` | GitHub: `jchodera`; X/Twitter: @jchoderalab; lab page: choderalab.org | "Validation-as-a-first-class-feature" — Chodera lab's whole brand is reproducibility; lead with the 5-gate pipeline + benchmark. |
| **Peter Eastman** | OpenMM lead, Stanford | GitHub: `peastman`; openmm.org | "Crucible as an OpenMM productivity layer" — Crucible is a downstream user, not a competitor. Brief him courteously. |
| **David Mobley** | UC Irvine, OpenFF Initiative | GitHub: `davidlmobley`; X: @davidlmobley | "Open Force Field as Crucible's ligand-parameterization spine" — Crucible already binds Sage 2.2.0 in `force_field.ligand`. |
| **Mike Shirts** | CU Boulder, FEP / MBAR | GitHub: `mrshirts`; lab: shirtsgroup.com | "BAR/MBAR analysis on Crucible-emitted FEP runs" — Crucible's `FEPStage` ladder is the input his analysis tools want. |
| **Joe Greener** | MRC LMB Cambridge, Molly.jl | GitHub: `jgreener64`; X: @jgreener64 | "Crucible as Molly's protocol-onboarding layer" — Molly's hardest barrier is "what protocol do I run?"; Crucible answers it. |
| **Lee-Ping Wang** | UC Davis, ForceBalance / FF dev | GitHub: `leeping` | "Crucible as the FF-cross-validation harness" — drop-in compare AMBER vs CHARMM vs OPLS on the same `MDSpec`. |
| **Rommie Amaro** | UCSD, GPCR + viral MD | Lab: amarolab.ucsd.edu | The `gpcr_oncogene_membrane` template demos the workload her lab publishes. Lead with that template. |
| **Paul Robustelli** | Dartmouth, IDP MD | Lab page; X: @paulrobustelli | "Long-timescale IDP sampling as a Crucible REMD template" — extend the `enzyme_design_remd` template for IDPs. |
| **Charlotte Deane** | Oxford, antibody design (returned from Recursion) | OPIG group page; X: @charlotteMDeane | The `antibody_paratope_fep` template is in her lab's exact lane. Lead with that + ΔΔG benchmark. |
| **Frank Noé** | Microsoft Research / FU Berlin, ML for MD | mscresearch + flyhomenet | "Crucible as data-pipeline for ML-MD training corpora" — the option-3 transcript flywheel feeds the kind of corpus his lab needs. |

### Tier 2 — Pharma / biotech CADD leadership (8 personas)

The actual buyers in the commercial-validation hypothesis. Reach via
LinkedIn (every named role below has a public LI presence) +
conference run-ins (BPS, ACS COMP, GRC CADD).

| Persona / role | Org | Why they matter | Angle |
|---|---|---|---|
| **Robert Abel** (Chief Scientific Innovation Officer) | Schrödinger | Author of FEP+, the gold-standard prior art Crucible reproduces openly. | Don't compete; position as "open IR layer that integrates with FEP+ as a black-box." |
| **Patrick Walters** | Relay Therapeutics → advisory roles widely | Most-public CADD voice in industry; strong open-source advocate. Blog: *Practical Cheminformatics*. | A guest blog post on his site = field-wide credibility. Lead with the benchmark. |
| **CADD group at Genentech** (multiple ICs publish) | Genentech / Roche | Large public preprint output; sets industry norms. | Cite their published protocols in the benchmark; offer reproductions as evidence. |
| **CADD group at Vertex** | Vertex Pharma | Heavy small-molecule MD output; CFTR work. | Reach via the recently-IPO'd CADD-tooling community; conference run-in at ACS COMP. |
| **Tom Miller** | Iambic Therapeutics (formerly Caltech, OpenMM contributor) | Spans academic OSS and pharma; rare bridge persona. | Best single intro target — speaks both languages. Lead with the IR design + Molly differentiable path. |
| **Mathai Mammen** | Relay Therapeutics CEO; formerly J&J R&D head | Decision-authority signal; doesn't need a CADD pitch but values them. | Not a primary target; value as warm-intro source if a Relay IC engages. |
| **Daphne Koller** | Insitro CEO | ML-MD intersection; institutional user of MD tools. | Indirect target via her public ML-MD posts; useful for Tier-3 "narrative" reach. |
| **Brooke Husic** | Princeton (formerly D.E. Shaw, Anthropic) | Bridges ML, MD, and AI; will see this campaign anyway. | Brief courteously; she's a high-signal early-feedback target. |

### Tier 3 — Conference / community surfaces (not individuals)

The discovery channels where Tier 1 + 2 hang out. Not people to
target — *places* to be present.

| Surface | Cadence | What ships there |
|---|---|---|
| **ACS COMP** (American Chemical Society, Computational Division) | Spring + Fall national meeting | Tranche-2 conference. Submit a contributed talk + poster. |
| **Biophysical Society annual** (BPS) | Feb/Mar | Pharma CADD attendance is heaviest here. |
| **Gordon Research Conference — Computer-Aided Drug Design** | June, biennial | Closed-door but highest-density CADD audience. |
| **JuliaCon** | July | Molly.jl + Crucible Julia-side talk. |
| **MolSSI / OpenFF workshops** | Varies | Training-style — best for tier-1 trust building. |
| **r/comp_chem, MatSci.engineering Discord, OpenFF Slack** | Continuous | Tier-3 narrative reach. |
| **Practical Cheminformatics blog** (Pat Walters) | Weekly-ish | Single highest-leverage industry-CADD touchpoint. |

## Messaging stack

Three message tiers. Same product; different audiences need
different leads.

### Lead 1 — Academic OSS (Tier 1)

> *"Crucible is the OSS protocol-extraction layer for OpenMM and
> Molly. Every numeric field carries source attribution; every spec
> passes a 5-gate validator before it runs. We benchmarked on 20
> published MD papers — here are the results."*

**Hooks:** reproducibility, benchmark transparency, IR-as-contract,
schema versioning + migrations, JOSS-paper alignment.

### Lead 2 — Pharma CADD (Tier 2)

> *"Crucible reads a paper, extracts the MD protocol, validates it,
> and emits a runnable script. On-prem mode (local LLM) means your
> unpublished protocols never leave your network. Pilot scope: we
> reproduce 10 of your internal protocols against published
> ground-truth and you compare yields against your manual baseline."*

**Hooks:** time-to-first-simulation, IP isolation (local-LLM),
audit trail (provenance), GROMACS exporter on the roadmap, fixed-fee
30-day POC.

### Lead 3 — Founder/community narrative (Tier 3)

> *"I built an LLM molecular-dynamics paper transpiler in Julia.
> Here's why the IR is the load-bearing piece, why the LLM never
> emits code, and what it took to ship 5 validation gates that
> catch silent semantic errors before GPU time gets allocated."*

**Hooks:** maker narrative, candid technical write-up, the IR-as-
contract decision, the why-not-Mojo / why-not-protobuf musings,
opinions on LLM tool-use design.

## Campaign assets (concrete deliverables, weeks 1–13)

Asset effort sized against the 8 hr/week founder bandwidth in the
commercial-validation plan. Each asset has a single owner (founder
unless flagged), a single channel, and a single KPI.

| # | Asset | Lead | Audience | Channel | Effort | KPI |
|---|---|---|---|---|---|---|
| 1 | **60-second Loom demo** — paper drop → spec → benchmark hit | 1 | All tiers | Embed in cold emails + landing page | 2 hrs | ≥ 25% video-completion rate |
| 2 | **Hallucination benchmark page** at `docs/HALLUCINATION_BENCHMARK.md` + a public viewer | 1 | Tier 1 + 2 | Site (GitHub Pages) | 8 hrs (across weeks 2–3) | first 10 incoming links from .edu / pharma CADD blogs |
| 3 | **Twitter/X thread** announcing benchmark | 3 | Tier 1 + 3 | X | 1 hr | ≥ 3 RTs by Tier 1 personas |
| 4 | **arXiv preprint** — 4-page short-paper version of the benchmark | 1 + 2 | Tier 1 | arXiv (q-bio.BM) | 12 hrs (week 12) | citation-trackable |
| 5 | **Practical Cheminformatics guest post** | 3 | Tier 2 (industry) | Pat Walters' blog | 6 hrs writing + outreach | publication |
| 6 | **Cold-email v1 template** (PI variant + CADD variant) | 2 | Tier 1 + 2 | Direct | 1 hr | ≥ 15% reply rate (panel benchmark) |
| 7 | **`docs/ON_PREM.md` page** (local-LLM mode) | 1 | Tier 2 (pharma) | Site | 4 hrs (gated on Week 3 IP-block signal) | unblocks ≥ 1 pharma demo |
| 8 | **ACS COMP contributed talk submission** | 1 | Tier 1 + 2 | ACS abstracts | 3 hrs | accepted |
| 9 | **Landing-page hero rewrite** focused on benchmark + provenance | 2 | All tiers | crucible.dev | 4 hrs | bounce rate < 50% |
| 10 | **OSS hygiene release** (v1.30) tagged on the benchmark publication | 1 | Tier 1 | GitHub | 2 hrs | clean tag |

(Lead `1` = founder; `2` = founder, low-effort; `3` = ambient/social.)

## Channel strategy

The ordering matters — earlier touchpoints lay credibility for later
ones.

```
Week 1   → cold email round 1 (15) + Loom demo
Week 2-3 → benchmark v1 + pre-publication share with Tier 1 (≤ 5 personal)
Week 4   → public benchmark publication + X thread + r/comp_chem post
Week 5   → cold email round 2 (10) citing benchmark
Week 6-9 → on-prem mode + GROMACS scoping (gated on Week-3 signal)
Week 10  → guest-post pitch to Pat Walters
Week 11  → arXiv preprint submission
Week 12  → ACS COMP abstract submission
Week 13  → status report against gate criteria
```

## Cold-email templates (founder-fillable; do not send as-is)

### Tier 1 academic-PI variant

> Subject: Reproducing your Methods section in MDSpec
>
> Dr. <name>,
>
> I built an OSS tool (Crucible) that extracts MD protocols from
> papers into a typed IR, validates them through 5 gates, and emits
> runnable OpenMM / Molly.jl scripts. I just ran a 20-paper
> benchmark across <subfield>; <paper-of-yours> scored <X>/8 on
> protocol-fidelity axes (provenance attached).
>
> If the failure modes are interesting to your group's
> reproducibility work, I'd value 15 minutes to walk you through
> what the IR captures vs. drops. Zero ask beyond feedback.
>
> Loom (60s): <link>. Repo: github.com/j4qfrost/crucible. Benchmark
> page: <link>.
>
> — <signature>

### Tier 2 pharma-CADD variant

> Subject: 30-day POC: Crucible on your internal protocol backlog
>
> <name>,
>
> Crucible is an OSS LLM-to-MD transpiler with on-prem mode (local
> LLM, your protocols never leave your network) and a 5-gate
> validator that catches the silent semantic errors that break MD
> reproductions.
>
> POC scope: we run Crucible against 10 of your internal protocols,
> compare yields against your manual baseline, and ship a written
> evaluation in 30 days. Fixed fee, no ongoing commitment.
>
> Loom (60s): <link>. Public benchmark: <link>. On-prem doc:
> <link>.
>
> If this is the wrong person at <company>, I'd value an intro to
> the right one.
>
> — <signature>

## Email-sequencing framework

The templates above are *first-touch* copy. A single cold email
rarely converts; a disciplined short sequence does. This framework
defines the follow-up cadence — and, just as importantly, where it
*stops*.

The hard ceiling from "Honest constraints" below is unchanged:
**cold emails cap at 35 across the 13 weeks.** The sequence is a
*per-recipient* policy that fits inside that total — it does not add
volume, it allocates the existing 35 touches across fewer recipients
more deliberately. A "touch" here is one email to one person; the
35-touch budget counts every send, first or follow-up.

### The three-touch sequence (per recipient)

| Touch | Timing | What it is | What changes from the prior touch |
|---|---|---|---|
| **1 — first email** | Day 0 | The Tier-1 or Tier-2 template above, hand-personalized. | — |
| **2 — follow-up** | Day 5–7, only if no reply | A 3-sentence nudge on the *same thread* (reply, don't restart). | Lead with a *new* concrete artifact, not a restatement: a fresh benchmark number, the published benchmark page going live, or the on-prem doc shipping. If nothing new exists yet, delay the follow-up until it does — never send "just bumping this." |
| **3 — re-engage** | After 8–12 weeks, at most once | A short new-thread note tied to a campaign milestone. | Tied to a *milestone event*: the arXiv preprint, the ACS COMP talk acceptance, the Practical Cheminformatics guest post. No milestone → no re-engage. |

Three touches per recipient is the **cap**. After touch 3 with no
reply, the recipient is closed-lost for the quarter — do not email
them a fourth time.

### Cadence rules

- **Reply ends the sequence.** Any human reply — even "not now" —
  moves the recipient out of the cold sequence and into the
  `outreach.csv` warm/lukewarm pipeline. Follow-ups are for
  *silence only*.
- **One thread per touch-1/touch-2 pair.** Touch 2 replies to
  touch 1 so the recipient has context. Touch 3 starts a new thread
  because the milestone is genuinely new news.
- **Follow-up needs new substance.** The Day 5–7 nudge must carry
  an artifact that did not exist at Day 0. This is what keeps a
  follow-up from reading as spam — and it aligns the sequence with
  the campaign's week-by-week asset ships (benchmark in Week 4,
  on-prem doc in Week 6, preprint in Week 11).
- **Respect the channel-strategy windows.** Sequencing operates
  *inside* the round-1 / round-2 outreach windows already in
  "Channel strategy"; it does not open new send windows.

### Touch-budget math (stays within the 35 cap)

The "Honest constraints" cap and the commercial plan's two outreach
rounds (15 + 10 + 10 = 35 first-touches *if every email is a fresh
recipient*) interact with sequencing. The sequence trades breadth
for depth:

| Approach | Recipients | Touches | Within 35? |
|---|---|---|---|
| No sequencing (status quo) | 35 | 35 (all touch-1) | yes |
| Light sequencing | ~25 recipients, ~10 get a touch-2 | 35 | yes |
| Full three-touch on a focused set | ~15 recipients × ~2.3 touches avg | 35 | yes |

Recommended: **light-to-full sequencing on the highest-fit
recipients.** The AI-receptivity sub-ranking below identifies who
those are — spend the follow-up budget on Tier-1/Tier-2 personas
whose public work is the closest match, not on broadening the
first-touch list. A reply rate of ≥15% (the KPI threshold) is more
achievable from 15 well-sequenced recipients than 35 one-shot sends.

### When to stop

- **Stop the sequence for a recipient** after touch 3, or on any
  reply, or if they ask to be removed (remove immediately, no touch 3).
- **Stop the campaign's cold outreach entirely** once the 35-touch
  budget is spent — even mid-sequence. Budget exhaustion outranks
  sequence completion. If the budget runs out before a focused
  recipient gets their touch 3, that is acceptable; the cap is the
  cap.
- **Never** convert the re-engage touch into a recurring newsletter.
  Touch 3 is one-shot. Ongoing contact with people who never
  replied is the spam the "Honest constraints" section forbids.

## AI-receptivity sub-ranking (highest-priority early targets)

A separate cut at the persona list: of the named figures, which are
**most likely to engage warmly with software that's mostly built by
AI** (Crucible's actual provenance). Reasoning is from public posture
— papers, blogs, employer signal, public talks — not from confirmed
personal positions on AI-authored code. Ranking is best-guess.

| Rank | Persona | Why they top this list | Use case |
|---|---|---|---|
| 1 | **Brooke Husic** (Princeton; formerly Anthropic) | Anthropic alumna — AI-built tooling is daily reality, not novelty. Will read the IR-as-contract design and structured-output binding as familiar craft. The rare audience that won't bounce on the AI-provenance angle. | Earliest critical-feedback target. Brief courteously; she will see this work field-wide regardless. |
| 2 | **Frank Noé** (Microsoft AI for Science / FU Berlin) | His group is built around ML-MD; an AI-developed MD pipeline is on-thesis. Boltzmann generators, deep learning for sampling. Microsoft AI-for-Science context = daily AI tooling exposure. | Conceptual alignment is highest; expect substantive ML-MD framing in any reply. |
| 3 | **Patrick Walters** (Relay; *Practical Cheminformatics*) | Most public-voice AI/ML-chemistry advocate in industry. Has written candidly about LLMs in chemistry. Discerning but not allergic. | Highest-leverage industry-CADD megaphone. A guest-post placement on his blog is the single best Tier-2 reach. |
| 4 | **Tom Miller** (Iambic Therapeutics; formerly Caltech / OpenMM contributor) | Iambic is explicitly AI-driven drug discovery; Tom himself crossed from academic OpenMM to AI-bio. Speaks both languages natively. | Best strategic-bridge persona for warm intros into both academic OSS and AI-pharma. |

**Honorable mentions:**

- **Charlotte Deane** (Oxford OPIG, Recursion alumna) — heavy ML
  output in antibody design; the `antibody_paratope_fep` template
  speaks to her direct lane.
- **Joe Greener** (MRC LMB) — differentiable MD is itself an
  ML-adjacent paradigm; modern, GitHub-active, more likely
  personally engaged with AI tooling than the median academic.
- **Daphne Koller** (Insitro) — AI-first biotech founder. Too
  senior/busy to be a direct outreach target; treat as ambient
  narrative reach via Tier-3 surfaces.

### The receptivity-discernment trade-off

High-AI-fluency audiences are also the **most discerning** about
LLM-written code. The same reader who recognizes Crucible's IR
design as familiar craft will also catch any benchmark hand-waving,
fabricated metrics, or claims that aren't backed by the public
artifact. **Sequencing rule: reach out to this group only *after*
the hallucination benchmark publishes (Phase A week 4).** Reaching
out earlier risks burning the highest-leverage early audience on a
weaker artifact than they'd respect.

A corollary: AI-receptivity does *not* mean "low bar." It means
"familiar enough to evaluate fairly." That's the audience Crucible
should want.

## Honest constraints (do not compromise these)

- **No fabricated traction.** Don't claim users, pilots, or
  partnerships that don't exist. The benchmark + the open code are
  the credibility.
- **No paid ads.** Tranche 1 + 2 budget covers compute + one
  conference, not Google or LinkedIn ads. Comp-chem audiences
  ignore those anyway.
- **No spamming.** Outreach is hand-personalized; cold emails cap
  at 35 across the 13 weeks (matches the commercial plan).
- **Local-LLM mode is a pharma-conversation prerequisite, not an
  add-on.** If asked about Anthropic-API-only, the honest answer is
  "Ollama / Qwen2.5-7B path is coming in Phase A weeks 4–6 and
  will close that loop."
- **No claims about regulatory or clinical use.** Crucible is a
  pre-clinical research tool. Don't position it as a regulatory
  asset.

## KPI dashboard (week-13 review)

| Metric | Threshold to advance to Phase B Track 1 (LOI pursuit) |
|---|---|
| Cold emails sent | ≥ 30 |
| Reply rate | ≥ 15% |
| Demo calls held | ≥ 5 |
| Tier-1 RT or mention of benchmark | ≥ 2 |
| GitHub stars during the campaign window | +50 |
| Tier-2 warm leads near close | ≥ 1 |
| Hallucination benchmark public | yes (non-negotiable) |
| Local-LLM mode demo-able (if signal present) | yes |
| Practical Cheminformatics guest-post pipeline | submitted or in-edit |

## See also

- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  — the 180-day operational plan this campaign sits inside.
- [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) — strategic 18-month
  plan; the academic / OSS ↔ commercial fork happens at month 9.
- [`musings/scaling_modes.md`](../musings/scaling_modes.md) —
  analysis of academia / OSS / business modes; informs which Tier
  the campaign weighs heavier.
- `~/Projects/salt-mines/reports/crucible.verdict.md` — panel
  verdict that grounds the entire commercial sprint.
