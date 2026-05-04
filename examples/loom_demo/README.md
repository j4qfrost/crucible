# Loom demo — record assets

Hands-off setup for the 60-second Loom record session described in
[`docs/LOOM_DEMO_SCRIPT.md`](../../docs/LOOM_DEMO_SCRIPT.md).

## Files

- **`methods.txt`** — a representative Methods-section blob for an
  Abl + imatinib FEP simulation. **Synthesized for recording**;
  contains all the protocol details a real paper would. Swap with a
  real paper's Methods section before publishing the Loom (asset
  attribution matters; the demo is a marketing artifact).
- **`methods_underspecified.txt`** — a real-paper variant grounded
  ONLY in the public abstract of Shaw 2010 (Anton BPTI 1ms,
  DOI 10.1126/science.1187409). Deliberately omits protocol details
  that are in the paywalled SI. Use this to record the
  *under-specification handling* angle: the LLM should flag missing
  fields rather than hallucinate them, which is also what the
  hallucination benchmark grades for. Attribution is real; no
  fabricated values.
- **`record_session.sh`** — the exact terminal invocations the
  scene-by-scene script in `docs/LOOM_DEMO_SCRIPT.md` calls. Reads
  cleanly on screen at 16pt + dark theme.

## Recording checklist (cross-reference `docs/LOOM_DEMO_SCRIPT.md`)

1. Open a clean terminal at 1080p, font ≥ 16pt, prompt set to bare
   `$` (`PS1='$ '`).
2. Open this directory in the editor: `code examples/loom_demo` (or
   any editor with a dark theme + 16pt+).
3. Pre-flight:
   ```bash
   crucible doctor          # backend reachable
   crucible templates list  # warm the JIT before recording
   ```
4. Record using `record_session.sh`. Single take, no cuts.
5. Replace `methods.txt` with a real paper's Methods section before
   uploading to a public Loom URL — the synthesized version is fine
   for internal sanity-checks but reads as fake under scrutiny.

## Real-paper substitution

Recommended: paraphrase a Methods section from one of the
[`docs/HALLUCINATION_BENCHMARK.md`](../../docs/HALLUCINATION_BENCHMARK.md)
seed-set entries — that way the Loom and the benchmark land the same
paper. Seed-set DOIs:

- `10.1126/science.1187409` — Shaw 2010 (Anton BPTI 1ms)
- `10.1021/jp067192x` — Mobley/Chodera/Dill 2007 (alchemical FEP)
- `10.1016/S0009-2614(99)01123-9` — Sugita & Okamoto 1999 (REMD)
- `10.1021/ja512751q` — Wang 2015 (FEP+)
- `10.1021/ct400314y` — Salomon-Ferrer 2013 (AMBER on GPUs)

Pick the one closest to your audience: pharma-leaning → Mobley 2007
or Wang 2015; methods-leaning → Shaw 2010 (already shipped as
`methods_underspecified.txt` in the abstract-only variant).

## Why a synthesized methods.txt at all?

Per the apps-stall pattern in the user's memory: "libraries finish
cleanly but apps plateau before tests/CI/error paths/deploy." The
real-paper-attribution step is exactly the kind of friction that
turns "record the Loom" into "I'll do it tomorrow." The synthesized
file lets you record the demo today, with the real-paper swap as a
clean follow-up commit.
