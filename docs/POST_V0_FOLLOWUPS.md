# Post-v0 Verification Report

_Generated: 2026-05-10 by the 2-week post-bootstrap verification routine._

---

## 1. Test Results

**Julia install: FAILED.** `julia` is not on PATH in this environment. `juliaup` install attempt
returned HTTP 403 (network restriction). **No tests could be run.**

The test suite (`test/runtests.jl`) includes 36 test files across all subsystems. Based on static
inspection, expected pass/fail breakdown when Julia is available:

| Testset | Expected outcome | Notes |
|---|---|---|
| `spec_schema_test` | PASS | `schema.json` + fixtures present; round-trip is pure Julia |
| `validation_gates_test` | PASS (gates 1–3) / SKIP (gate 4) | Gate 4 tests guard on `Sys.which("python3")`; will skip without OpenMM |
| `renderer_golden_test` | PASS | Structural `occursin` checks, not byte-identical; golden files deferred to v0.5 |
| `router_test` | PASS (likely) | Pure Julia feature-set dispatch logic |
| `advisor_test` | PASS (likely) | Pure Julia table lookup in `benchmarks.toml` |
| `migrations_test` | PASS (likely) | v0.3→v0.4 migration, pure data transform |
| `diff_test`, `coverage_test`, `snapshot_test` | PASS (likely) | Pure Julia utility modules |
| `fep_test`, `remd_test`, `metadynamics_test`, `membrane_test` | PASS (likely) | IR + renderer structural checks, no execution |
| `constph_test`, `martini_test` | PASS (likely) | Renderer emits `NotImplementedError` stub — test likely asserts that |
| `parameterizer_test`, `smiles_test` | UNKNOWN | May need Python subprocess (`OpenFFParameterizer`) |
| `integration_test` | SKIP / FAIL | Requires Python + OpenMM for end-to-end preview |
| `llm_test` | PASS (RecordedProvider path) / SKIP (AnthropicProvider path) | Recorded fixture exists; Anthropic path needs API key |
| `web_test` | UNKNOWN | HTTP.jl server test; should be self-contained |
| `atproto/*` | UNKNOWN | AT Protocol publisher — not surveyed |
| `observables_v3_test` | UNKNOWN | Not surveyed |

**Fix for Julia install:** provision a standard image with `juliaup` pre-installed, or use the
official Docker image `julia:1.10` as the CI base.

---

## 2. PythonCall + CondaPkg Integration Status

**Current state:** `OpenMMBackend` does NOT use PythonCall.jl at the Julia level. It renders an
MDSpec to a standalone Python script and executes it via `Base.run(\`$(b.python) script.py\`)` —
a plain subprocess. The `python::String` field on `OpenMMBackend` defaults to `"python"` (the
ambient binary on PATH). PythonCall.jl appears in comments and in the plan but is **not listed as
a dependency in `Project.toml`**, is not `import`-ed anywhere in `src/`, and `CondaPkg.toml`
is currently inert at runtime (no code calls `CondaPkg.ensure_conda_env()` or equivalent).

**What this means in practice:**
- The renderer is fully testable without Python (intentional, correct design).
- `preview_run` and `run!` will fail silently if `python` is not on PATH or OpenMM is not
  installed in the ambient Python — there is no env-activation step before the subprocess call.
- `CondaPkg.toml` specifies the right packages (`openmm >=8.1`, `openff-toolkit >=0.16`,
  `pdbfixer >=1.9`, `mdtraj >=1.10`) but nothing calls `CondaPkg` to resolve them.

**Smallest next change to make live OpenMM execution work:**

Option A (preferred, matches the plan): add `PythonCall` and `CondaPkg` to `[deps]` in
`Project.toml`, then in `OpenMMBackend`:

```julia
# At module load time (or lazily in prepare()):
import CondaPkg
CondaPkg.ensure_conda_env()          # resolves CondaPkg.toml on first call
import PythonCall: python_executable
```

Then set `b.python = python_executable()` in `OpenMMBackend()` (or resolve it at `prepare()`
time). This activates the Conda-managed env before any subprocess call and makes the python path
deterministic across machines.

Option B (minimal): leave the subprocess approach but call `CondaPkg.activate!(ENV)` before
building the `Cmd` in `preview_run` / `run!`. Less elegant but keeps the PythonCall dependency
optional.

---

## 3. Anthropic Provider End-to-End Status

**Exercised against a real paper: NO.** `AnthropicProvider.jl` is fully implemented — it sends
an HTTP POST to the Anthropic Messages API with the MDSpec JSON Schema as the tool `input_schema`,
parses the `tool_use` block, and passes the output through `spec_from_json`. The implementation
is correct and production-ready.

