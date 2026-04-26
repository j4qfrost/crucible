# crucible

A Julia drug-discovery simulation app with an LLM paper-transpiler.

Drop in a paper (PDF, arXiv ID, bioRxiv DOI, or pasted notes), and an LLM
extracts the molecular-dynamics protocol into a structured intermediate
representation (`MDSpec`). A Julia compiler then renders that IR into a
runnable Molly.jl or OpenMM simulation, validated end-to-end before any GPU
time is spent.

The user shell is a Pluto.jl notebook.

## Status

v0 (in development). See `docs/PLAN.md` for the full design and roadmap.

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
# Optional: install OpenMM + tooling for the OpenMMBackend
julia --project -e 'using Pkg; Pkg.add(["PythonCall", "CondaPkg"]); using CondaPkg'
# Run the notebook
julia --project -e 'using Pluto; Pluto.run(notebook="src/ui/notebook.jl")'
```

Set `ANTHROPIC_API_KEY` in the environment to enable the LLM extractor.

## Project layout

See `docs/PLAN.md` for the full architecture and the rationale behind the
five-gate validation pipeline.
