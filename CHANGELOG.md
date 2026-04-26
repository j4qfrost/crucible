# Changelog

## Unreleased

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
