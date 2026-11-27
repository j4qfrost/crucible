# Power-user onboarding

Audience: someone who already knows what Crucible is, has run a
template through the CLI or notebook at least once, and now wants to
**extend** it — add a stage type, add a lint rule, ship a custom
template, drive the bindings from a different language, or integrate
Crucible into a CI pipeline.

If you haven't run anything yet, start with `README.md` and
`docs/HOW_TO_READ.md`. If you want strategy/scaling, read
`musings/scaling_modes.md` and `docs/ADOPTION_PLAN.md`. This file
is the contributor handbook for the people doing the work.

## Conventions you'll see everywhere

- **Hard rule (AGENTS.md §1):** the LLM never invents force-field
  parameters. The IR carries source attribution; the renderer is the
  only thing that converts units. Every code path has to honor this.
- **Hard rule (AGENTS.md §2):** the IR is the contract. Renderers are
  pure functions of the IR. If you want a new feature, the question is
  always "what does the IR look like?" first.
- **Hard rule (AGENTS.md §3):** renderers convert units. Nothing
  upstream of the renderer touches a unit.
- **Hard rule (AGENTS.md §4):** BYO-topology gate — auto-parameterizing
  ligands from SMILES requires `force_field.ligand` to be a real
  parameterizer, not `:user_supplied`.
- **Hard rule (AGENTS.md §5):** gates run sequentially. Don't skip,
  don't reorder.

When you propose a change, the reviewer will check it against these
rules first.

---

## Adding a stage type

A new stage is the highest-friction extension because it touches every
layer. Walk through this checklist if you're adding `:my_new_stage`:

1. **IR (`src/spec/MDSpec.jl`)**
   - Add `MyNewStage <: Stage` struct.
   - Add `stage_to_dict(s::MyNewStage)` and a branch in `stage_from_dict`.
   - If it adds new feature requirements, extend `required_features(spec)`.
2. **Schema (`src/spec/schema.json`)**
   - Add the discriminator `"kind": "my_new_stage"` to `protocol[].oneOf`.
   - Bump `schema_version` (see "Bumping the schema" below).
3. **Migrations (`src/spec/Migrations.jl`)**
   - Register the new bump as `register_migration!(prev, new, ...)`.
4. **Validation (`src/validation/Gates.jl`)**
   - Add a `_rule_my_new_stage_*` function for any field-level
     invariant the schema can't express.
   - Register it in the `gate_semantic` rule list.
5. **Coverage (`src/spec/Coverage.jl`)**
   - Add the new stage's numeric paths to `_enumerate_provenance_keys`.
6. **Renderers (`src/backends/{OpenMMBackend,MollyBackend}.jl`)**
   - Add `_emit_my_new_stage(io, spec, stage)`.
   - The OpenMM emit must produce a runnable Python script; Molly the
     equivalent in-process Julia code.
7. **Python port** — the Python side mirrors all of (1)-(5):
   - Add `MyNewStage` to `python/crucible/spec.py` with pydantic types.
   - Update the discriminated `Stage` union.
   - Port the new semantic rule(s) to `python/crucible/validate.py`.
   - Update `_enumerate_provenance_keys` in `python/crucible/coverage.py`.
   - Update the migration in `python/crucible/migrate.py`.
8. **Templates (`src/spec/Templates.jl` + `python/crucible/templates.py`)**
   - Add at least one demo template that exercises the new stage.
9. **Tests** — both sides:
   - `test/spec_schema_test.jl`: round-trip a sample.
   - `test/validation_gates_test.jl`: assert each new rule fires.
   - `python/tests/test_spec.py` + `test_validate.py`: parallel coverage.

The Python and Julia ports must agree — every cross-language test in
`test/cross_language_consistency_test.jl` re-runs after a stage
change.

---

## Adding a lint rule

Less invasive than a stage type — pure advisory layer. Single PR:

1. Add a `_rule_<your_name>` to `src/spec/Coverage.jl` inside the `lint`
   function. Severity is `:advisory` (suggestion), `:warn` (probable
   issue), or `:info` (FYI). Lint never blocks; if it should block,
   it's a Gate 2 rule, not a lint rule.
