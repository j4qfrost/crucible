# Contributing to Crucible

Practical guide for human contributors. (`AGENTS.md` is the equivalent
for AI coding assistants — same project rules, denser format. Read
both if you're unsure.)

## What Crucible is

A Julia drug-discovery simulation pipeline. You feed it a paper, it
extracts the molecular-dynamics protocol via an LLM into a structured
intermediate representation (`MDSpec`), and the package renders that IR
into a runnable OpenMM (or Molly) script with provenance, validation,
and a cloud-sizing recommendation.

Read [`docs/PLAN.md`](docs/PLAN.md) first — it has the architecture +
roadmap. The five-gate validation pipeline (schema → semantic →
loadability → preview → user-confirm) and the `MDSpec` IR are the
keystones; everything else is downstream.

## Setting up

You don't need Julia installed locally — the project ships a
docker-based test loop:

```bash
docker run --rm \
  -v "$PWD":/work -v /tmp/crucible-depot:/julia-depot \
  -w /work -e JULIA_DEPOT_PATH=/julia-depot julia:1.10 \
  bash -c 'julia --project -e "using Pkg; Pkg.test()"'
```

The cached `/tmp/crucible-depot` makes repeat runs ~10× faster. If you
do install Julia locally:

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'
julia --project -e 'using Pkg; Pkg.test()'
```

For the Pluto notebook UI:

```bash
julia --project -e 'using Pluto; Pluto.run(notebook="src/ui/notebook.jl")'
```

For optional Python deps (OpenMM execution, OpenFF parameterization):

```bash
pip install openmm pdbfixer mdtraj openff-toolkit openff-interchange rdkit \
            openmmtools openmmforcefields
# AMD/ROCm: also
conda install -c conda-forge openmm-hip
```

`crucible doctor` will tell you what's installed and what's missing.

## Hard rules (the same five from AGENTS.md)

1. **The LLM never invents force-field parameters.** All FF symbols
   come from the allowlists in `src/spec/MDSpec.jl`. Adding a new FF
   means updating the allowlist + the corresponding XML mapping in
   `OpenMMBackend._emit_forcefield`.
2. **The IR (`MDSpec`) is the contract.** Schema changes are version
   bumps. Bump `schema_version` in both `MDSpec.jl` and `schema.json`,
   register a migration in `Migrations.jl`, and add a CHANGELOG entry.
3. **Renderers are the only code that converts units.** The IR carries
   units in field names (`temperature_K`, `dt_fs`, etc.). The LLM is
   forbidden from doing unit math; the renderer does it.
4. **BYO-topology gate is scoped to `:user_supplied` only.** SMILES
   sources (`:smiles`, `:protein_ligand`) parameterize via
   `OpenFFParameterizer`. Hard rule #1 still applies — parameterization
   is OpenFF-driven, never LLM-invented.
5. **Validation gates are sequential.** Gate N+1 only runs after Gate N
   passes. Don't add code paths that bypass this.

## Common workflows

### Adding a new stage type (sampling method)

1. Subtype `Stage` in `src/spec/MDSpec.jl`. Add `stage_to_dict` +
   `stage_from_dict` clauses.
2. Add the schema entry under `protocol.items.oneOf` in `schema.json`.
3. Add a semantic rule in `src/validation/Gates.jl` if there are
   cross-field invariants the schema can't express (almost always
   yes).
4. Add a renderer block in `src/backends/OpenMMBackend.jl`'s
   `_emit_protocol` (and Molly if applicable).
5. Update `required_features(spec)` so the Router dispatches correctly.
6. Add MarkdownRenderer + PlutoRenderer handlers (`_stage_label`,
   `_stage_details`, `_stage_summary`).
7. Update the LLM prompt in `src/llm/Provider.jl` so the LLM knows the
   new kind exists.
8. Test file: round-trip + Gate 1 + Gate 2 + renderer-output.

The five-stage path (Minimize / Dynamics / FEP / REMD / Metadynamics)
all follow this pattern; pick whichever is closest to your new stage
and copy.

### Adding a new force-field family

1. Add the symbol(s) to the matching allowlist (`PROTEIN_FF_ALLOWLIST`,
   `WATER_MODEL_ALLOWLIST`, `LIGAND_FF_ALLOWLIST`, `LIPID_FF_ALLOWLIST`,
   `CG_PROTEIN_FF`).
2. Add to the schema enum.
3. Add the matching XML file mapping in `OpenMMBackend._emit_forcefield`.
4. Add a coherence rule if needed (e.g. "Martini protein FF + atomistic
   water is incoherent").
5. Test that the schema accepts it + the renderer emits the right XML
   files.

### Adding a new ligand parameterizer

1. Subtype `LigandParameterizer` in `src/ligand/`.
2. Implement `parameterize(p, smiles, output_dir) -> ParameterizedLigand`.
3. Add `parameterizer_available(p) -> Bool` so tests + CLI skip cleanly
   when the optional dep isn't installed.
4. Update `OpenMMBackend.prepare()` if the new parameterizer needs a
   different prepare-time hook.

### Schema bumps

1. Bump `schema_version` constant in `MDSpec.jl` *and* the `const` in
   `schema.json` to match.
2. Register a migration: `register_migration!("0.x.0", "0.y.0", f)`
   where `f(::Dict)::Dict` translates the old shape forward. Identity
   migrations are fine for additive changes (e.g. new optional field).
3. Update `migrate_spec_json` default `target` to the new version.
4. Migrate test fixtures: `julia --project -e 'using Crucible;
   for f in [...]; write(f, migrate_spec_json(read(f, String))); end'`.
5. Update `schema_version` assertions in `spec_schema_test.jl`,
   `cli_extras_test.jl`, `snapshot_test.jl` (anywhere a literal
   `"0.x.0"` appears).
6. CHANGELOG entry describing what's new in the schema.

## Testing conventions

- **Every new code path needs a test.** The bar: a malicious edit to
  the new code should break a test.
- Live integration tests are gated behind `CRUCIBLE_RUN_*` env vars.
  When the env isn't set, the test should be a placeholder (`@test
  true`) so the testset isn't empty.
- Use `RecordedProvider` for LLM tests, not `AnthropicProvider`. The
  recorded fixture lives at `test/fixtures/recorded_anthropic_spec.json`
  and is regenerated via `tools/regenerate_fixtures.sh` (needs
  `ANTHROPIC_API_KEY`).
- Renderer tests assert structural content via `occursin` — don't aim
  for byte-identical golden files until the schema version stabilizes.
- Web tests hit the `_router` handler directly with a mock
  `HTTP.Request`. Don't bind a real socket in tests.

## CLI conventions

- New subcommands go in `src/cli/CLI.jl`; pattern is `cmd_<name>`.
- Add to `HELP_TEXT` so the dispatch test sees it.
- The dispatch coverage test loops over `HELP_TEXT` and asserts
  `rc != 2` (unknown). Subcommands that intentionally block (e.g.
  `serve`) get added to the `blocking` skip-set.
- Errors throw `ErrorException`; the dispatcher catches and returns
  `rc=1`. Don't `exit(...)` from inside a subcommand.
- Long-running output should accept `--format text|json` (and
  `markdown` where it makes sense).

## Dual CI

- **GitHub Actions** (`.github/workflows/ci.yml`): Julia 1.10 + 1.11
  matrix on `ubuntu-latest`. The public-facing pipeline.
- **Woodpecker** (`.woodpecker.yml`): same matrix on snowman. Runs
  even if GitHub Actions billing clamps.
- **GPU smoke** (`.github/workflows/gpu-smoke.yml`): self-hosted
  runner on snowman, gated on the `gpu-smoke` PR label. Live OpenMM
  on the actual GPU.

Keep all three in sync when you change build commands.

## Commit + push

- Conventional-ish messages with milestone tags: `v0.1`, `v1.0`, etc.
- Multi-paragraph body explaining *why*, not what (the diff shows
  what).
- Co-authorship footer when an AI assistant contributed:
  `Co-Authored-By: Claude Opus 4.7 (1M context)
  <noreply@anthropic.com>`.
- The synthetic `all` remote pushes to GitHub + Forgejo when both
  credentials are loaded. `git push all main`. If Forgejo is offline,
  push to `origin` only — `tools/sync_remotes.sh` re-wires when the
  Forgejo token comes back.

## Where to ask questions

- Architecture: `docs/PLAN.md`
- Schema reference: `docs/IR.md` (auto-generated)
- Long-form thinking: `musings/`
- AI agent guidance: `AGENTS.md`
- Verification routine details: `docs/VERIFICATION_ROUTINE.md`

## Not currently accepted

- New backends without an existing runtime (no "scaffolding" PRs for
  speculative platforms — the constph + Martini precedent was
  warranted; speculative ones aren't).
- Pluto notebook re-architecture without a clear migration story.
- LLM-side changes that bypass the schema (the IR is the contract).
- `Manifest.toml` edits without a corresponding dep-set diff in the
  PR description (the manifest is committed but volatile).
