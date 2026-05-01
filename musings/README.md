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

- [`why_not_mojo.md`](why_not_mojo.md) — assessment of the
  Julia → Mojo migration question. Conclusion: don't migrate
  (performance argument doesn't apply since the hot path is
  subprocesses, Python-interop argument is moot since the project
  deliberately uses subprocess, ecosystem cost is substantial).
  Three explicit triggers under which the answer would change:
  Mojo-native MD engine, Mojo wins AI/ML standardization, Modular
  licensing shift.

- [`ecosystem_alternatives.md`](ecosystem_alternatives.md) — the
  broader version of the Mojo question: "is Julia the right
  ecosystem at all?" Conclusion: Python is the only meaningful
  alternative; everything else is worse on multiple axes. The
  greenfield Julia-vs-Python decision today would be closer than
  it was when Crucible started, but the right move forward is
  Python *bindings* (Phase 2b in `docs/ADOPTION_PLAN.md`), not a
  port. Three implementation paths analyzed in increasing cost
  order; recommendation given.

- [`why_not_protobuf.md`](why_not_protobuf.md) — should `MDSpec` be
  defined in protobuf instead of JSON Schema? Conclusion: no for
  the IR (LLM-friendliness, human readability, transcript
  flywheel, hand-port advantage all favor JSON). Reserve protobuf
  for the future RPC envelope if `crucible serve` ever fronts a
  typed daemon protocol. For language bindings without a hand
  port, run `quicktype` on `schema.json` rather than owning a
  `.proto`. Triggers for revisiting documented.

- [`python_for_app_layer.md`](python_for_app_layer.md) — evaluation
  of Python on two axes (performance + stall-avoidance). Performance
  is neutral (hot paths are subprocesses or C++/FFI; orchestrator
  language barely matters). Stall-avoidance is where Python
  materially wins: web hosting, packaging, error reporting,
  telemetry, dashboard frameworks, and contributor pipelines are an
  order of magnitude more mature. Conclusion: **library stays Julia
  (per `ecosystem_alternatives.md`); app / UI / deploy layer drifts
  toward Python**. Subprocess is the seam. The v1.24 bindings and
  v1.29 corpus GUI are the empirical evidence.

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