2. Mirror it in `python/crucible/coverage.py`.
3. Add a test on each side that constructs a triggering spec and
   asserts the rule fires.
4. Document it in the `lint(spec) -> LintReport` docstring on both
   sides.

Trade-off you'll be asked about: "is this advisory or block?"
A good rule of thumb — if a senior comp-chemist would write a paper
that violates it, it's lint. If they wouldn't, it's Gate 2.

---

## Adding a template

Lowest friction. Single-file change on each side:

```julia
# src/spec/Templates.jl
function _my_template()
    sys = SystemSpec(...)
    ff  = ForceFieldSpec(...)
    proto = Stage[...]
    obs = Observable[...]
    spec = MDSpec(system=sys, force_field=ff, protocol=proto,
                  observables=obs, notes="...")
    _enrich_provenance!(spec, "my_template")
end

# Register at the bottom of __init_templates__
register_template!(:my_template, _my_template)
```

```python
# python/crucible/templates.py — same shape
def _my_template() -> MDSpec:
    spec = MDSpec(...)
    return _enrich_provenance(spec, "my_template")

register("my_template", _my_template)
```

Templates must:

- Pass Gates 1+2 unmodified (`run_validation(spec)` returns ok).
- Have a coverage score ≥ 0.6 (the `_enrich_provenance` helper handles
  this if you use realistic field values).
- Carry a `notes` field that explains the use case.
- Add `warnings` for the things a user is likely to misuse.

Add a parametrized test on each side that includes the new name in
the `EXPECTED` set.

---

## Bumping the schema

Schema version is a coordinated change across both languages. Order:

1. **Decide the bump kind.**
   - **Patch** (e.g. `0.3.0 → 0.3.1`): purely additive, identity
     migration. New optional field, new enum value.
   - **Minor** (`0.3.0 → 0.4.0`): backward-compatible reshape;
     migration is a real transform.
   - **Major** (`0.3.0 → 1.0.0`): breaking change, plan transcript
     re-curation.
2. **Edit `src/spec/schema.json`.** Bump `$id` and the `schema_version`
   const. Add or modify properties.
3. **Mirror in `python/crucible/spec.py`.** Bump `SCHEMA_VERSION`. Update
   pydantic `Literal[…]` enums.
4. **Register migrations on both sides.**
   - Julia: `register_migration!("0.3.0", "0.4.0", _migrate_v0_3_to_v0_4)`
   - Python: `register_migration("0.3.0", "0.4.0", _migrate_v0_3_to_v0_4)`
5. **Run all tests on both sides.** A schema bump is a "did everything
   round-trip cleanly" question.
6. **Bump `python/pyproject.toml` version** to match.
7. **CHANGELOG entry** that calls out the schema bump explicitly so
   transcript-collectors know to migrate.

The migration framework guarantees the option-3 fine-tune flywheel
(`docs/ADOPTION_PLAN.md` Phase 4) keeps working: historical transcripts
collected pre-bump still load post-bump.

---

## Adding a CLI subcommand

The Julia CLI lives in `src/cli/CLI.jl`. The 30 existing subcommands
all follow the same pattern:

```julia
function cmd_my_subcommand(args::Vector{String})
    # 1. Parse args (use Crucible._argparse helpers).
    # 2. Read input — either stdin (JSON) or --file path.
    # 3. Do the work.
    # 4. Emit either text (default) or JSON (--format json).
    # 5. Return the exit code.
end
```

Register it in `_DISPATCH` near the top of `CLI.jl`.

If the subcommand has a sensible Python wrapper, add one to
`python/crucible/cli_bridge.py` that shells out via `_run`. Keep the
Python signature pythonic; the bridge handles JSON serialization.

---

## CI integration (the patterns we've shipped)

### GitHub Actions

```yaml
name: crucible-validate
on: [push, pull_request]
jobs:
  validate-specs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install crucible
      - name: Validate all checked-in specs
        run: |
          for spec in specs/*.json; do
            python -m crucible validate "$spec"
          done
```

This is the "Phase 0 of integration" path: spec validation only,
no Julia, no GPU. The Python bindings exist for exactly this
scenario.

### Forgejo Actions (the self-hosted setup)

