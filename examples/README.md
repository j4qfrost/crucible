# Crucible examples

Each example is self-contained and runnable with `julia --project examples/<name>.jl` from the repo root. Examples that need optional Python deps print exactly which ones at startup; nothing in `examples/` is required for the test suite.

## By sampling method

| Method | Example | What it shows |
|---|---|---|
| **Vanilla MD** | [`from_methods.jl`](from_methods.jl) | Hand-built MDSpec from a Methods-section paragraph; no LLM round-trip |
| **Vanilla MD** | [`smoke_alanine_dipeptide.sh`](smoke_alanine_dipeptide.sh) | Shell smoke test: alanine-dipeptide in vacuum, single Pkg.test() pass |
| **SMILES → MD** | [`from_smiles.jl`](from_smiles.jl) | `:smiles` SystemSource + `OpenFFParameterizer` (ethanol-in-vacuum, end-to-end) |
| **Alchemical FEP** | [`protein_ligand_fep.jl`](protein_ligand_fep.jl) | `:protein_ligand` source + `FEPStage` decoupling λ-windowing (1ubq + p-cresol) |
| **Replica exchange (REMD)** | [`remd_protein_folding.jl`](remd_protein_folding.jl) | 8-replica T-REMD via `openmmtools.multistate.ParallelTemperingSampler` |
| **Membrane MD** | [`membrane_protein.jl`](membrane_protein.jl) | GPCR in POPC bilayer, automatic `MonteCarloMembraneBarostat` |

## By workflow stage (LLM loop)

| Stage | Example | Notes |
|---|---|---|
| **Paper → MDSpec** | [`walkthrough.jl`](walkthrough.jl) | End-to-end demo using `RecordedProvider` (no API key required) |
| **Pluto interactive** | [`walkthrough_notebook.jl`](walkthrough_notebook.jl) | Pluto notebook format — open via `Pluto.run(notebook=...)` |
| **v1.5 method tour** | [`walkthrough_v15_methods.jl`](walkthrough_v15_methods.jl) | Pluto: pick a template (vanilla / smiles / fep / remd / membrane / metad) → IR + validation + cloud sizing + lint + rendered script in one flow. No Python deps needed. |
| **Option-3 flywheel** | [`lifecycle.jl`](lifecycle.jl) | Full flywheel: transpile → log → user-edit → diff → log → JSONL export |

## Required runtime deps

| Example | Python runtime needs | Notes |
|---|---|---|
| `from_methods.jl` / `walkthrough.jl` / `walkthrough_notebook.jl` / `lifecycle.jl` | none for IR + render | execution needs `openmm` if you actually run the script |
| `from_smiles.jl` | `openff-toolkit openff-interchange rdkit` | `parameterizer_available()` probes cleanly |
| `protein_ligand_fep.jl` | `openmm pdbfixer openff-toolkit openmmforcefields openmmtools mdtraj` | also needs `pymbar` for downstream ΔG analysis |
| `remd_protein_folding.jl` | `openmm openmmtools` (`mpiplus` optional for multi-node) | netcdf output via `MultiStateReporter` |
| `membrane_protein.jl` | `openmm pdbfixer mdtraj` | also expects pre-built lipid topology in workdir |

## How an example becomes a test

Several examples mirror the structure of the matching test file (`from_smiles.jl` ↔ `test/smiles_test.jl`, `remd_protein_folding.jl` ↔ `test/remd_test.jl`, etc.). The convention: examples target the human reader (provenance, narrative, optional execution); tests target the CI machine (assertions, no I/O beyond temp files).

If you add a new heavy-lift feature, please add **both** an example here and a matching test under `test/`. The test pins behavior; the example documents intent.
