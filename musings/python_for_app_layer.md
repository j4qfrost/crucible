# Python for the app layer (performance + stall-avoidance)

A recurring question after shipping the v1.24 Python bindings and the
v1.29 Streamlit corpus GUI: **does more of Crucible belong in Python**,
both for performance and to avoid the apps-stall pattern that has
sunk earlier projects? This musing is the honest evaluation.

## The core argument in one paragraph

Performance is not the right axis for this question — Crucible's hot
paths are subprocesses (OpenMM via rendered Python script) or
C++/Rust libraries called via FFI (DuckDB), so the orchestration
layer's language barely moves the throughput needle. The right axis
is **stall-avoidance**: the friction at the "ship to a real user"
boundary, where libraries graduate into apps. Python materially wins
on that axis — web hosting, packaging, error/telemetry SDKs, and
deploy playbooks are all an order of magnitude more mature than
Julia's. The recommendation is **not** to port the library; it's to
formalize a split that's already happening — **library stays in
Julia (IR, validation, renderers, LLM transpile, scientific test
suite); app / UI / deploy layer drifts toward Python (corpus GUI
shipped, hallucination-benchmark dashboard next, eventual on-prem
mode wrapper)**. Subprocess is the seam between the two, exactly as
`why_subprocess_over_pythoncall.md` argued.

## Performance — Python is fine

The hot paths in Crucible, ranked by realistic wall-clock time:

| Operation | Hot loop in… | Orchestration language matters? |
|---|---|---|
| LLM extraction (paper → MDSpec) | Anthropic API HTTP roundtrip | No |
| JSON Schema validation (Gate 1) | C-backed validator (`jsonschema` / `JSONSchema.jl`) | Negligible |
| Semantic rules (Gate 2) | 17 small functions, microsecond regime | No |
| Renderer (MDSpec → script) | string templating | No |
| Backend execution | OpenMM (C++/CUDA) via subprocess; Molly.jl in-process | No (orchestrator is glue) |
| DuckDB queries (corpus, transcripts) | DuckDB engine (C++) via FFI | No |
| Pluto notebook reactivity | Pluto runtime (Julia-only) | Julia-only by accident |
| Streamlit GUI rendering | Streamlit runtime (Python-only) | Python-only by accident |

**Cold start is the only place language choice meaningfully shows
up**, and Python wins there (~50 ms vs. Julia's TTFX ~3–30 s on
first invocation). Cold-start matters for short-lived processes
(CLI invocations, web request handlers, GUI launch); it doesn't
matter for hour-long simulations. The CLI's existing
PackageCompiler-based AOT image collapses Julia's TTFX to ~150 ms,
which closes most of the gap.

The v1.29 corpus module shipped entirely in Python with no perf
complaint. The hallucination benchmark is a 20-paper batch job;
Python's per-paper overhead is invisible against the API roundtrip
+ DuckDB write.

**Verdict: performance is not a reason to use Python, and not a
reason against it.** It's neutral. Pick by the other axis.

## Stall-avoidance — Python materially wins

The user's apps-stall pattern: **libraries finish cleanly,
apps plateau before tests / CI / error paths / deploy**. The friction
that triggers the stall is almost always at the "ship to a real
user" boundary, not in the core feature work. So the right
question isn't "what language ships features fastest?" — it's
"what language has the lowest friction at the deploy boundary?"

Honest comparison on the surfaces that decide whether an app stalls:

| Surface | Python | Julia | Asymmetry |
|---|---|---|---|
| Web hosting | Streamlit Cloud, HF Spaces, Fly.io, Render, Vercel (FastAPI), Replit. 5-min deploy paths everywhere. | PlutoSliderServer.jl + Docker + tedious config; no SaaS equivalent. | Large |
| Packaging | `pip install` + `pyproject.toml` is the path-of-least-resistance everyone knows. | `Pkg` is technically excellent but `julia --project -e 'Pkg.instantiate()'` is friction for a non-Julia user. | Medium |
| Error reporting | Sentry SDK is mature, drop-in. | Sentry.jl is alpha-ish. | Medium |
| Telemetry | OpenTelemetry SDK is full-featured. | OpenTelemetry.jl exists, less complete. | Medium |
| Dashboards / data UI | Streamlit, Gradio, Panel, Dash, Plotly — all polished. | Genie + Stipple, Pluto-as-app. Smaller surface. | Large |
| CI/CD | GitHub Actions Python action ecosystem is enormous. | `julia-actions/setup-julia` works fine, but matrix coverage is narrower. | Small |
| Web frameworks for the impatient | FastAPI hot reload + Pydantic + Uvicorn = Hello-World-to-deployed in 30 minutes. | HTTP.jl + Genie / Bonito = same job, ~2× friction, smaller community. | Medium-large |
| Contributor pipeline | "I can hire a Python intern who can ship" is true everywhere. | Same statement requires meaningfully more search effort. | Large |
| Mobile / Electron wrappers | tauri-py, Briefcase, kivy. | Effectively non-existent. | Large |
| Onboarding for non-language-natives | Pip is universal. | Julia install is one extra step many users won't take. | Medium |

