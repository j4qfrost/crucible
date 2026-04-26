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

### What works in v0

- `MDSpec` IR + JSON Schema (the LLM contract)
- Two `SimBackend` implementations:
  - `MollyBackend` — native Julia, sweet spot is CG / implicit / small / autodiff
  - `OpenMMBackend` — via PythonCall + OpenMM, the workhorse for solvated
    protein–ligand systems
- A `Router` that picks a backend based on spec features
- Validation gates 1–2 (JSON Schema + semantic rules) — reject malformed or
  physically incoherent specs without ever touching a GPU
- Anthropic provider scaffolding (Claude tool-use → MDSpec); no-ops without
  `ANTHROPIC_API_KEY` set
- Input adapters for PDF, arXiv, bioRxiv DOI, and raw notes
- Cloud sizing advisor (GCP + AWS) with ready-to-paste `gcloud` / `aws`
  commands and hard caps on long runs
- Pluto notebook UI

### What is explicitly *not* in v0

- SMILES → ligand force-field parameters (you supply prepared topology)
- Free-energy methods, enhanced sampling, QM/MM, membranes, plumed
- Multi-GPU / multi-replica orchestration
- Local / fine-tuned LLM providers (interface stubbed; see roadmap)
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
