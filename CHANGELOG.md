# Changelog

## Unreleased

### v1.5.1 — schema bump + Molly gating + Pluto refresh (2026-04-27)

Polish pass following v1.5.

- **Schema version bump 0.1.0 → 0.2.0**. `MDSpec.schema_version` and the
  `const` in `schema.json` both now read `"0.2.0"`. Real
  `_migrate_v0_1_to_v0_2` registered in `Migrations.jl`: fills nullable
  defaults for `system.source.ligand_smiles`, `system.solvent.membrane`,
  and `force_field.lipid` so old transcripts forward-compatibly upgrade.
  Existing fixtures migrated in place; default `target` of
  `migrate_spec_json` advanced to `"0.2.0"`.
- **MollyBackend rejects v1+ stages explicitly**. `validate_spec` now
  emits a per-stage error pointing at OpenMMBackend for `FEPStage` /
  `REMDStage` / `MetadynamicsStage`, and a separate error for
  `LipidBilayer` membrane systems. Replaces the generic "missing
  features" line for these cases.
- **Router auto-prefers OpenMM** for any spec demanding `:alchemy`,
  `:remd`, `:metadynamics`, `:membrane`, `:biased_sampling`,
  `:multi_replica`, or `:plumed` — even when the only thing Molly is
  missing is one of these.
- **Pluto notebook refresh**. Top-of-page banner lists v0.2.0 schema
  + 5 stage types + 5 source types + lipid bilayer note. Section 2
  (`## 2. Transpile`) gains a `provider_kind` selector for
  `recorded` / `anthropic` / `local` so the offline iteration path
  works without environment manipulation.
- **New test file**: `test/molly_gating_test.jl` — 6 testsets pinning
  the Molly rejection messages + the Router preference for OpenMM
  on v1+ features.
- **Tests**: 401/401 pass on Julia 1.10 (offline; +5 with
  `CRUCIBLE_RUN_OPENMM=1`).

### v1.5 — enhanced sampling + membranes (2026-04-26)

The remaining items from the v1+ deferred list, partly closed.

- **`REMDStage` (replica-exchange MD)**. Temperature ladder + exchange-attempt period; renderer emits real `openmmtools.multistate.ParallelTemperingSampler` code that writes `remd.nc` (multistate netcdf) for downstream WHAM/MBAR. Validation rule enforces strictly increasing T and warns on aggressive ratios that hurt acceptance.
- **`MetadynamicsStage` + `CollectiveVariable`** (distance / angle / dihedral / RMSD). Renderer emits an `openmm-plumed` `PlumedForce` block with auto-generated `METAD` line (well-tempered + bias-factor by default). Schema covers up to 8 CVs per stage. Validation rules check CV atom-group counts, RMSD reference presence, and the well-tempered/bias-factor coherence.
- **Membrane / lipid bilayer support**. `LipidBilayer` (composition + n_lipids + chol_mol_fraction) attaches to `SolventSpec.membrane`; `ForceFieldSpec.lipid` enum allowlist covers `:charmm36_lipid`, `:lipid21`, `:slipids`. The OpenMMBackend renderer auto-switches to `MonteCarloMembraneBarostat` (XYIsotropic, ZFree) for NPT stages in membrane systems — physically-correct semi-isotropic coupling, no user action needed. New `_rule_membrane_coherence` semantic rule.
- **Multi-GPU advisor candidates**: `A100x4`, `A100x8`, `L4x4` rows in `benchmarks.toml` with `default_gpu_count` + `multi_gpu_factor` fields. Advisor scales runtime by parallelism factor when the spec demands replicas (REMD), making multi-GPU instances cost-competitive only when actually utilized. New warning when `n_replicas > 1`.
- **`Stage` count → 5**: `MinimizeStage`, `DynamicsStage`, `FEPStage`, `REMDStage`, `MetadynamicsStage`. `OpenMMBackend.supported_features` now includes `:remd`, `:metadynamics`, `:plumed`, `:multi_replica`, `:membrane`.
- **Three new examples**: `examples/remd_protein_folding.jl` (8-replica T-REMD), `examples/membrane_protein.jl` (GPCR in POPC), and the existing `protein_ligand_fep.jl` is now joined by these for a complete sampling-method coverage.
- **Three new test files**: `remd_test.jl` (8 testsets), `metadynamics_test.jl` (7 testsets), `membrane_test.jl` (10 testsets). 386/386 tests pass on Julia 1.10.

### v1.0 — heavy lifts (2026-04-26)

The deferred v1 items shipped in one push.