The asymmetry isn't about language quality. Julia is technically
excellent for the library tier. The asymmetry is about
**deploy-ecosystem maturity**, which exists at the Python tier in a
form Julia hasn't yet caught up to. For a maintainer who has
historically stalled at the deploy boundary, this matters more than
the language's intrinsic ergonomics.

## What this means concretely for Crucible

Two things are already happening; this musing names them so they're
deliberate, not accidental.

### What stays in Julia (no change)

- The IR (`MDSpec`) and schema (`schema.json` is the cross-language
  contract).
- All five validation gates' core (gate 3 / 4 are backend-side and
  language-bound to the backend).
- Renderers (`OpenMMBackend`, `MollyBackend`).
- LLM transpile providers (`AnthropicProvider`, `LocalProvider`).
- The 30-subcommand CLI (`bin/crucible`) and its dispatch logic.
- Pluto walkthrough notebooks (`examples/walkthrough_v15_methods.jl`,
  `examples/study_validation_gates.jl`).
- The 868-test scientific suite.

### What drifts toward Python (already started)

- **Python bindings of the IR layer** (v1.24, shipped). Pure-Python
  validate / lint / coverage / templates / migrate so headless
  consumers don't need Julia.
- **Corpus + corpus GUI** (v1.29, shipped). OpenAlex client +
  DuckDB + Streamlit GUI, all Python.
- **Hallucination benchmark dashboard** (queued, Phase A weeks
  2–3). The dashboard belongs in Python; the underlying
  benchmark runner shells out to the Julia CLI for the actual
  MDSpec → render → compare cycle.
- **Future on-prem deployment wrapper.** A FastAPI service that
  orchestrates Crucible runs against an Ollama-backed
  `LocalProvider`. The wrapper is Python; the work it dispatches
  is Julia subprocess.
- **Future telemetry / Sentry / OpenTelemetry hooks.** Python's
  SDKs are the path of least resistance.
- **Future hosting deploy** (Fly.io / Render / similar). The
  Python tier carries the deployable surface; Julia stays
  invocable as a sidecar.

### The seam

Subprocess, exactly as `why_subprocess_over_pythoncall.md`
specified. Python invokes `bin/crucible <subcommand>` (already wired
in `python/crucible/cli_bridge.py`). The IR is JSON, the wire format
is `--format json`. Adding new Python services on top is purely
additive — no Julia code changes.

This is also why the v1.29 corpus could ship in Python without
touching the Julia tree: the seam was already in place from v1.24.

## Triggers for revisiting

- **If Pluto cloud-deploy lands cleanly.** A `PlutoSliderServer.jl`
  SaaS or a polished Pluto-on-Fly.io path would shrink the
  asymmetry on the dashboard surface. Track quarterly.
- **If a Julia web framework hits Streamlit-like deploy
  ergonomics.** Bonito + a hosted runner, or Genie + a SaaS, or
  GenieFramework as a managed service — any of these could change
  the calculus.
- **If the user wants single-language ownership for downstream
  contributors.** A research lab that's all-Julia might prefer
  Julia tooling end-to-end even at the cost of more deploy
  friction. So far the user's contributors are polyglot.
- **If a Julia-native version of `[Streamlit equivalent]` hits 1.0
  with managed hosting.** This is the single biggest asymmetry; a
  fix here flips the recommendation.

Until one of these triggers, the answer is: **library stays in
Julia, app / UI / deploy drifts toward Python, subprocess is the
seam**. The question of "should we migrate the library?" is
answered separately by `ecosystem_alternatives.md` (no), and that
answer doesn't change.

## Why this isn't drift

A reviewer might worry that "Python for app layer" is a slippery
slope toward "Python for everything," which `ecosystem_alternatives.md`
considered and rejected. The defense is structural:

- The library has a hard contract (the IR + schema + 5 gates).
  Anything that touches that contract has to honor the
  language-symmetric tests.
- The app layer doesn't have a hard contract beyond "consume the
  IR or shell out to the CLI." It can reorganize freely.
- The seam (subprocess + JSON) is enforced by lack of a shared
  address space, which is mechanical, not a discipline question.
- New Python deps don't ratchet the Julia install footprint; the
  base `crucible` (pure-Python) install stays lean (`[corpus]` and
  `[ui]` are opt-in extras, exactly as v1.29 did).

## See also

- [`musings/ecosystem_alternatives.md`](ecosystem_alternatives.md) —
  why the *library* stays Julia. This musing is the orthogonal
  decision: where does Julia stop and Python start?
- [`musings/why_subprocess_over_pythoncall.md`](why_subprocess_over_pythoncall.md)
  — the seam between the tiers. The pattern that makes the
  Python-on-top approach work without coupling.
- [`musings/why_not_protobuf.md`](why_not_protobuf.md) — keeps the
  IR JSON, which is what enables the polyglot tier-split this
  musing depends on.
- [`musings/scaling_modes.md`](scaling_modes.md) — the broader
  strategic picture; deploy-friction is a load-bearing constraint
  in the academic-OSS-business mode comparison.
- The v1.24 Python bindings (`python/crucible/`) and v1.29 corpus
  GUI (`python/crucible/corpus/ui.py`) are this musing's
  empirical evidence.
