# Plan: Julia Drug-Discovery Sim with LLM Paper-Transpiler

## Context

Greenfield Julia app: a researcher uploads a paper (PDF, arXiv ID, bioRxiv DOI, or notes) into a Pluto.jl notebook, an LLM extracts the molecular-dynamics protocol, and the app produces a runnable Molly.jl / OpenMM simulation with provenance, validation, and a cloud-sizing recommendation. Plug-and-play across four axes: sim backends, LLM providers, input adapters, output renderers.

**Why now:** sits adjacent to (not replacing) augury and microquest/Pixie. v0 ships as a Pluto notebook app — Julia-native, low UI cost, doesn't compete with augury's 2-3 week sprint. LLM strategy is Anthropic API on first pass, with the IR designed to make a future fine-tune (option 3) trivial: training data becomes `(paper_text, MDSpec_json)` pairs rather than `(paper_text, runnable_code)`.

**Why MD-from-paper is hard, and why the design accommodates it:** papers rarely give you a runnable system — only a protocol. Auto-parameterizing ligands from SMILES is its own multi-month project and the highest risk for shipping physically-wrong simulations that *look* fine. v0 sidesteps this with a BYO-topology contract (user supplies prepared system; LLM extracts protocol only). v0.5 adds standard-residue auto-build via OpenMM/PDBFixer; v1 adds OpenFF SMILES→params.

