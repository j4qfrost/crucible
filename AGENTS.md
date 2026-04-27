# AGENTS.md — guidance for Claude / contributors editing this repo

This file is read by Claude Code (and other AI agents) before making
changes. Human contributors should also read it.

## Hard rules (non-negotiable)

1. **The LLM never invents force-field parameters.** Every FF symbol
   must come from the allowlists in `src/spec/MDSpec.jl`
   (`PROTEIN_FF_ALLOWLIST`, `WATER_MODEL_ALLOWLIST`, `LIGAND_FF_ALLOWLIST`).
   When extending an allowlist, also add the corresponding XML mapping
   in `src/backends/OpenMMBackend.jl`'s `_emit_forcefield`.
2. **The IR (`MDSpec`) is the contract.** Schema changes are a version
   bump. Bump `schema_version` in `MDSpec.jl` and `schema.json` together;
   add a migration note to `CHANGELOG.md`. Renderers must continue to
   produce byte-identical output for the previous schema version until
   the next major release.
3. **Renderers are the only code that converts units.** The IR carries
   units in field names (`temperature_K`, `dt_fs`, `duration_ns`). LLM
   prompts are forbidden from doing arithmetic on units; the renderer
   does it.
4. **BYO-topology gate is now scoped to `:user_supplied` source only.**
   Never let `has_ligand=true` + `ligand_ff=user_supplied` +
   `source.type=:user_supplied` proceed without a topology path.
   SMILES paths (`:smiles`, `:protein_ligand`) bypass this — they
   parameterize via `OpenFFParameterizer` (subprocess to openff-toolkit
   + Interchange) at prepare-time or script-runtime. Hard rule #1 still
   holds: parameterization is OpenFF-driven, never LLM-invented.
5. **Validation gates are sequential.** Gate N+1 only runs if Gate N
   passes. Don't add backends or features that bypass this.

## Local development pattern

Julia is not assumed to be installed on the host. The reproducible
pattern uses Docker:

```bash
docker run --rm \
  -v "$PWD":/work -v /tmp/crucible-depot:/julia-depot \
  -w /work -e JULIA_DEPOT_PATH=/julia-depot julia:1.10 \
  bash -c 'julia --project -e "using Pkg; Pkg.test()"'
```

The cached `/tmp/crucible-depot` makes repeat runs ~10× faster. For the
full live OpenMM + PDBFixer + mdtraj integration, set
`CRUCIBLE_RUN_OPENMM=1` and ensure the container has `openmm`,
`pdbfixer`, `mdtraj` installed (the `.woodpecker.yml` `openmm-smoke`
step shows the recipe).

## Testing conventions

- All new code must come with at least one test. The bar: a malicious
  edit to the new code should break a test.
- Live integration tests are gated behind `CRUCIBLE_RUN_*` env vars
  and contain an early-return placeholder so the testset is non-empty
  in offline mode.
- The `RecordedProvider` is the default LLM in tests; only the live
  Anthropic smoke (`CRUCIBLE_RUN_ANTHROPIC=1`) hits the real API.
- Renderer tests assert structural content (`occursin`); don't aim
  for byte-identical golden files until the schema version stabilizes.

## Adding a new backend

1. Subtype `SimBackend` in a new file under `src/backends/`.
2. Implement the full interface from `src/backends/SimBackend.jl`:
   `backend_name`, `supported_features`, `validate_spec`,
   `estimate_resources`, `prepare`, `preview_run`, `run!`,
   `collect_artifacts`.
3. Update `src/backends/Router.jl` so dispatch logic considers it.
4. Add a renderer test asserting the emitted script contains the
   expected backend-specific lines for a known-good spec.
5. Avoid adding it as a default Julia dep — gate optional deps behind
   user opt-in (`Pkg.add(...)`) per the project's "OpenMM is optional"
   stance.

## Adding a new LLM provider

1. Subtype `LLMProvider` in `src/llm/`.
2. Implement `transpile(provider, paper_text; kwargs...)`. Return a
   `TranspileResult`; never throw on API/network errors — record them
   in `raw_response` with `spec=nothing`.
3. The provider should hit the existing JSON Schema as `input_schema`
   (or equivalent structured-output mechanism) so the validator is
   the single source of truth.
4. Don't auto-log to the transcript store from inside `transpile` —
   logging is the caller's responsibility (see Pluto notebook + CLI).

## Adding a new ligand parameterizer

1. Subtype `LigandParameterizer` in `src/ligand/`.
2. Implement `parameterize(p, smiles, output_dir) -> ParameterizedLigand`.
   Return paths to AMBER `.parm7` / `.rst7` (or equivalent OpenMM-loadable
   pair). Never invent FF parameters — fail loudly if the toolkit can't
   type the molecule.
3. Add a `parameterizer_available(p) -> Bool` probe so tests + CLI can
   skip cleanly when the optional dep isn't installed.
4. The OpenMMBackend's `prepare()` calls `parameterize()` only for
   `source.type == :smiles`. For `:protein_ligand`, parameterization
   happens at script-runtime via `SMIRNOFFTemplateGenerator` instead.

## Adding a new stage type

1. Subtype `Stage` in `src/spec/MDSpec.jl`.
2. Add `stage_to_dict(::NewStage)` and a clause in `stage_from_dict` for
   the new `kind` string.
3. Add the schema entry under `protocol.items.oneOf` in `schema.json`.
4. Add a semantic rule in `src/validation/Gates.jl` if there are
   cross-field invariants the schema can't express.
5. Add a renderer block in `src/backends/OpenMMBackend.jl`'s
   `_emit_protocol` and (if applicable) `MollyBackend.jl`.
6. Update `required_features(spec)` to declare any new feature your
   stage needs (`:alchemy` for FEP, etc.) so the Router can dispatch.

## Adding a new input adapter

1. Subtype `InputAdapter` in `src/adapters/`.
2. Implement `ingest(adapter, source) -> PaperRepr`. Network-tolerant:
   transient failures should warn and return a partial `PaperRepr`,
   not throw.
3. When `pdftotext` is on PATH, prefer to populate `body_text` with
   full extracted text (see `ArxivAdapter` and `BioRxivAdapter` for
   the pattern).

## CI

- Woodpecker on snowman is the canonical CI. `.woodpecker.yml` matrix
  on Julia 1.10 + 1.11. The `openmm-smoke` step installs
  `openmm + pdbfixer + mdtraj` and runs the live integration tests.
- Don't add steps that reference Woodpecker secrets via `from_secret`
  unless the secret has been configured in the Woodpecker UI; the
  YAML is rejected at parse time when a referenced secret is missing.

## Commit style

Conventional-ish, with milestone tags (`v0.1`, `v0.2`, `v1`):

```
<scope>: <one-line summary>

Multi-paragraph body explaining WHY (not what — diff shows that).

Tests: <pass count>/<total>.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Use `git push all main` to fan out to GitHub + Forgejo (when the
Forgejo token is loaded). GitHub-only is fine when Forgejo is offline.

## Updating this file

When adding a new architectural pattern or a new "always do X" rule,
update this file in the same commit so the next agent doesn't relearn
the lesson.
