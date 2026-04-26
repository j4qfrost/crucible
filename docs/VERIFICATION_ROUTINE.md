# 2-week verification routine

## What it is

A scheduled remote agent (Claude Sonnet 4.6) configured to fire once at
**2026-05-10T16:00:00Z** (~9am PDT). The routine ID is
`trig_01NMfAZfi6Zwrj9HTEoyUxrj`. View / edit / cancel via:
<https://claude.ai/code/routines/trig_01NMfAZfi6Zwrj9HTEoyUxrj>

## Why it exists

When this routine was scheduled, the project was at v0 (37 files, no
runs of `Pkg.test()` had ever happened). The routine's job was to
verify Julia could install + the test suite would run on a clean
sandbox in two weeks, and to surface any gaps that crept in.

By the time it actually fires, the project has grown substantially
(the routine doesn't know that). So the routine should treat its
prompt as a starting point and be willing to discover the project
has matured.

## What the routine should do

In order:

1. **Verify Julia is available** in the sandbox. If not, install via
   juliaup; if that fails too, write a brief `docs/POST_V0_FOLLOWUPS.md`
   noting the failure and stop.

2. **Run `Pkg.test()`** at the repo root. Expect ~150 tests passing.
   Tests are deterministic — no API keys, no GPU, no OpenMM required
   for the baseline suite.

3. **Survey integration health**:
   - Is `tools/check.sh` clean? (full pre-commit gate runner)
   - Does `examples/walkthrough.jl` exit 0?
   - Does `examples/lifecycle.jl` exit 0?
   - Are there any TODO/FIXME comments newer than the v0 commit
     (`fe5299c`) that look stale?
   - Has `docs/IR.md` drifted from `src/spec/schema.json`?

4. **Inspect (without running)**:
   - `src/backends/OpenMMBackend.jl`: still using subprocess, no
     PythonCall dep added?
   - `src/llm/AnthropicProvider.jl`: still no-op without API key?
   - `src/spec/MDSpec.jl`: schema_version still `0.1.0` or has a
     migration in `src/spec/Migrations.jl` covering the bump?
   - The Molly backend: still confined to its declared sweet spot?

5. **Write `docs/POST_V0_FOLLOWUPS.md`** with sections:
   - **Test results** (pass/fail counts; brief diagnoses for any
     failures with file:line references and 1-2 sentence fixes)
   - **PythonCall + CondaPkg integration status** — note that
     subprocess was the chosen path, not PythonCall
   - **Anthropic provider end-to-end status** — has the live smoke
     ever run? (`CRUCIBLE_RUN_ANTHROPIC=1` + secret in Woodpecker)
   - **Other gaps surfaced**
   - **Recommended next sprint** — 3-5 concrete tasks in priority
     order

6. **Open a PR** on the `post-v0-followups` branch with the
   followups doc. Do NOT merge. Do NOT push to main. Do NOT modify
   anything outside `docs/`.

## What the routine should NOT do

- Do not run live OpenMM (the sandbox lacks a GPU and OpenMM may
  not be installed; the package's deterministic suite is the right
  test).
- Do not call the Anthropic API (no key, and even if there were
  one, it would charge the user).
- Do not touch `~/Projects` or any other repo.
- Do not regenerate `recorded_anthropic_spec.json` — that's a
  human-supervised refresh via `tools/regenerate_fixtures.sh`.

## Self-hosted-hybrid-ci follow-up (TODO for a future routine)

When the user's `self-hosted-hybrid-ci` infrastructure exists, a
*separate* routine should also push or upload the project there.
That routine doesn't exist yet — leave a one-line note in the
followups file calling this out.
