# Loom demo script — 60-second walkthrough

Campaign asset #1 from [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md).
Embedded in cold emails (Tier 1 + Tier 2 templates) and on the landing
page. The Loom is the single highest-leverage piece of marketing
content — it has to land the wedge in 60 seconds.

> **Wedge to land:** "Crucible turns a paper into a validated,
> runnable simulation script — with a 5-gate validator that catches
> the silent semantic errors LLMs make on MD." Provenance, validation,
> on-prem-mode roadmap. Not "look at AI, it writes code."

## Recording target

- **Length:** 55-65 seconds. Hard cap 75. If you can't say it in
  60, the wedge isn't sharp enough yet.
- **Resolution:** 1080p (Loom default). Show the terminal at a
  font size readable on a phone (≥ 16pt).
- **Audio:** USB mic, room treated. Loom's auto-cleanup is fine.
- **Cuts:** none. Single take. If a take feels rough, redo it; Loom
  encourages many cheap takes.

## Scene-by-scene script

Format: `[seconds] {visual}` `[narration in voice]`. Total target 60s.

### [0:00 – 0:08] Hook

`{Show a published MD paper PDF in the browser. Highlight the Methods
section with the cursor.}`

> "Every MD reproduction starts here — a Methods section that's three
> paragraphs of force fields, water models, timesteps, ensembles."

### [0:08 – 0:18] The problem

`{Switch to a code editor or terminal. Show a hypothetical Python
OpenMM script with red squiggles or comments calling out
"wrong force field?", "TIP3P or TIP4P?", "missing barostat".}`

> "The paper says ff14SB. Your script uses ff19SB. The temperature
> drift is identical. The energies look fine. The result is
> physically wrong, and you don't know yet."

### [0:18 – 0:32] The product

`{Switch to terminal. Run:}`

```
$ crucible transpile --paper methods.txt
```

`{Show the rendered MDSpec JSON (selectively — first ~12 lines).
Cursor highlights the `provenance` field next to one numeric.}`

> "Crucible reads the paper. The LLM emits a typed intermediate
> representation — every numeric field is tagged with its source.
> Paper. Paper-default. Assumed. User."

### [0:32 – 0:42] The differentiator (validation gates)

`{Run:}`

```
$ crucible health spec.json
✓ Gate 1: schema
✓ Gate 2: semantic (NPT requires barostat — present)
✓ Gate 3: backend loadability
✓ Gate 4: 100-step preview — energies finite, T within ±50 K
```

> "Five validation gates. Schema-level. Semantic-level. Backend
> loadability. A 100-step preview run that catches non-finite
> energies before allocating GPU time."

### [0:42 – 0:54] The output

`{Run:}`

```
$ crucible render spec.json --backend openmm > run.py
```

`{Show the first ~15 lines of the generated script. Cursor highlights
the imports and an obvious AMBER ff14SB line.}`

> "The output is a runnable OpenMM script. Reproducible by
> construction. The IR is the deliverable — render it again for a
> different backend, or feed it to a fine-tuned model later. Your
> protocol stays your protocol."

### [0:54 – 0:60] Close

`{Show github.com/j4qfrost/crucible briefly, then a card with
text:}`

> "Crucible. github.com/j4qfrost/crucible. Open source. Local-LLM
> mode shipping next month."

## Asset checklist before recording

The demo only works if the artifacts on screen are real. Check each:

- [ ] One real paper PDF or arXiv link to use as the source. Pick one
      from the `docs/HALLUCINATION_BENCHMARK.md` seed set so the demo
      and the benchmark land the same wedge. **Recommended**:
      Shaw 2010 Anton BPTI 1ms (DOI `10.1126/science.1187409`) — high
      visibility; the abstract is public so the demo is paywall-safe.
      A pre-extracted abstract-only methods file is shipped at
      `examples/loom_demo/methods_underspecified.txt`.
- [ ] `methods.txt` — extracted Methods paragraphs from the chosen
      paper. Saves cycle time on screen.
- [ ] A live `ANTHROPIC_API_KEY` (or local LLM via Ollama) so the
      `transpile` call actually fires. **Workaround if no budget:**
      record against `crucible templates init kinase_inhibitor_fep
      | crucible health --stdin` and edit narration to match — the
      gates demo is the wedge, not the LLM call itself.
- [ ] Terminal theme: dark background, monospaced 16pt+, no shell
      prompt clutter (just `$`). Set `PS1='$ '` for the recording.
- [ ] Browser tabs cleared except the paper PDF. Bookmarks bar
      hidden. **Personal info on the screen is the #1 take-killer.**
- [ ] Recording mic off any obviously-noisy hardware (laptop fan,
      mechanical keyboard). USB headset preferred.

## Re-record triggers

The Loom is a campaign asset; replace it whenever any of these become
true:

- Crucible's CLI surface changes the spelling of `transpile`, `health`,
  or `render`.
- The hallucination benchmark publishes — re-record to cite the
  number ("89% accuracy across 20 published MD papers" or whatever
  it lands at).
- On-prem mode (`LocalProvider`) ships — say "open source, on-prem,
  no API call leaves your network" instead of "local-LLM mode
  shipping next month."
- Pricing or pilot scope changes (probably not till Phase B).

## Variants (Tier-aware)

The 60-second cut targets all three tiers in
[`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md). Two derivative cuts
land sharper for specific audiences when you have time:

### Tier 2 (pharma CADD) — 75 seconds

Same script through 0:42. Then replace 0:42-0:60 with:

> "On-prem mode runs the LLM locally — your unpublished protocols
> never leave your network. Pilot scope is a 30-day POC against
> 10 of your internal protocols, fixed fee."

### Tier 1 (academic OSS) — 50 seconds

Drop the on-prem mention. After 0:42:

> "The IR is a JSON Schema. The validation gates are 17 Julia
> functions. The benchmark is a public 20-paper test set. Everything
> reviewable. Everything reproducible."

## Distribution

Once recorded:

- **Embed link** in the cold-email templates ([asset #6 in the
  campaign doc](CAMPAIGN_2026Q2.md)). Both PI and CADD variants.
- **Tweet** the unlisted Loom from the Twitter/X account with a
  one-sentence framing (asset #3). Pin until the benchmark replaces it.
- **Landing-page hero** (asset #9) — embed inline above the fold.
- **Practical Cheminformatics guest post** (asset #5) — link in the
  intro paragraph if Pat Walters accepts the pitch.
- **ACS COMP submission** (asset #8) — Loom URL in the abstract's
  "supplementary materials" if format allows.

## See also

- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) — full asset matrix +
  per-tier messaging stack.
- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) —
  the credibility anchor the Loom calls out.
- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md) —
  Phase A week-1 outreach is gated on this asset existing.
