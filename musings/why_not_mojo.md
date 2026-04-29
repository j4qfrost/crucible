# Why not Mojo (yet)

Periodically the question comes up: should Crucible migrate from
Julia to Mojo? Mojo's pitch — Python syntax + MLIR-backed
performance + native Python interop — sounds like it should be a
strict upgrade for a project that talks to Python subprocesses all
day. This musing is the record of why the answer, **as of
2026-04-29, is no**, and the explicit triggers that would change
the answer.

## The core argument in one paragraph

Crucible's hot path isn't in Julia code — it's in the OpenMM/Molly
subprocesses. Mojo's MLIR-backed numerical performance would buy us
~10ms on a simulation that takes hours. Mojo's tighter Python
interop would buy us nothing because the project deliberately chose
subprocess over PythonCall (`musings/why_subprocess_over_pythoncall.md`)
— the integration boundary is at the process layer, not the
function-call layer. The migration cost is 6-12 months of full-time
work plus a reset of every architectural-decision record in this
directory. The performance and ergonomic upside are zero;
the ecosystem downside is substantial. Don't migrate.

## What Mojo gets right (where the temptation comes from)

- **Python-syntax familiarity.** Comp-chem and ML communities are
  Python-native. A grad student inherits Mojo more easily than
  Julia.
- **MLIR backend.** Genuinely good performance for numerical inner
  loops. If you're writing kernels, Mojo is a serious choice.
- **Native Python interop.** `from python import numpy` works.
  No PythonCall.jl gymnastics.
- **Modular's funding + commercial backing.** Could mean sustained
  language development, mature tooling.

If you were starting a *new* MD-adjacent project today and the
question was Mojo vs. Python, Mojo could win on the right shape of
problem. The question for Crucible is migration from a working Julia
codebase, which is a different equation.

## What Crucible would lose

### Mature Julia ecosystem

