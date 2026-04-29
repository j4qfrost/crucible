# Musings

Project-internal explainers and architectural-decision notes that don't
fit `docs/` (spec/contributor reference) or `examples/` (runnable demos).

## Contents

- [`quantum_outlook_eli5.md`](quantum_outlook_eli5.md) — companion to
  `docs/QUANTUM_OUTLOOK.md`. Same conclusions; uses the actual jargon
  (VQE, QPE, Trotter, fault-tolerant, NISQ, …) but with a glossary of
  analogies at the end. For someone who's seen "quantum will
  revolutionize drug discovery" headlines and wants to know whether to
  take them seriously.

- [`why_subprocess_over_pythoncall.md`](why_subprocess_over_pythoncall.md) —
  why Crucible shells out to `python script.py` instead of using
  PythonCall.jl + CondaPkg. The rendered script is the deliverable,
  optional deps stay optional, the integration boundary is the LLM
  not the runtime. The decision is reaffirmed every time we add a
  new Python interop point.

- [`why_ir_as_contract.md`](why_ir_as_contract.md) — why the LLM
  emits MDSpec JSON, not runnable Python. Hallucinations collapse
  to a finite enum/numeric space; multi-backend rendering is free;
  the fine-tune flywheel becomes feasible. The most-important call
  the project has made.

- [`why_dual_ci.md`](why_dual_ci.md) — why both GitHub Actions and
  Woodpecker run on every push. The story of getting clamped on
  GH Actions billing, the trade-off of two YAMLs to maintain, and
  when to drop one.

- [`why_no_genie.md`](why_no_genie.md) — why `WebRenderer` is built
  on HTTP.jl directly instead of Genie.jl. Eight endpoints, one
  string-literal SPA, tests that hit the router function directly
  without binding a port. Genie isn't wrong; it's just overkill for
  Crucible's web surface.

- [`scaling_modes.md`](scaling_modes.md) — how Crucible scales as a
  product across academia, private business, and open source. Three
  distinct modes with different bottlenecks; cross-mode dynamics
  (academia feeds OSS, OSS feeds business via open-core, etc.); the
  honest take that the bottleneck is maintainer time, not
  architecture or market. Companion to
  [`docs/ADOPTION_PLAN.md`](../docs/ADOPTION_PLAN.md), which is the
  operational version.

## When to add a musing

Add one when you've made an architectural decision that:

- a future contributor (or you, three months from now) will be tempted
  to relitigate, and
- the right answer depends on context that isn't obvious from the
  diff or the code comments.

Don't add one for:

- A bug fix or refactor (that's a commit message + maybe a test).
- A feature addition (that's the changelog).
- A user-facing concept (that's a doc).

Musings are for the design philosophy that lives between the code and
the user-facing docs.

## Format

Each musing is a single Markdown file in this directory. Open with
the decision in one sentence; spend the body on the context that
made it the right call; close with the conditions under which it
should be re-evaluated. Future-you should be able to read one in
five minutes and skip a re-derivation that would have cost a
half-day.
