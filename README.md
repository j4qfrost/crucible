# crucible

[![CI (GitHub Actions)](https://github.com/j4qfrost/crucible/actions/workflows/ci.yml/badge.svg)](https://github.com/j4qfrost/crucible/actions/workflows/ci.yml)
[![CI (Woodpecker)](https://snowman.tailddc637.ts.net/api/badges/j4qfrost/crucible/status.svg)](https://snowman.tailddc637.ts.net/repos/j4qfrost/crucible)
![Julia 1.10+ / 1.11](https://img.shields.io/badge/julia-1.10%20%7C%201.11-9558B2)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

A Julia drug-discovery simulation app with an LLM paper-transpiler.

Drop in a paper (PDF, arXiv ID, bioRxiv DOI, or pasted notes), and an LLM
extracts the molecular-dynamics protocol into a structured intermediate
representation (`MDSpec`). A Julia compiler then renders that IR into a
runnable Molly.jl or OpenMM simulation, validated end-to-end before any GPU
time is spent.

The user shell is a Pluto.jl notebook.

## Status

v1.5 (active development). See `docs/PLAN.md` for the full design and roadmap.

| Component        | Count | Items                                                |
|------------------|-------|------------------------------------------------------|
| Tests            | 386   | offline; +5 with `CRUCIBLE_RUN_OPENMM=1`             |
| Backends         | 3+1   | `MollyBackend`, `OpenMMBackend`, `KineticsBackend` (stub) |
| LLM providers    | 3     | `AnthropicProvider`, `RecordedProvider`, `LocalProvider` (real, OpenAI-compat) |
| Input adapters   | 4     | PDF, arXiv, bioRxiv, raw notes (PDFs auto-extracted via `pdftotext`) |
| Output renderers | 4     | `PlutoRenderer`, `MarkdownRenderer`, `NotebookRenderer`, `WebRenderer` (real HTTP) |
| CLI subcommands  | 11    | `transpile`, `validate`, `render`, `advise`, `summarize`, `diff`, `walkthrough`, `info`, `parameterize`, `verify`, `serve` |
| Source types     | 5     | `:user_supplied`, `:pdb_id`, `:pdb_fetch`, `:smiles`, `:protein_ligand` |
| Stage types      | 5     | `MinimizeStage`, `DynamicsStage`, `FEPStage`, `REMDStage`, `MetadynamicsStage` |
| Solvent extras   | —     | `LipidBilayer` for membrane systems (`:POPC`, `:POPE`, `:DPPC`, `:mixed_POPC_chol`) |
| Lipid FFs        | 3     | `:charmm36_lipid`, `:lipid21`, `:slipids` (auto MonteCarloMembraneBarostat) |
| Validation gates | 5     | schema, semantic, loadability, preview, user-confirm |
| Cloud GPUs       | 8     | T4, L4, A10G, A100, H100, V100 + multi-GPU (A100x4/8, L4x4) for REMD |
| Examples         | 9     | `walkthrough.jl`, `walkthrough_notebook.jl`, `lifecycle.jl`, `from_methods.jl`, `from_smiles.jl`, `protein_ligand_fep.jl`, `remd_protein_folding.jl`, `membrane_protein.jl`, `smoke_alanine_dipeptide.sh` |
| Tools            | 4     | `check.sh`, `regenerate_docs.jl`, `regenerate_fixtures.sh`, `sync_remotes.sh` |

### What works (v0–v0.4)

- `MDSpec` IR + JSON Schema (the LLM contract)
- Two `SimBackend` implementations:
  - `MollyBackend` — native Julia, sweet spot is CG / implicit / small / autodiff
  - `OpenMMBackend` — subprocess-driven OpenMM, the workhorse for solvated
    protein–ligand systems. Supports user-supplied topology, PDB-only
    systems, and `:pdb_fetch` (PDBFixer auto-build for canonical-residue
    protein systems)
- A `Router` that picks a backend based on spec features
- Five validation gates: schema, semantic rules, backend loadability,
  preview run (`CRUCIBLE_PREVIEW_STEPS`), and Pluto user-confirmation
- Anthropic provider with Claude tool-use binding the schema as
  `input_schema`; no-ops without `ANTHROPIC_API_KEY` so CI without the key
  stays green
- `RecordedProvider` for deterministic offline tests
- `TranscriptStore` (DuckDB) — every transpile session is logged for the
  option-3 fine-tune flywheel
- Input adapters for PDF, arXiv (with PDF download), bioRxiv DOI, and raw notes
- Cloud sizing advisor (GCP + AWS) with ready-to-paste commands and hard
  caps on long runs (50 ns / $20 confirmation thresholds)
- Real observable output: `DCDReporter` for trajectories, `mdtraj` post-run
  analysis writes RMSD / RMSF / Rg CSVs
- Pluto notebook UI with the 5-gate pipeline rendered as numbered sections
- CI on GitHub Actions + Woodpecker (Julia 1.10 + 1.11 matrix); live OpenMM smoke in a
  separate pipeline step on Julia 1.10
- `examples/walkthrough.jl` for a no-API-key end-to-end demo

### What works (v1.0 / v1.5 — heavy lifts shipped)

v1.0:
- **SMILES → AMBER topology** via `OpenFFParameterizer` (subprocess: openff-toolkit
  + Interchange). Two new SystemSource types: `:smiles` (pure ligand) and
  `:protein_ligand` (PDBFixer + OpenFF + SMIRNOFFTemplateGenerator at runtime)
- **Alchemical free-energy stages** (`FEPStage`): renderer emits real
  `openmmtools.alchemy` λ windowing with `u_kln.csv` output for MBAR
- **HTTP web frontend** (`crucible serve`): single-page UI + JSON API for
  transpile / validate / render / advise / parameterize. HTTP.jl, no Genie dep
- **Real `LocalProvider`** (OpenAI-compatible: vLLM / Ollama / llama.cpp)

v1.5:
- **REMD** (`REMDStage`): temperature-ladder replica exchange, renderer emits
  `openmmtools.multistate.ParallelTemperingSampler` + multistate netcdf for
  WHAM/MBAR. Acceptance heuristic warns on aggressive ladder ratios.
- **Metadynamics** (`MetadynamicsStage` + `CollectiveVariable`): up to 8 CVs
  (distance/angle/dihedral/RMSD), well-tempered + bias-factor support, renderer
  emits an `openmm-plumed` PLUMED block
- **Membrane systems**: `LipidBilayer` in `SolventSpec`, lipid21 / charmm36_lipid
  FF allowlist, automatic switch from `MonteCarloBarostat` to `MonteCarloMembraneBarostat`
  (XYIsotropic, ZFree) for NPT in the renderer
- **Multi-GPU advisor candidates** (A100x4/x8, L4x4) become competitive when
  the spec demands replicas

### Explicitly deferred (v2+)

- QM/MM (CP2K / TeraChem / Psi4 integration)
- Constant-pH MD
- Coarse-grained MD (Martini explicit support beyond Molly's CG sweet spot)
- Fine-tuned LLM provider against the Crucible-collected transcript corpus
  (Phase B/C/D of the option-3 roadmap; needs ~1k logged sessions first)
- Actual cloud provisioning (advisor outputs commands; you run them)

## Hard rule

The LLM never invents force-field parameters. The IR carries source attribution
on every numeric field. The renderer is the only thing that converts units.

## Flagship use cases

Three application-area docs covering [cancer drug discovery](docs/CANCER_USE_CASES.md),
[materials science](docs/MATERIALS_USE_CASES.md), and
[protein engineering](docs/PROTEIN_ENGINEERING_USE_CASES.md). Each
ships canned templates with a "when to pick which" guide and an honest
"what's deferred" section. Single index at
[`docs/USE_CASES.md`](docs/USE_CASES.md). List all templates:

```bash
crucible templates list
crucible templates init <name> --out spec.json
```

## GPU acceleration

The OpenMM renderer emits a platform-fallthrough block: when the script runs
it tries `CUDA → HIP → OpenCL → CPU` in order and picks the first available.
Override with `CRUCIBLE_PLATFORM=HIP` (or `CUDA`/`CPU`/`Reference`) to force a
specific platform.

- **NVIDIA**: install `openmm` from conda/pip; CUDA driver ≥ 11.x.
- **AMD ROCm**: install OpenMM with the HIP plugin (`conda install -c
  conda-forge openmm-hip` on a ROCm-enabled machine). Crucible's `crucible
  doctor` probes both `nvidia-smi` and `rocm-smi`, so an AMD-only box surfaces
  cleanly.
- **CPU fallback**: works everywhere; ~10-30× slower than a discrete GPU.

The cloud advisor's `benchmarks.toml` covers 8 NVIDIA cloud profiles plus AMD
entries (RX 7900 XT for local rigs, MI300X for Azure ND_MI300X_v5). VRAM
headroom is checked against the spec's `n_atoms_estimate` (≈150 bytes/atom +
25% margin) — the advisor warns if the chosen GPU likely won't fit.

## Quick start

```bash
julia --project -e 'using Pkg; Pkg.instantiate()'

# Run the Pluto notebook UI
julia --project -e 'using Pluto; Pluto.run(notebook="src/ui/notebook.jl")'

# Or use the CLI
bin/crucible help
bin/crucible walkthrough notes "AMBER ff14SB / TIP3P / 300K / 100 ns NPT"
bin/crucible transpile pdf paper.pdf --out spec.json
bin/crucible validate spec.json --backend openmm
bin/crucible render   spec.json --backend openmm --out run.py
bin/crucible advise   spec.json --budget-hours 6
```

Set `ANTHROPIC_API_KEY` in the environment to enable the live LLM extractor.
Without it, the CLI/notebook works against `RecordedProvider` fixtures.

To run the script that crucible emits, you'll need OpenMM (`pip install openmm`)
or Molly (`Pkg.add("Molly")`) installed wherever the script runs.

### Reproducible builds via Docker

If you don't have Julia locally, the project runs cleanly in `julia:1.10`
or `julia:1.11` containers. The pattern used in development:

```bash
docker run --rm \
  -v "$PWD":/work -v /tmp/crucible-depot:/julia-depot \
  -w /work -e JULIA_DEPOT_PATH=/julia-depot julia:1.10 \
  bash -c 'julia --project -e "using Pkg; Pkg.test()"'
```

The cached depot at `/tmp/crucible-depot` makes subsequent runs ~10× faster.

For the full live OpenMM + PDBFixer + mdtraj smoke (matches the CI pipeline
step):

```bash
./examples/smoke_alanine_dipeptide.sh   # requires `pip install openmm pdbfixer`
# or just run the test suite with CRUCIBLE_RUN_OPENMM=1
```

## Documentation

- [`docs/HOW_TO_READ.md`](docs/HOW_TO_READ.md) — six role-specific
  reading guides (wet-lab biologist, comp chem, research software
  engineer, PI evaluating adoption, new PhD student, LLM-tooling
  engineer). Pick yours; ignore the rest.
- [`docs/PLAN.md`](docs/PLAN.md) — architecture, rationale, roadmap.
- [`docs/ADOPTION_PLAN.md`](docs/ADOPTION_PLAN.md) — 18-month
  go-to-market plan with phases + decision gates for academia / OSS
  / business modes. Companion analysis at
  [`musings/scaling_modes.md`](musings/scaling_modes.md).
- [`docs/IR.md`](docs/IR.md) — auto-generated MDSpec field reference
- [`AGENTS.md`](AGENTS.md) — contributor + Claude-Code guidance (hard rules,
  dev pattern, testing conventions, how to add backends/providers/adapters)
- [`CHANGELOG.md`](CHANGELOG.md) — versioned change log
- [`examples/walkthrough.jl`](examples/walkthrough.jl) — end-to-end demo,
  no API key required (uses RecordedProvider)
- [`examples/lifecycle.jl`](examples/lifecycle.jl) — full option-3
  fine-tune flywheel: transpile → log → user-edit → diff → log → JSONL
- [`examples/from_methods.jl`](examples/from_methods.jl) — hand-built MDSpec
- [`examples/from_smiles.jl`](examples/from_smiles.jl) — `:smiles` SystemSource
  + OpenFFParameterizer end-to-end (ethanol-in-vacuum)
- [`examples/protein_ligand_fep.jl`](examples/protein_ligand_fep.jl) — `:protein_ligand`
  source + `FEPStage` decoupling λ-windowing scaffolding
- [`examples/remd_protein_folding.jl`](examples/remd_protein_folding.jl) — 8-replica
  temperature-REMD via `openmmtools.multistate`
- [`examples/membrane_protein.jl`](examples/membrane_protein.jl) — GPCR in POPC
  bilayer with `MonteCarloMembraneBarostat`

## How the option-3 flywheel works

Every transpile session can be appended to `~/.local/share/crucible/transcripts.duckdb`
(see `TranscriptStore`). When the user edits the LLM-emitted MDSpec to fix
hallucinated values, the second log entry plus `diff_specs(llm, user)` is the
training-pair signal: input paper text, target spec (the user's correction).

The IR-first design is what makes this tractable. We're not curating
`(paper, runnable_code)` pairs — we're curating `(paper, MDSpec_json)` pairs,
which validate against `schema.json` deterministically. When ~1k corrected
sessions are collected, fine-tuning a small open-weights model
(Qwen2.5-Coder, etc.) on JSON Schema-validated outputs is straightforward.

`bin/crucible diff a.json b.json` and `tools/regenerate_fixtures.sh check`
expose the diff at the CLI level; `examples/lifecycle.jl` exercises the
whole loop in ~100 LOC.