| Component | Julia today | Mojo (2026 reality) |
|---|---|---|
| MD engine | `Molly.jl` (real, Julia-native, used in production) | None |
| Notebook UI | Pluto.jl + the project's two walkthrough notebooks | None |
| JSON Schema validation | `JSONSchema.jl` (battle-tested) | Would need to write |
| HTTP server | `HTTP.jl` (`crucible serve`'s 8 endpoints) | Limited; would need Python interop or rewrite |
| Test framework | stdlib `Test` + `Pkg.test` (868 tests) | Nascent |
| Embedded DB | `DuckDB.jl` for the transcript store | Likely via Python interop |
| Templating | `Mustache.jl` | Would need to write |
| Unitful types | `Unitful.jl` for IR field types | Reimplement |

For each row: real, working integration we'd discard.

### Architectural-decision context

Every musing in this directory references the Julia codebase. The
v2 IR scaffolding for constph + Martini assumes Julia conventions.
The five hard rules in AGENTS.md cite Julia files. The role-specific
reading guides in `docs/HOW_TO_READ.md` assume Julia familiarity.

A migration would need to either rewrite all of this (massive doc
debt) or leave it pointing at deleted code (worse).

### The Pluto study notebooks

`examples/walkthrough_v15_methods.jl` and
`examples/study_validation_gates.jl` are Pluto-specific. Pluto's
reactive cell model has no Mojo equivalent. The pedagogical surface
the project just spent v1.18-v1.20 building would need a different
home.

### The maintainer's accumulated Julia knowledge

This is the silent cost. The current maintainer is fluent in Julia +
the package ecosystem. A Mojo migration is a 3–6 month relearning
curve before any productive work happens. The adoption plan
(`docs/ADOPTION_PLAN.md`) doesn't have that slack.

## What Crucible would gain (the honest accounting)

- **Marginal performance** the workload doesn't need.
- **Cleaner Python interop** the architecture deliberately doesn't
  use (`musings/why_subprocess_over_pythoncall.md`).
- **A Python-syntax codebase** that's easier for some contributors
  to read but uses an ecosystem an order of magnitude smaller than
  Python's or Julia's.

That's the whole list. Honest.

## What about the contributor-pool argument?

The pitch: "more people know Python than Julia, so Python-syntax
Mojo will attract more contributors than Julia."

Reality check:

1. **Mojo's contributor pool today is much smaller than Julia's.**
   Mojo has ~10k active developers vs. Julia's ~100k. The Python-
   syntax similarity helps with onboarding but the pool itself is
   smaller right now.
2. **The ceiling argument requires Mojo to win the AI/ML
   standardization war.** Possible but not certain. Two years ago,
   the same argument was made for Rust ("more Rust developers will
   exist than Julia developers"). It mostly didn't pan out for
   scientific computing. Mojo has a stronger commercial backer
   than Rust did, which helps but isn't sufficient.
3. **Crucible's contributor barrier isn't language fluency, it's
   domain familiarity.** Adding a stage type requires understanding
   the IR + the validation gates + the renderer pattern. That
   knowledge is language-agnostic; the rewrite doesn't help here.

## Three triggers that would change the answer

A migration becomes the right call if any one of these fires.

### Trigger 1: A Mojo-native MD engine emerges that beats OpenMM

If someone ships `MojoMD.jl`-equivalent (a real, performant Mojo MD
engine) and it has technical advantages over OpenMM (better GPU
utilization, novel sampling algorithms, faster energy evaluation),
*then* the language choice has scientific rather than aesthetic
value. We'd want to be in Mojo to use it natively.

Probability in 5 years: low but non-zero. MD-engine development is
slow (Molly.jl took ~5 years to mature; OpenMM has 15+); a Mojo
contender would need to start now. **Track**: search for "molecular
dynamics" + "Mojo" annually.

### Trigger 2: Mojo wins the AI/ML standardization war

If the default scientific computing language in 2030 becomes Mojo
(analogous to Python beating Tcl/Perl/R for general data work in
the 2000s), ecosystem migration becomes inevitable. Crucible would
follow the broader scientific-computing community, not lead it.

Probability: uncertain. Depends on:
- Modular's commercial trajectory (acquisition, IPO, demise)
- CUDA/MLIR rivalry (Mojo bets on MLIR; CUDA's lock-in is sticky)
- Whether NumPy / SciPy / PyTorch start integrating Mojo natively
- Whether the academic community's Python-default starts shifting

**Track**: PyPI top-1000 packages adopting Mojo as a primary or
significant target. Annual review.

### Trigger 3: Modular shifts licensing or pricing in a way that punishes Julia

If Modular acquires a key Julia library (unlikely but possible) and
locks it Mojo-only, or if Modular's pricing for Mojo SDK becomes
strategically advantageous in a way Julia can't match, the calculus
changes.

Probability: low. **Track**: Modular's commercial announcements +
licensing changes.

## What about partial adoption?

Could Crucible add a Mojo backend alongside the Julia core, the
way it has both OpenMM and Molly?

Theoretically yes. Practically:

- The IR + validation + render path is in Julia. A Mojo-side
  consumer would need to either re-implement validation in Mojo
  (duplication) or call into Julia (no clean path) or read the IR
  JSON and render its own scripts (which is a separate tool, not
  a Mojo backend).
- The CLI is in Julia. A Mojo-side CLI is a separate tool.
- The web frontend is in Julia. A Mojo SPA is a separate tool.

What you actually get from "a Mojo backend" is "a separate Mojo
tool that consumes Crucible's IR." That's the IR-as-contract bet
working as designed — the *tool* is in any language, the IR is the
contract. If a contributor wants to ship a Mojo-native renderer
that consumes `MDSpec` JSON and emits Mojo-flavored OpenMM-equivalent
code, that's a separate project and Crucible would happily link to
it. No migration of the core required.

## When to revisit

- **Annually.** Quick check of all three triggers; update this
  musing if the trajectory has shifted.
- **When the adoption plan re-evaluates.** Phase 2 decision gate
  (9-month mark per `docs/ADOPTION_PLAN.md`) is a natural
  re-examination point.
- **If a contributor proposes the migration.** Read the analysis
  here first. If their argument addresses one of the three triggers,
  weigh seriously. If their argument is "Mojo is faster" or "Mojo
  has Python interop," send them to the relevant section.

## See also

- `musings/why_subprocess_over_pythoncall.md` — why the Python
  interop boundary is at the process level. The single biggest
  reason Mojo's interop story doesn't help.
- `musings/why_ir_as_contract.md` — why the IR is the contract,
  language-agnostic. A Mojo-side renderer is possible without
  migrating the core.
- `musings/scaling_modes.md` — the broader strategic picture. The
  migration question is one input to scaling.
- `musings/quantum_outlook_eli5.md` — analogous "this hyped
  technology is real, but not a fit for our workload yet" record.
  Same shape of analysis.