**Naming:** working name `crucible` (alchemy + fire motif, fits user's brand). Final name TBD before first commit.

## v1.0 update (2026-04-26) — heavy lifts shipped

The v1+ items below were partly closed in v1.0:

- **SMILES → ligand parameters**: `OpenFFParameterizer` is now a real subprocess implementation (openff-toolkit + Interchange). New SystemSource types `:smiles` (pure ligand) and `:protein_ligand` (PDBFixer + SMIRNOFFTemplateGenerator at script-runtime). The BYO-topology gate goes away for the common protein + small-molecule case.
- **Alchemical free-energy methods**: `FEPStage` ships with `:decouple` / `:annihilate` modes, λ windowing, and an `openmmtools.alchemy`-based renderer that emits `u_kln.csv` for downstream MBAR analysis.
- **Web frontend**: `WebRenderer` is no longer a stub — `crucible serve` boots an HTTP.jl-based single-page UI + JSON API for the full pipeline. Genie.jl deliberately NOT used (overweight for the endpoint surface).
- **Local LLM provider**: `LocalProvider` is real (OpenAI-compatible: vLLM / Ollama / llama.cpp).

## v1.5 update (2026-04-26) — enhanced sampling + membranes

The remaining v1+ items closed in v1.5:

- **REMD** (`REMDStage`): `openmmtools.multistate.ParallelTemperingSampler` renderer, multistate netcdf output for WHAM/MBAR, T-ladder validation rule (strictly increasing + acceptance-ratio warning).
- **Metadynamics** (`MetadynamicsStage` + `CollectiveVariable`): `openmm-plumed` renderer with up to 8 CVs (distance/angle/dihedral/RMSD), well-tempered + bias-factor support.
- **Membrane systems**: `LipidBilayer` in `SolventSpec`, `:charmm36_lipid` / `:lipid21` / `:slipids` in the FF allowlist, automatic `MonteCarloMembraneBarostat` (XYIsotropic, ZFree) for NPT stages.
- **Multi-GPU advisor**: A100x4/x8, L4x4 candidates with `default_gpu_count` + `multi_gpu_factor`. Become competitive only when `n_replicas >= default_gpu_count`.

Still deferred to v2+: QM/MM, constant-pH MD, explicit Martini coarse-graining (beyond Molly's CG sweet spot), fine-tuned chem-LLM (needs ~1k logged sessions), actual cloud provisioning.

## Non-goals (deferred; do not build in v0)

- SMILES → ligand force-field parameters (no LLM-invented LJ params, ever)
- Free-energy methods (FEP/TI/MM-PBSA), enhanced sampling (REMD/metadynamics), QM/MM, membranes, plumed integration
- Multi-GPU / multi-replica orchestration
- Auto-analysis beyond RMSD / RMSF / energies / trajectory
- Genie.jl web frontend (Pluto only in v0)
- Local-LLM and fine-tuned providers (interface stubbed, not wired)
- Actual cloud provisioning (advisor outputs commands; user runs them)

## Architecture

### Project layout (Julia package)

```
crucible/
├── Project.toml
├── CondaPkg.toml                 # pins OpenMM, openff-toolkit, pdbfixer for PythonCall
├── src/
│   ├── Crucible.jl               # top-level module
│   ├── spec/
│   │   ├── MDSpec.jl             # IR types + provenance
│   │   ├── schema.json           # JSON Schema for LLM-emitted MDSpec
│   │   └── units.jl              # explicit unit handling (Unitful.jl)
│   ├── backends/
│   │   ├── SimBackend.jl         # abstract interface (validate / estimate / prepare / preview / run!)
│   │   ├── MollyBackend.jl       # native Julia, CG/implicit/autodiff sweet spot
│   │   ├── OpenMMBackend.jl      # PythonCall.jl → OpenMM, the workhorse for protein-ligand
│   │   └── Router.jl             # picks backend from spec features
│   ├── adapters/
│   │   ├── InputAdapter.jl       # abstract: source -> normalized PaperRepr
│   │   ├── PDFAdapter.jl         # local PDF (pdftotext via PDFio.jl or poppler shellout)
│   │   ├── ArxivAdapter.jl       # arXiv ID -> abstract + PDF
│   │   ├── BioRxivAdapter.jl     # DOI -> uses bioRxiv MCP server (already in user env)
│   │   └── NotesAdapter.jl       # raw text passthrough
│   ├── llm/
│   │   ├── Provider.jl           # abstract LLMProvider
│   │   ├── AnthropicProvider.jl  # Claude with structured tool-use output -> MDSpec
│   │   ├── LocalProvider.jl      # stub for Pixie/Gemma path (option 2/3 roadmap)
│   │   └── prompts/              # system prompts + few-shot extraction examples
│   ├── validation/
│   │   └── Gates.jl              # 5 gates: schema, semantic, loadability, preview, user-confirm
│   ├── renderers/
│   │   ├── Renderer.jl           # abstract: SimResult -> artifact
│   │   ├── PlutoRenderer.jl      # in-notebook plots, RMSD, trajectory viewer
│   │   ├── NotebookRenderer.jl   # exports a standalone .jl Pluto notebook
│   │   └── WebRenderer.jl        # stubbed for v1 Genie path
│   ├── cloud/
│   │   ├── Advisor.jl            # (atoms, ns, ensemble) -> {gpu, instance, cost, command}
│   │   └── benchmarks.toml       # seeded from OpenMM published throughputs
│   └── ui/
│       └── notebook.jl           # the Pluto entry-point
└── test/
    ├── runtests.jl
    ├── spec_schema_test.jl
    ├── renderer_golden_test.jl   # IR -> rendered script, golden-file diff
    └── validation_gates_test.jl
```

### The IR (MDSpec) — single most important design choice

LLM emits **structured JSON conforming to `schema.json`**, not raw Julia code. This is the keystone:

- Hallucination surface collapses to a finite enum/numeric space
- JSON Schema validation is deterministic (Gate 1)
- Multi-backend rendering (Molly today, OpenMM today, GROMACS/AMBER tomorrow) requires an IR anyway
- **Fine-tune roadmap (option 3)** becomes feasible: curating `(paper, MDSpec)` pairs is dramatically easier than curating `(paper, runnable_code)` pairs, and validity is checkable without execution
- Every field carries `provenance: {source: "paper §2.3" | "default" | "assumed", confidence: float}` for the assumed-vs-extracted UI

Shape (illustrative, schema is authoritative):

```json
{
  "system": {"source": {"type": "user_supplied", "topology": "...", "coordinates": "..."},
             "n_atoms_estimate": 42000, "has_ligand": true,
             "solvent": {"model": "TIP3P", "ions": {"NaCl_mM": 150}}},
  "force_field": {"protein": "amber14sb", "water": "tip3p", "ligand": "user_supplied"},
  "protocol": [
    {"stage": "minimize", "max_iterations": 5000},
    {"stage": "equilibrate", "ensemble": "NVT", "duration_ns": 0.1, "temperature_K": 300, "thermostat": "langevin", "restraints": {"heavy_atoms": "harmonic", "k_kj_mol_nm2": 1000}},
    {"stage": "equilibrate", "ensemble": "NPT", "duration_ns": 0.5, "pressure_bar": 1.0, "barostat": "monte_carlo"},
    {"stage": "production", "ensemble": "NPT", "duration_ns": 10.0, "dt_fs": 2.0, "constraints": "h_bonds"}
  ],
  "observables": [{"type": "rmsd", "selection": "protein and name CA", "stride_ps": 10},
                  {"type": "trajectory", "stride_ps": 100}],
  "provenance": { "...": "..." },
  "warnings": ["Paper specifies 'Amber99', mapped to amber99sb-ildn — verify"]
}
```

### Backend abstraction (real from day one)

```julia
abstract type SimBackend end
abstract type SimSpec end           # MDSpec <: SimSpec; KineticsSpec, PBPKSpec drop in later

validate_spec(::SimBackend, spec::SimSpec)::ValidationReport
estimate_resources(::SimBackend, spec::SimSpec)::ResourceEstimate
prepare(::SimBackend, spec::SimSpec, workdir::String)::PreparedJob
preview_run(::SimBackend, job::PreparedJob; n_steps=100)::PreviewReport
run!(::SimBackend, job::PreparedJob; on_progress=identity)::SimResult
collect_artifacts(::SimBackend, result::SimResult)::Vector{SimArtifact}
supported_features(::SimBackend)::Set{Symbol}   # :pme, :npt, :implicit_solvent, :autodiff
```

**v0 ships two backends:** `MollyBackend` for CG / implicit / small / autodiff (Julia's defensible niche), `OpenMMBackend` (via `PythonCall.jl`, with versions pinned in `CondaPkg.toml`) as the workhorse for any solvated protein-ligand system. `Router` chooses based on `supported_features` ∩ spec requirements; defaults to OpenMM when ambiguous and surfaces the choice + reason in Pluto.

### Validation pipeline (5 gates, sequential, non-skippable)

1. **Schema** — JSON Schema validation. Free, deterministic, catches ~80% of LLM mistakes.
2. **Semantic** — Julia rules the schema can't express: NPT ⇒ barostat present; constraints `h_bonds` + dt > 4 fs ⇒ warn; implicit solvent + barostat ⇒ reject; production stage must follow ≥1 equilibration; `has_ligand=true` + `ligand_ff=user_supplied` + missing topology ⇒ reject.
3. **Loadability** — actually load topology + coords in chosen backend. Catches missing residues, broken bonds, atom-count mismatch — before allocating a GPU.
4. **Preview run** — 100–1000 steps locally (CPU or tiny GPU slice). Assert: energies finite (no NaN, no 1e30 blowups), NVT temperature within ±50 K of target, max force component bounded.
5. **User confirmation** — Pluto cell renders MDSpec, provenance table, backend choice, sizing estimate, preview diagnostics. User clicks `run production` or edits the spec.

### Cloud sizing advisor

Inputs: `(atom_count, total_ns, ensemble, has_pme, backend)`. Lookup table in `benchmarks.toml` seeded from published OpenMM throughputs (rough order: T4 ~25–60 ns/day, L4 ~80–150, A10G ~100–180, A100 ~250–450, H100 ~400–700 for ~25–50k atom solvated proteins; Molly ~0.2–0.4× of OpenMM on the same workload). Scale linearly with atom count up to saturation.

Output: candidates table sorted by cost, recommendation defaulting to "smallest GPU that finishes within budget." For a typical 10 ns run on 30k atoms, the right answer is L4 (~2–3 hr, ~$3) — never H100. Includes ready-to-paste `gcloud compute instances create` and `aws ec2 run-instances` commands. Hard caps: 10 ns default duration, explicit confirmation past 50 ns or $20 estimated cost.

Cloud platforms covered: GCP (user is fluent — knows GKE n4d from es-ingest bench) and AWS. Azure deferred.

### Plug-and-play axes — what's real in v0 vs. stubbed

| Axis                | v0 status                                                          |
|---------------------|---------------------------------------------------------------------|
| Sim backends        | Molly + OpenMM real. Kinetics/PBPK have IR + interface, not wired. |
| LLM providers       | Anthropic real. Local/fine-tuned have abstract trait + stub impl.  |
| Input adapters      | PDF + Notes real. arXiv + bioRxiv real (bioRxiv via existing MCP). |
| Output renderers    | Pluto real. Notebook export real. Web (Genie) stubbed.             |
| Cloud advisor       | GCP + AWS recommendations real; provisioning is user-side.         |

## Build order

The IR and the renderers must work *before* the LLM is wired in. Building the LLM first is the canonical failure mode of "paper-transpiler" projects.

1. `MDSpec` types + `schema.json` + Unitful unit handling
2. `OpenMMBackend` renderer: `MDSpec` → executable OpenMM Python script (no LLM yet — hand-write specs to test)
3. `MollyBackend` renderer: `MDSpec` → Molly script
4. Validation gates 1–3 (no GPU, no LLM)
5. `AnthropicProvider`: paper text + system prompt + tool-use schema → `MDSpec` JSON; round-trip to renderer
6. Gate 4 (preview run) wired in
7. `PlutoRenderer` + `ui/notebook.jl` — minimal: upload widget, MDSpec viewer, provenance table, run button
8. `Adapters/*` — PDF / arXiv / bioRxiv ingestion
9. `cloud/Advisor.jl` + benchmarks table
10. `LocalProvider` stub finalized (just contract, not implementation)

## Roadmap to "Option 3" (specialized fine-tuned chem model)

The IR-first design is what makes this tractable.

- **Phase A (v0 ship):** Anthropic + structured output → MDSpec. Log every `(paper_text, MDSpec, user_edits, validation_outcome)` tuple to a local DuckDB (user already uses `dart_duckdb` in sidequest — same engine).
- **Phase B (data flywheel):** Crowdsource ~1k paper→MDSpec pairs from logged sessions + public MD methods sections.
- **Phase C (train):** Fine-tune Qwen2.5-Coder-7B or similar open model on the pair corpus; reward signal is JSON Schema validity + human review (cheaper than execution-based reward, which is the curse of code-gen fine-tunes).
- **Phase D (deploy):** Drop-in `LocalProvider` swap behind `LLMProvider` interface — zero changes elsewhere.

## Critical files / interfaces to define first

These are the load-bearing pieces — getting them right de-risks everything downstream:

- `src/spec/MDSpec.jl` + `src/spec/schema.json` — the IR; everything else is downstream
- `src/spec/units.jl` — explicit Unitful handling; **never let the LLM convert units**, the renderer does it
- `src/backends/SimBackend.jl` — the abstract interface that locks plugin extensibility in
- `src/backends/OpenMMBackend.jl` — the workhorse renderer; getting this clean validates the IR
- `src/validation/Gates.jl` — sequencing of the five gates is non-negotiable
- `src/llm/AnthropicProvider.jl` — built last, after the compiler works without an LLM

## Verification (end-to-end)

**Unit-level:**
- `test/spec_schema_test.jl` — sample MDSpec JSONs validate; malformed ones reject with useful error
- `test/renderer_golden_test.jl` — fixed MDSpecs render to byte-identical OpenMM and Molly scripts (golden files in `test/fixtures/`)
- `test/validation_gates_test.jl` — each gate accepts known-good and rejects known-bad spec mutations

**Integration smoke (no LLM):**
- Hand-written MDSpec → OpenMMBackend renderer → executes a 1000-step run on a tiny test system (`test/fixtures/alanine_dipeptide.pdb`, vacuum, AMBER ff14SB) → produces non-NaN energies. Runs locally on CPU in <30 s.

**LLM-loop smoke:**
- Feed `test/fixtures/sample_md_methods.txt` (excerpt from a known MD paper) → AnthropicProvider → MDSpec → schema-valid → renderer → preview-run gate passes.

**Pluto end-to-end:**
- `julia --project -e 'using Pluto; Pluto.run(notebook="src/ui/notebook.jl")'` — upload alanine-dipeptide PDB + a paper excerpt → see MDSpec with provenance → click preview → see RMSD plot → see cloud advisor recommend a T4 with the gcloud command.

**Cloud advisor sanity:**
- For (30k atoms, 10 ns, NPT, OpenMM): advisor recommends L4 / g2-standard-4, ~2–3 hr, ~$3. For (200k atoms, 100 ns, NPT, OpenMM): A100 / a2-highgpu-1g, with cost-confirmation prompt fired.

## Risk register (what will actually go wrong)

1. **Ligand parameterization**, if scope creeps into v0 — would ship physically-wrong sims that look fine. BYO-topology gate is hard.
2. **LLM-mapped force-field names** ("Amber99" → which?). Mitigated by strict allowlist + warnings on every mapping.
3. **Silent unit errors** (kJ/kcal, nm/Å, ps/ns). IR carries units explicitly; renderer is the only converter.
4. **PythonCall + CondaPkg env hell** on first setup. Pin OpenMM 8.x and openff-toolkit; expect ~1 week of integration cost.
5. **Molly bugs in long runs** outside its proven envelope. Don't promote Molly past CG/implicit/small/autodiff in v0.
6. **Cloud cost runaway.** Hard caps + confirmation prompts on long runs.
7. **Pluto reactivity firing long-running cells** on every spec edit. Gate behind `@bind run_button` patterns.