The repo's own `.forgejo/workflows/ci.yml` runs the full Julia test
suite including cross-language consistency. The core of it, for any
fork:

```yaml
jobs:
  test:
    runs-on: docker
    container:
      image: julia:1.10
    steps:
      - uses: actions/checkout@v4
      - run: julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

### Pre-commit hook

Project-level `.git/hooks/pre-commit` (not committed; install per dev):

```bash
#!/usr/bin/env bash
set -e
# Validate any *.json specs that this commit touches.
git diff --cached --name-only --diff-filter=ACM | grep -E '\.json$' | while read f; do
    if jq -e 'has("schema_version")' "$f" >/dev/null 2>&1; then
        python -m crucible validate "$f" || {
            echo "spec $f failed validation"
            exit 1
        }
    fi
done
```

---

## Custom LLM provider

The Anthropic provider (`src/llm/AnthropicProvider.jl`) is the
reference implementation. To add another:

1. Subtype `LLMProvider` in `src/llm/Provider.jl`.
2. Implement `transpile(provider, paper_text) -> TranspileResult`.
3. Bind the JSON schema as the structured-output format on whatever
   API you're calling. The contract is: "return MDSpec JSON or fail
   loudly."
4. Register in `LLM_PROVIDERS` so the CLI's `--provider` flag picks
   it up.

A `LocalProvider` (vLLM / llama.cpp) stub already exists; this is the
slot Phase 4 fine-tunes drop into.

---

## Driving Crucible from Python

Once `pip install crucible`:

```python
import crucible

# Pure Python — no Julia required.
spec = crucible.templates.init("kinase_inhibitor_fep")
spec.system.source.ligand_smiles = "Cc1cnc(N)nc1"  # your analog

# Mutate in pydantic style.
spec = spec.model_copy(update={
    "notes": "screening, batch 2026-Q2"
})

# Gates 1+2.
report = crucible.validate(spec)
if not report.ok:
    raise SystemExit(report.errors)

# Heavy ops shell out to Julia.
script = crucible.render(spec, "openmm")
result = crucible.run(spec, workdir="runs/2026Q2/01",
                      seed=42, precision="mixed",
                      checkpoint_period_ps=100.0)
events = crucible.events("runs/2026Q2/01")
```

The Python wrapper finds the Julia binary in this order:

1. `$CRUCIBLE_BIN`
2. `bin/crucible` next to the package (dev tree)
3. `crucible` on `$PATH`

Failure mode: `CrucibleNotInstalled` is raised with the remediation
hint pointing at `julia --project -e 'using Pkg; Pkg.instantiate()'`.

---

## Driving Crucible from another language

The IR-as-contract design means any language that speaks JSON can be a
producer or consumer:

| You want…                          | You need…                                                          |
|-------------------------------------|--------------------------------------------------------------------|
| Rust producer                       | Validate against `src/spec/schema.json`. Use `serde_json` + a JSON Schema validator like `jsonschema`. |
| Go consumer                         | `gojsonschema` against the file; emit specs by JSON-marshaling structs that match the schema. |
| TypeScript frontend                 | `ajv` against the file. Generate TS types via `quicktype` from the schema. |
| Custom backend (e.g. Tinker, GROMACS) | Read `MDSpec` JSON; emit your engine's input deck. The IR has all the protocol fields you need. |

There is no in-process integration. There is no extension API. There
is JSON in, scripts/artifacts out. That's deliberate
(`musings/why_subprocess_over_pythoncall.md`). The cost is lost
ergonomics; the benefit is "Crucible never breaks your tool."

---

## When something is hard, ask first: what does the IR look like?

The most common source of bad PRs is implementing a feature in the
renderer and treating the IR as an afterthought. The IR is the
contract; if a feature can't be expressed in the IR cleanly, it
shouldn't be in Crucible at all (or the IR needs a schema bump).

If you're stuck:

1. Open an issue tagged `ir-question`.
2. Sketch the IR shape first; tag the maintainer.
3. Wait for sign-off before touching renderers, gates, or templates.

This avoids the "PR rewrites itself three times" pattern, which has
happened enough that the convention is now load-bearing.
