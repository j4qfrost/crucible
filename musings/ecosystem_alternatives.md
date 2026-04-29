# Ecosystem alternatives (Python, Rust, others)

The Mojo question (`why_not_mojo.md`) is one specific instance of a
broader recurring question: **is Julia the right ecosystem for this
project, and if not, what's a better fit?** This musing is the
durable record of the broader analysis.

The short version, for the impatient reader:

> **Python is the only ecosystem that's a real alternative to Julia
> for Crucible. Everything else is meaningfully worse on multiple
> axes. Python's advantages are real, and a greenfield project
> today would have a closer Julia-vs-Python decision than the one
> the project made in 2026 — but the right move forward is to add
> Python bindings (Phase 2b in `docs/ADOPTION_PLAN.md`), not to
> port the core. The IR-as-contract bet means consumers can be in
> any language; the implementation language matters less than the
> ecosystem inertia and contributor pipeline.**

## The candidates evaluated

| Ecosystem | MD libraries | LLM tooling | Contributors | Net fit |
|---|---|---|---|---|
| **Python** | Vast (OpenMM, OpenFF, mdtraj, MDAnalysis, openmmtools, openmmforcefields, pymbar, RDKit, NGLview) | Excellent (pydantic + instructor + marvin + native vendor SDKs) | Largest pool by far | **Genuinely competitive with Julia** |
| **Julia** (current) | Real (Molly.jl, JuMP, DiffEq, Catalyst, DuckDB, JSONSchema, Pluto, HTTP) | Adequate (anthropic-julia, hand-rolled provider abstraction) | ~100k devs | Defensible original choice |
| **Mojo** | None | Nascent | ~10k devs | See `why_not_mojo.md` — no |
| **Rust** | None (some viz: rerun.io) | crates exist (serde + nascent structured-output) | Large + growing | Beautiful IR, terrible everything else |
| **TypeScript / Node** | Effectively none | Strong (Vercel AI SDK, Anthropic TS SDK) | Huge in web | Strong frontend, wrong elsewhere |
| **Go** | Effectively none | Adequate | Large in infrastructure | Wrong community for science |
| **C++** | Where the engines actually live | Manual (no high-level LLM lib) | Small + aging | Hostile to contributors |
| **Nim / Crystal / Zig / Common Lisp** | None | None | Tiny | Not serious options |

The MD-libraries column is the dominant axis. Without a real MD
ecosystem, the project becomes "subprocess to Python forever" with
no native engine — which means the rendered-script-is-deliverable
invariant still holds, but the dual-backend (OpenMM + Molly) story
collapses.

## The Python case (in more detail)

### What Python would offer that Julia doesn't

1. **Native imports of OpenMM, OpenFF, openmmtools, mdtraj.** No
   subprocess plumbing. The `_emit_*` renderer functions in
   `OpenMMBackend` would still emit a Python script (the script is
   the deliverable; that's load-bearing per
   `why_ir_as_contract.md`), but the surrounding orchestration
   gets simpler.

2. **~10× larger contributor pool.** Comp-chem and ML are
   Python-native. Every grad student knows Python; ~5% know Julia.
   The bus-factor risk in `scaling_modes.md` is meaningfully better
   in Python.

3. **Better LLM tooling.** Pydantic + Instructor + Marvin give you
   structured-output validation in ~3 lines per provider. Crucible's
   manual `LLMProvider` + `TranspileResult` + schema-validation
   plumbing is more code than the Pythonic equivalent would be.

4. **Familiar to pharma + biotech.** All three flagship application
   docs (cancer / materials / protein engineering) involve users
   who know Python and may not know Julia. Adoption story is
   friendlier.

5. **Schrödinger / OpenEye / Cresset / Genesis Therapeutics
   ecosystems are all Python.** Open-core integration with their
   existing toolchains is one `pip install` away.

### What Julia offers that Python doesn't

1. **Molly.jl exists.** A real Julia-native MD engine. Crucible's
   `MollyBackend + OpenMMBackend` is genuinely a dual-backend
   story. In Python, the only path is "subprocess to OpenMM";
   there's no Python-native MD engine that's competitive.

2. **Pluto.jl reactive notebooks.** The two walkthrough notebooks
   (`walkthrough_v15_methods.jl`, `study_validation_gates.jl`) use
   Pluto's reactive cell model — slider changes propagate through
   downstream cells automatically. Jupyter doesn't have this;
   Marimo (the closest Python equivalent) is younger than Pluto
   and less integrated.

3. **Multiple-dispatch type system.** The `Stage` hierarchy
   (`MinimizeStage <: Stage`, `DynamicsStage <: Stage`, …) and
   per-stage renderer dispatch are unusually clean. Python's
   `dataclasses.dataclass` + `match` is fine but less elegant.

4. **Iteration speed for the maintainer.** 868-test suite in
   ~20 seconds; Python's pytest equivalent would be slower. Not
   load-bearing for users; meaningful for daily-iteration speed.

5. **Subprocess-as-default is a feature, not a bug.** Per
   `why_subprocess_over_pythoncall.md`, the integration boundary
   should be the process layer. Python's "native imports"
   advantage cuts in the wrong direction: it tempts you to bake
   assumptions about a specific OpenMM version into the code.
   Subprocess preserves the rendered-script-is-deliverable
   invariant.

### The honest Julia-vs-Python comparison

If Crucible were greenfield today, the Python case would be
stronger than it was when the project started. But "stronger" ≠
"obviously better." The two ecosystems are roughly tied; the
project's design choices monetize Julia's strengths (Molly, Pluto,
type system) while not relying on what Julia lacks.

A clean port to Python would be:

- 6–9 months of full-time work
- Reset of the 22 versions of architectural decisions in
  `musings/`
- Loss of the dual-backend story (Molly disappears)
- Loss of both Pluto walkthrough notebooks
- Loss of the maintainer's accumulated Julia fluency
- Gain of access to the larger contributor pool

The bus-factor argument cuts both ways: the larger pool reduces
catastrophic-loss risk, but the migration itself is bus-factor
risk concentrated in one undertaking.

## What Python users should get instead: bindings

Phase 2b of the adoption plan already lists this:

> **Python bindings (or equivalent FFI) for the IR + render layer.**
> Major adoption blocker is the Julia requirement; Python bindings
> let Python-only labs use Crucible without learning Julia. ~6–10
> weeks of work.

What that actually looks like:

```python
import crucible

spec = crucible.templates.init("kinase_inhibitor_fep")
spec.system.source.ligand_smiles = "Cc1ccc(NC(=O)c2cccnc2)cc1"
spec.protocol[3].duration_per_window_ns = 5.0

report = crucible.health(spec)              # gates 1-3 + lint + coverage
script = crucible.render(spec, "openmm")    # returns the OpenMM Python source
crucible.run(spec, workdir="runs/exp1",     # subprocess + monitor
             seed=42, precision="mixed")
events = crucible.events("runs/exp1")
```

Three implementation paths in increasing cost order:

### Path 1: Subprocess-only client (~2 weeks)

Python module that wraps `crucible <subcommand>` calls. The CLI
already accepts JSON input + emits JSON via `--format json` for
most subcommands. Build the Python client as a thin wrapper.

Pros: simplest, no Julia in the Python user's environment.
Cons: serialization overhead per call (JSON in, JSON out for every
operation); CLI-style errors get shoehorned into Python exceptions.

### Path 2: PythonCall.jl bridge (~6 weeks)

Julia is the engine; Python imports it via PythonCall (the inverse
of PyCall). Crucible objects become Python proxies.

Pros: in-process, low overhead, full feature access.
Cons: pulls Julia into the Python user's environment. CondaPkg
solves the conda environment, but it's a real install cost. Some
features (Pluto notebooks specifically) won't translate.

### Path 3: Re-implement IR + validation in Python (~8 weeks)

Pure-Python `MDSpec`, schema validation, JSON migrations. The CLI
+ renderer + LLM transpile stay in Julia (called via subprocess
for those). Path 1 + Path 3 in tandem.

Pros: nicest UX for Python users; no Julia dependency for IR
manipulation; can use pydantic for the type layer.
Cons: duplicate IR implementation (drift risk). Mitigation: the
JSON Schema is the contract; cross-language tests pin behavior.

**My recommendation: Path 3 if/when committed to Phase 2b.** The
IR is what Python users will most-want to manipulate
programmatically; the renderer and LLM transpile are usually
one-shot subprocess calls. Splitting the layers gives the best
ergonomic story without a full port.

## What about the polyglot architecture?

Crucible is already mostly language-agnostic at layer boundaries:

| Layer | Wire format | Could live in |
|---|---|---|
| IR + schema | JSON | Anywhere that speaks JSON |
| CLI + renderer | reads JSON, writes scripts | Anywhere |
| LLM transpile | HTTP + JSON | Anywhere |
| Backends | subprocess (OpenMM) or in-process (Molly) | Mixed |
| Web frontend | HTTP + JSON | Anywhere |
| Transcript store | DuckDB | Anywhere with DuckDB bindings |

A polyglot Crucible — IR in Rust, CLI in Go, renderer in Python,
web frontend in TypeScript — is *conceivable*. The IR-as-contract
design (`why_ir_as_contract.md`) enables it.

But:

- Contributor onboarding cost goes from "learn Julia" to "learn
  4 languages." Much worse, not better.
- Build complexity multiplies. CI matrices explode.
- Per-language test suites duplicate effort.
- The architectural musings would need rewriting per language.

The polyglot version is a feature of the *deployment* (a third
party can write their own Crucible-IR consumer in any language),
not a feature of the *codebase* (Crucible itself stays in one
language). This is the right design.

## When this analysis should change

- **A Python project ships an MDSpec-equivalent IR** with similar
  scope. Then the question becomes "merge or compete," and either
  way Crucible's positioning changes. **Track**: BioSimSpace,
  OpenFF Evaluator, OpenMM-Setup quarterly.
- **Mojo wins the AI/ML standardization war** (also a trigger for
  `why_not_mojo.md`). Then the Python case weakens because Python
  is in the same boat.
- **Julia's adoption growth stagnates or reverses.** If Julia loses
  ground broadly in scientific computing, the contributor-pool
  argument tilts further toward Python. **Track**: Julia community
  metrics, JuliaCon attendance, JOSS Julia-paper count vs Python.
- **A Mojo-native or Rust-native MD engine emerges that beats
  OpenMM.** Same logic as `why_not_mojo.md` — the ecosystem
  question becomes scientific rather than aesthetic.

Until one of these triggers, the answer is: **Julia for the core,
Python bindings for adoption**.

## See also

- `musings/why_not_mojo.md` — the specific Mojo case. Same shape
  of analysis at smaller scope.
- `musings/why_subprocess_over_pythoncall.md` — why the integration
  boundary is the process layer. Foundational to why language
  choice matters less than it might seem.
- `musings/why_ir_as_contract.md` — why the IR being JSON makes
  the "polyglot" question tractable.
- `musings/scaling_modes.md` — the broader strategic picture; the
  ecosystem question is one input.
- `docs/ADOPTION_PLAN.md` Phase 2b — where Python bindings live in
  the operational plan.
