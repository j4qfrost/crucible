# User profiles — adoption-strategy index

Each profile below has a dedicated doc that takes a specific kind of
person from "I just heard about Crucible" to "I have produced
something useful with it." Designed for the adoption-strategy mode
in [`musings/scaling_modes.md`](../musings/scaling_modes.md): the
academic / OSS / pharma split scales by *whose problem we
solved this week*, not by *whose mailing list we joined*.

Companion to:

- [`docs/HOW_TO_READ.md`](HOW_TO_READ.md) — *reading*-oriented
  guides for newcomers who want to navigate the codebase.
- [`docs/POWER_USERS.md`](POWER_USERS.md) — *contributor* onboarding
  for someone extending Crucible.
- This doc — *task*-oriented onboarding for someone consuming
  Crucible for a specific outcome.

The three docs are non-overlapping by design.

## Profiles

| Profile | Primary outcome | First commit / artifact | Time-to-value |
|---|---|---|---|
| **[Grad student / postdoc](USER_PROFILE_GRAD_STUDENT.md)** | First runnable MD script from a paper | A reproduced Methods section + a passing health gate | ≤ 1 hour |
| **[Pharma CADD scientist (POC eval)](USER_PROFILE_PHARMA_POC.md)** | 30-day evaluation deck for management | A scored benchmark across your internal protocols + on-prem deployment doc | 30 days |
| **[Instructor / TA](USER_PROFILE_INSTRUCTOR.md)** | A reproducible course module | A Pluto walkthrough notebook tailored to your syllabus | 1-2 weeks |
| **[Reproducibility-minded researcher](USER_PROFILE_REPRODUCIBILITY_RESEARCHER.md)** | Audit-quality verification of a published MD result | Provenance-coverage report + a structural diff against the paper's protocol | ≤ 1 day |
| **[Data engineer / MLOps](USER_PROFILE_DATA_ENGINEER.md)** | JSONL data layer of `(paper, MDSpec, score)` tuples for the option-3 fine-tune flywheel | Exported corpus + benchmark runs in your warehouse | 1 week |
| **[JOSS reviewer / scientific-software referee](USER_PROFILE_JOSS_REVIEWER.md)** | A complete JOSS-style review covering the 6 criteria | A filled-in review checklist with citations into the codebase | 3-5 hours |
| **[Open-source maintainer](POWER_USERS.md)** | A landed PR or extension | A merged contribution | varies |

## Picking a profile

The chooser:

- *"I have a paper and want to reproduce its MD."* → **Grad student / postdoc**.
  Even if you're a PI; the workflow is the same.
- *"My team needs to evaluate Crucible vs. our internal scripts."* →
  **Pharma CADD scientist (POC eval)**.
- *"I'm teaching a comp-chem course this semester."* → **Instructor / TA**.
- *"I'm reviewing a published MD claim."* → **Reproducibility-minded researcher**.
- *"I'm building the data layer for a chemistry-MD fine-tune."* →
  **Data engineer / MLOps**.
- *"I'm reviewing this software for JOSS / a national lab eval."* →
  **JOSS reviewer / scientific-software referee**.
- *"I want to ship code into Crucible itself."* → **Open-source maintainer**.

If two apply, start with the more concrete one — the abstract one
will compose on top.

## What goes in a profile doc

Each `USER_PROFILE_*.md` follows the same shape so they're
cross-referenceable:

1. **One-paragraph hook** — what this person leaves with.
2. **Pre-flight** — exactly what they need installed/credentialed.
3. **The 30-minute path** — fastest way to a real artifact.
4. **The first-week path** — what comes after the smoke run.
5. **Failure modes specific to this profile** — what tripped previous
   adopters in the same role.
6. **When to read X next** — pointers into the rest of the docs.

The `30-minute path` is the load-bearing section. If a profile's
first artifact takes more than 30 minutes for the median user, the
profile doc has failed.

## Adding a profile

If you encounter a real adopter whose path doesn't match any of the
above:

1. Open an issue tagged `user-profile` describing the role + the
   first artifact they wanted.
2. Sketch a draft `USER_PROFILE_<role>.md` following the shape above.
3. PR the new doc + a row in the table at the top of this file.
4. Cross-reference from any campaign tier in
   [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) the role overlaps
   with.

Don't add a profile until you've spoken to a real person in that
role and watched them stumble — speculative profiles are worse than
no profiles (they ossify wrong assumptions).
