# crucible

[![CI](https://snowman.tailddc637.ts.net/api/badges/j4qfrost/crucible/status.svg)](https://snowman.tailddc637.ts.net/repos/j4qfrost/crucible)
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

v0.5 (active development). See `docs/PLAN.md` for the full design and roadmap.

| Component        | Count | Items                                                |
|------------------|-------|------------------------------------------------------|
| Tests            | 153   | offline; +5 with `CRUCIBLE_RUN_OPENMM=1`             |
| Backends         | 3+1   | `MollyBackend`, `OpenMMBackend`, `KineticsBackend` (stub) |
| LLM providers    | 2+1   | `AnthropicProvider`, `RecordedProvider`, `LocalProvider` (stub) |
| Input adapters   | 4     | PDF, arXiv, bioRxiv, raw notes (PDFs auto-extracted via `pdftotext`) |
| Output renderers | 3+1   | `PlutoRenderer`, `MarkdownRenderer`, `NotebookRenderer`, `WebRenderer` (stub) |
| CLI subcommands  | 7     | `transpile`, `validate`, `render`, `advise`, `summarize`, `diff`, `walkthrough` |
| Validation gates | 5     | schema, semantic, loadability, preview, user-confirm |
| Examples         | 5     | `walkthrough.jl`, `walkthrough_notebook.jl`, `lifecycle.jl`, `from_methods.jl`, `smoke_alanine_dipeptide.sh` |
| Tools            | 3     | `check.sh`, `regenerate_docs.jl`, `regenerate_fixtures.sh` |

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
- CI on Woodpecker (Julia 1.10 + 1.11 matrix); live OpenMM smoke in a
  separate pipeline step on Julia 1.10
- `examples/walkthrough.jl` for a no-API-key end-to-end demo

### Explicitly deferred (v1+)

- SMILES → ligand force-field parameters (you supply prepared topology
  for ligand systems; canonical-residue protein systems use `:pdb_fetch`)
- Free-energy methods, enhanced sampling, QM/MM, membranes, plumed
- Multi-GPU / multi-replica orchestration
- Local / fine-tuned LLM providers (interface stubbed; transcript flywheel
  is collecting training data)
- Actual cloud provisioning (advisor outputs commands; you run them)

## Hard rule

The LLM never invents force-field parameters. The IR carries source attribution
on every numeric field. The renderer is the only thing that converts units.

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

- [`docs/PLAN.md`](docs/PLAN.md) — architecture, rationale, roadmap
- [`docs/IR.md`](docs/IR.md) — auto-generated MDSpec field reference
- [`AGENTS.md`](AGENTS.md) — contributor + Claude-Code guidance (hard rules,
  dev pattern, testing conventions, how to add backends/providers/adapters)
- [`CHANGELOG.md`](CHANGELOG.md) — versioned change log
- [`examples/walkthrough.jl`](examples/walkthrough.jl) — end-to-end demo,
  no API key required (uses RecordedProvider)
- [`examples/lifecycle.jl`](examples/lifecycle.jl) — full option-3
  fine-tune flywheel: transpile → log → user-edit → diff → log → JSONL
- [`examples/from_methods.jl`](examples/from_methods.jl) — hand-built MDSpec

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