- **Real `OpenFFParameterizer` (SMILES → AMBER topology)**. Subprocess implementation via `src/ligand/parameterize_openff.py`: SMILES → RDKit conformer → OpenFF Sage typing → AM1-BCC charges → Interchange → `ligand.parm7` / `ligand.rst7` / `ligand.pdb`. No PythonCall dep added — keeps the package light per the project preference. `parameterizer_available()` probes the configured python without exploding on the user.
- **`:smiles` SystemSource type**. Pure-ligand path. `OpenMMBackend.prepare()` invokes the parameterizer when `source.type == :smiles` and the renderer loads the AMBER files. The BYO-topology gate goes away for ligand-only systems.
- **`:protein_ligand` SystemSource type**. Combined protein + small-molecule path. PDBFixer fetches + repairs the protein, OpenFF parameterizes the ligand from SMILES, `SMIRNOFFTemplateGenerator` (openmm-forcefields) registers the ligand against the protein force field. All at script-runtime — no prepare-time round-trip needed. Requires `openff-toolkit + openmmforcefields` at execution.
- **`FEPStage` (alchemical free-energy)**. New stage type with `kind ∈ (:decouple, :annihilate)`, `lambda_windows::Vector{Float64}`, `target_selection`, `duration_per_window_ns`. Schema entry, JSON round-trip, semantic gates (lambda monotonic, range [0,1], NPT-pressure required). Renderer emits real `openmmtools.alchemy.AbsoluteAlchemicalFactory` code that runs each λ window and writes a `u_kln.csv` for downstream MBAR analysis. `:alchemy` is now in `OpenMMBackend.supported_features`.
- **`WebRenderer` real implementation + `crucible serve`**. HTTP.jl-based frontend (no Genie dep). Endpoints: `GET /`, `GET /health`, `POST /api/transpile|validate|render|advise|parameterize`. Single-page UI with paper paste / spec edit / backend choice / cloud advise — all server-rendered. CLI: `crucible serve --host --port`.
- **CLI: `parameterize` + `verify`**. `crucible parameterize <smiles> --out <dir> [--ff openff_sage_2_2_0]` runs the OpenFFParameterizer directly. `crucible verify <spec> [--backend X]` runs gates 1-3 + render in one shot, exits non-zero on failure.
- **Two new semantic rules**: `_rule_smiles_source_coherence` (SMILES sources need ligand_smiles + non-:user_supplied ligand FF + a 4-char pdb_id for protein_ligand), `_rule_fep_lambda_monotonic` (λ windows strictly increasing, bracketing [0,1], NPT requires pressure).
- **Examples**: `examples/from_smiles.jl` (ethanol-in-vacuum, end-to-end), `examples/protein_ligand_fep.jl` (1ubq + p-cresol decoupling FEP scaffolding).
- **Tests**: `test/smiles_test.jl` (12 assertions for IR + validation + render), `test/fep_test.jl` (8 assertions for round-trip + schema + render), `test/web_test.jl` (6 endpoints, free-port server boot/teardown). `parameterizer_test.jl` rewritten for the real subprocess implementation.
- **Schema**: SystemSource now allows `ligand_smiles` and the source `type` enum gains `smiles` + `protein_ligand`. Added `free_energy` kind to the protocol oneOf with full property list.

### v0.5 (2026-04-26)

- **Crucible CLI** (`bin/crucible`): 7 subcommands — `transpile`, `validate`, `render`, `advise`, `summarize`, `diff`, `walkthrough`. Pipeline usable from a shell without Pluto.
- **`MarkdownRenderer`**: GFM-rich rendering of `MDSpec`, `ValidationReport`, `SpecDiff` for CLI / PR descriptions / README.
- **`diff_specs(a, b)` + `crucible diff`**: structured per-field diff between two specs. The training signal for the option-3 fine-tune (LLM-emitted vs. user-corrected pairs).
- **`docs/IR.md`** auto-generated from `schema.json` via `tools/regenerate_docs.jl`.
- **`examples/lifecycle.jl`**: full option-3 flywheel demo (transpile → log → user-edit → diff → log → JSONL).
- **`tools/regenerate_fixtures.sh`**: drift check for the recorded LLM fixture against a live Anthropic call.
- **`tools/check.sh`**: pre-commit gate runner — `Pkg.test()` + IR docs drift + fixture drift.
- **NVE ensemble support** (VerletIntegrator) and **CHARMM36m** rendering coverage.
- **Schema-version migration framework** (`src/spec/Migrations.jl`) so future schema bumps preserve historical transcripts.
- **`KineticsSpec` + `KineticsBackend` stub**: proof the SimBackend abstraction extends past MD; v1+ wires Catalyst.jl in.
- **`SECURITY.md`** with the project's secrets-handling policy.
- **`docs/VERIFICATION_ROUTINE.md`** documenting what the 2-week verification routine should do.
- **Schema tightening**: NPT/NVE invariants enforced at Gate 1 (was Gate 2-only).
- **JSONL transcript export** for sharing the data flywheel across machines.
- **CHANGELOG / README / AGENTS.md / LICENSE** all polished.

