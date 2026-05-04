# Punch list — user-gated follow-ups

Items that came out of the v1.36 → v1.38 stretch (2026-05-04) that
require human action to close. Filed here so a future session
(or a future you) can pick them up without re-deriving context.

Organized by what kind of action gates each item.

## Browser / external-service gated

### PSS #184 — convert PR to draft + post diagnostic comment

- **Repo:** `pluto-svelte-svelte` upstream (PSS = Pluto Svelte
  Svelte). Auth blocker: `gh` CLI returns 401 and there is no
  `GITHUB_TOKEN` in env, so the PR can't be transitioned
  programmatically. SSH push works.
- **Action:** open PR #184 in a browser, click *Convert to draft*,
  then paste the diagnostic comment that was drafted earlier in
  this session (CI regression + auth blocker explanation).
- **Why it's worth doing:** keeps the PR honest while the
  upstream review is paused; signals to the maintainer that we're
  aware of the regression rather than ghosting.

### Submit 3 drafted upstream PRs

- **`PSS feature/throw-on-cell-error`** — branch already pushed,
  needs PR opened as **Draft** in the GitHub compare UI.
- **`easy_localization feature/export-public-ext-from-generated`**
  — branch pushed, needs draft PR.
- **`easy_localization feature/dartdoc-on-locale-keys`** — branch
  pushed, needs draft PR.
- **Where the compare URLs live:**
  `~/Projects/upstream/CONTRIBUTIONS_LOG.md` has the per-branch
  compare URLs ready to click.
- **Why drafts:** all three are conversation-starters more than
  finished work; opening as Draft signals "feedback wanted before
  I polish" without burning maintainer goodwill.

## Paywall / human-judgment gated

### Verify the 5 benchmark seed entries against their SI

**Step-by-step procedure:** [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md)
(15-45 min per paper once you have the source — the bottleneck is
reading Methods, not editing the file).

After v1.37 / v1.38, all five DOIs are Crossref-verified at the
metadata level (title + authors + journal). The
`ExpectedProtocol` field-level values are still
`needs_verification` because the SI for each paper is paywalled
and a human has to read it.

The five entries, in order of likely-easiest-to-verify:

1. **Sugita & Okamoto 1999** — `10.1016/S0009-2614(99)01123-9`.
   Pre-paywall era; commonly accessible. Pick *one* of the two
   worked examples (alanine dipeptide *or* Met-enkephalin) and
   lock its protocol values.
2. **Mobley et al. 2007** — `10.1016/j.jmb.2007.06.002`. Multi-system
   paper; pick one of the simple-model-site systems and lock its
   λ-window count.
3. **Salomon-Ferrer et al. 2013** — `10.1021/ct400314y`. Tooling
   paper; pick one worked example (e.g. dihydrofolate reductase).
4. **Wang et al. 2015** — `10.1021/ja512751q`. FEP+ landmark; OPLS3
   force field is outside Crucible's allowlist, so document the
   coverage gap as part of the verification note.
5. **Shaw et al. 2010** — `10.1126/science.1187409`. Anton BPTI
   1ms. `duration_ns=1_000_000` already verified from abstract;
   the rest needs the Science SI (paywalled). Likely hardest
   without institutional access.

**Where the field-by-field acceptance criteria live:**
`python/crucible/benchmark/papers.py` — read the `notes` field on
each entry; it lists which axes are evidence-backed vs.
cargo-culted from secondary literature.

**How to mark verified:**
1. Edit the entry: set `status="verified"` and add
   `verified_by="<initials> <YYYY-MM-DD>"`.
2. Replace any cargo-culted values with the actual paper values
   (or `None` if the paper genuinely doesn't specify the knob).
3. Update `notes` to reflect what changed.
4. Run `cd python && pytest tests/test_benchmark.py
   tests/test_corpus_benchmark_bridge.py` (still 23/23 expected).
5. Optionally run `crucible benchmark report` to produce a real
   first published number.

## Recording / outreach gated

### Record the Loom demo

- **Pre-work eliminated.** The `examples/loom_demo/` directory
  ships a zero-friction record kit: `methods.txt` (synthetic full
  detail), `methods_underspecified.txt` (real-paper Shaw 2010
  abstract-only, paywall-safe), `record_session.sh` (executable
  three-scene driver), and `README.md` (recording checklist).
- **Two recording angles available:** happy-path full-detail
  (`methods.txt`) or under-specification handling
  (`methods_underspecified.txt`). Pick based on audience —
  `docs/LOOM_DEMO_SCRIPT.md` has the per-tier narration.
- **What's left:** open a clean terminal, run
  `crucible doctor && crucible templates list` to warm the JIT,
  then `bash examples/loom_demo/record_session.sh`. Single take.

### Send the cold-email batch

- **Templates ready:** `docs/CAMPAIGN_2026Q2.md` Tier-1 / Tier-2 /
  Tier-3 templates updated post-v1.35 with the GROMACS-scoped
  language ("primary deliverable is OpenMM. GROMACS export is
  scoped …").
- **Targeting:** the salt-mines panel verdict identified credibility
  as the wedge; lead with the hallucination benchmark + on-prem
  guarantees, not the renderer.
- **Cadence:** the campaign doc has the per-Tier weekly send
  cadence; respect it.

## How to use this file

When you're between tasks and looking for unblocking work, scan
the gating categories: pick whichever matches the kind of
attention you have right now (browser tab, paper PDF, terminal,
inbox). Each entry stands alone — no need to read the others to
act on one.

When an item is closed, **delete its entry**; this is a punch
list, not history. The CHANGELOG has the history.