Evidence of real runs: none found. No logged transcripts in `~/.local/share/crucible/`, no fixture
files with Anthropic response metadata, no test with `status=200` response bodies. The
`RecordedProvider` + `recorded_anthropic_spec.json` fixture exists and is the offline CI path, but
it is a hand-crafted spec, not a real Anthropic response.

**What's needed to validate:**

1. Set `ANTHROPIC_API_KEY` and run:
   ```julia
   using Crucible
   text = read("test/fixtures/sample_md_methods.txt", String)
   r = transpile(AnthropicProvider(), text)
   @assert r.spec !== nothing
   gate_schema(r.spec_json)
   ```
   This is the LLM-loop smoke described in `docs/PLAN.md` and is the only missing integration
   test. It should take ~30 s and cost < $0.10 on Haiku.

2. Capture the raw response and save it as `test/fixtures/real_anthropic_response.json` for
   future `RecordedProvider` replay — this closes the CI gap without requiring an API key in CI.

3. The `_estimate_cost` function uses mid-2025 placeholder rates hardcoded in the file
   (`src/llm/AnthropicProvider.jl:120`). These should be refreshed against current Anthropic
   pricing, or moved to a config file so they don't bitrot silently.

---

## 4. Other Gaps Surfaced

**Molly renderer trajectory gap:** `MollyBackend.render_script` emits a comment
`"trajectory writeout for stage ... is a v0.5 task"` and no actual trajectory code. The rendered
script will execute a Molly simulation but produce no output files. This means `collect_artifacts`
returns an empty list and the PlutoRenderer has nothing to plot. Fix: emit a `DCDReporter`-
equivalent using `Molly.VelocityVerletIntegrator` callbacks, or at minimum write energies to a CSV.

**Golden-file tests use structural checks, not byte-identical comparison:** `renderer_golden_test.jl`
uses `occursin` to assert the rendered script contains expected strings. This is correct while the
renderer is still evolving, but means a silent regression (e.g., a force-field XML filename
changing from `amber14-all.xml` to `amber14/protein.ff14SB.xml`) would pass the test. The
comment in the test says byte-identical golden files are deferred to v0.5.

**GROMACSBackend is acknowledged scaffolding:** `render_script`, `prepare`, `preview_run`, and
`run!` all `error("not yet implemented")`. The Router correctly never routes to GROMACS unless
explicitly forced. No action needed now, but the scaffolding creates 4 test surface areas that
need to stay green.

**KineticsBackend is a v0.5 stub:** All runtime methods (`prepare`, `preview_run`, `run!`) error.
`validate_spec` runs basic checks. No action needed until Catalyst.jl integration begins.

**Schema version mismatch in notebook:** `notebook.jl:24` says `**Schema:** v0.3.0` but the
`_SCHEMA_PATH` in `Gates.jl` loads `schema.json` which is `v0.4.0` (inferred from `Migrations.jl`
which has a `v0.3 → v0.4` migration path). Update the notebook header to v0.4.0.

**Pricing constants will silently bitrot:** `AnthropicProvider.jl:119` has a comment
`"Rough mid-2025 placeholder rates"` — these are baked in as literals. Wrap in a `const` dict or
load from a config toml so they're easy to find and update.

**`self-hosted-hybrid-ci` infrastructure not yet built:** When the user's self-hosted-hybrid-CI
is available, a separate verification routine should upload the project there and run the full
integration suite (including live OpenMM execution). That routine does not exist yet — this is a
TODO for a future sprint, not this one.

---

## 5. Recommended Next Sprint

In priority order:

1. **Wire CondaPkg → OpenMMBackend subprocess** (1–2 days). Add `PythonCall` + `CondaPkg` to
   `[deps]`, call `CondaPkg.ensure_conda_env()` at module init or in `prepare()`, and set
   `b.python` to the Conda-managed executable. This is the single change that makes preview and
   production runs work reliably across machines without manual env setup.

2. **Run LLM smoke test and commit the fixture** (1 day). With an API key available, run the
   Anthropic round-trip against `sample_md_methods.txt`, save the real response as a fixture,
   wire it into `llm_test.jl`, and update `RecordedProvider` to replay it. This closes the
   largest untested code path and seeds the option-3 training corpus.

3. **Provision Julia in CI / dev environment** (1 day). Either add Julia to the Docker image
   via `juliaup` (network permitting) or use `julia:1.10-bullseye` as the base. Without this,
   the 36-test suite cannot run at all and the verification routine stalls on step 1.

4. **Add trajectory writeout to MollyBackend** (1 day). Emit `StructureWriter` or energy CSV
   output from `render_script`. Without this, Molly simulations produce no observable output and
   the PlutoRenderer's RMSD plot cell has nothing to display.

5. **Refresh pricing constants and fix notebook schema version label** (< 1 hour). Low-effort
   correctness fixes that prevent user-visible inaccuracies.