### v0.4 / v1 partial (2026-04-26)

- **PDBFixer auto-build path** (v1 #1): `:pdb_fetch` source type now downloads a PDB by ID, fixes missing atoms/residues, adds hydrogens at pH 7, solvates with the requested water model, and saves the prepared system. Canonical-residue protein systems only — ligand systems still require BYO topology.
- **Real trajectory output**: `DCDReporter` per stage at the requested observable stride (was emitting comments).
- **Real observable computation**: post-run `mdtraj` block computes RMSD / RMSF / Rg from the trajectory and writes CSV files. Wrapped in `try/except` so the script still runs without `mdtraj` installed.
- **ArxivAdapter PDF download**: when `pdftotext` is on PATH, the adapter downloads the PDF and extracts the full body text (was abstract-only).
- **PDB column-alignment fix**: `test/fixtures/alanine_dipeptide.pdb` regenerated to strict PDB v3 column rules; OpenMM now loads it cleanly.
- **OpenMMBackend renderer**: relaxed topology requirement — PDB-only systems no longer demand a separate `.prmtop`.

### v0.3 (2026-04-26)

- `.woodpecker.yml` matrix on Julia 1.10 + 1.11; consolidated to Woodpecker (GHA + Forgejo Actions removed)
- Live OpenMM smoke in CI via a separate pipeline step that installs OpenMM in a venv and runs `Pkg.test()` with `CRUCIBLE_RUN_OPENMM=1`
- `Manifest.toml` committed for reproducible builds
- `poppler-utils` installed in CI, real `PDFAdapter` test
- `examples/walkthrough.jl` end-to-end demo using `RecordedProvider` (no API key needed)

### v0.2 (2026-04-26)

- `TranscriptStore` (DuckDB-backed append-only log) — Phase A of the option-3 fine-tune flywheel
- `RecordedProvider` for deterministic LLM tests without consuming API tokens
- Live `AnthropicProvider` smoke gated on `CRUCIBLE_RUN_ANTHROPIC=1` + `ANTHROPIC_API_KEY`
- Pluto Gate 5: `@bind run_button` gating prevents accidental production runs on spec edits
- `PlutoUI`, `HypertextLiteral`, `DuckDB`, `DBInterface`, `Dates` added to `Project.toml`

### v0.1 (2026-04-26)

- Renderer correctness: integers/floats are now text-formatted (was emitting raw bytes via `write(io, ::Number)`)
- OpenMM restraints: real `CustomExternalForce` honoring selection (heavy_atoms / backbone / ca) and harmonic k; auto-removed at end of stage
- Live `run!` for both backends via subprocess (no PythonCall dep added — keeps the package light)
- Validation Gate 4 (`gate_preview`): rendered scripts honor `CRUCIBLE_PREVIEW_STEPS` env var, every dynamics stage wrapped in `_cap()`; preview run parses log for NaN/Infinity/blowup
- Molly's `supported_features` now advertises `:constraints` so the Router dispatches implicit-solvent NVT specs to Molly
- Alanine-dipeptide test fixture + integration testset (live OpenMM smoke gated on `CRUCIBLE_RUN_OPENMM=1`)
- CI: consolidated to Woodpecker only (`.woodpecker.yml` matrix on Julia 1.10 + 1.11). GitHub Actions and Forgejo Actions removed
- 60 tests passing on both Julia 1.10 and 1.11

### v0 (2026-04-25)

Initial scaffold.

- MDSpec IR + JSON Schema + Unitful unit handling
- `SimBackend` abstract interface with `MollyBackend` and `OpenMMBackend` (renderer-only — emit scripts; live execution is the next milestone)
- Backend `Router` (defaults to OpenMM for explicit-solvent/ligand systems)
- Validation gates 1–3 (schema, semantic rules, backend loadability)
- Anthropic Claude provider with tool-use binding the MDSpec schema as `input_schema`
- `LocalProvider` stub for the option-3 fine-tuned chem model roadmap
- Input adapters: PDF (poppler-backed), arXiv, bioRxiv, raw notes
- Output renderers: Pluto inline HTML, standalone Pluto notebook export, web stub
- Cloud sizing advisor (GCP + AWS) seeded from OpenMM benchmarks
- Pluto.jl notebook UI (`src/ui/notebook.jl`)
- Test suite covering schema, validator, renderers, router, and advisor
- GitHub Actions CI (`ubuntu-latest` + `self-hosted-hybrid-ci` runner gated on commit tag)
- Hand-construction example at `examples/from_methods.jl`

### Not in v0 (deferred)

- SMILES → ligand force-field parameters (BYO topology required)
- Free-energy methods, enhanced sampling, QM/MM, membranes
- Live execution via PythonCall + CondaPkg (next milestone)
- Multi-GPU / multi-replica orchestration
- Local / fine-tuned LLM providers (interface stubbed)
