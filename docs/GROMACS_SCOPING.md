# GROMACS exporter — scoping

What it would take to add GROMACS as a third backend alongside OpenMM
and Molly. Phase A weeks 7-9 of
[`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md).
The technical-feasibility expert in the salt-mines verdict flagged
"Python/GROMACS-less" as a TAM cap; this is the path to closing that
without committing to a full GROMACS-renderer build until pilot
demand validates it.

## Why this matters

Roughly half of the published MD field uses GROMACS, the other half
uses AMBER (often via OpenMM). A pharma CADD lead's first
disqualifier is often: *"can it produce a GROMACS input deck?"* The
honest answer today is "no." The honest answer Crucible needs is:
*"yes, here's the subset, here's what's deferred, here's how it
maps."*

This page is the IR-level scoping. The renderer skeleton is shipped
at [`src/backends/GROMACSBackend.jl`](../src/backends/GROMACSBackend.jl);
its public methods raise "not yet implemented" with the specific
gap, so the Router still routes around GROMACS in v1.x and the
existing OpenMM/Molly paths are unaffected.

## What GROMACS' input deck actually is

A GROMACS run is a tuple of files, not a single script:

| File | Role | Crucible source |
|---|---|---|
| `.top` (topology) | Bonded + non-bonded params per molecule | Renderer-emitted, derived from `force_field` + `system.source.topology` |
| `.gro` or `.pdb` (coordinates) | Initial atom positions | `system.source.coordinates` (unchanged passthrough) |
| `.mdp` (run parameters) | Integrator, ensemble, thermostat, barostat, output stride | Renderer-emitted, derived from a single `Stage` |
| `.ndx` (atom-group index, optional) | Named atom groups for selections / restraints | Renderer-emitted from `RestraintSpec.selection` / `Observable.selection` |
| (per-stage `grompp` + `mdrun` invocation) | The actual run | Shell driver script |

The crucial structural fact: **one GROMACS run = one `.mdp` per
stage, plus a shell script that chains them.** A multi-stage Crucible
protocol (minimize → NVT eq → NPT eq → production) maps to four
`.mdp` files plus a `run.sh`. This is mechanically straightforward
to render; the cost is in the per-knob translation.

## Coverage map

What of Crucible's IR can render to GROMACS today, what's deferred,
what's structurally incompatible.

### MVP (Phase 1: ~2 weeks of work)

The set that covers the published-paper baseline. Rendering only —
`run!` is OOS for the MVP.

| MDSpec field | GROMACS equivalent | Notes |
|---|---|---|
| `system.source.topology` (`.parm7`) | `pdb2gmx` or pre-built `.top` | AMBER `.parm7` requires `acpype` or `parmed` to convert; document the manual step |
| `system.source.coordinates` (`.rst7`) | `.gro` (via `parmed`) | Same |
| `system.solvent.model` ∈ {TIP3P, TIP4P-EW, SPC/E} | `[ system ] water_model` | Direct mapping |
| `system.solvent.ions_NaCl_mM` | `genion -np N -nn N` | Renderer computes counts |
| `force_field.protein` ∈ {amber14sb, amber99sb_ildn, charmm36m} | `pdb2gmx -ff` | Allowlist 1:1 |
| `MinimizeStage` | `integrator = steep` | `emtol = tolerance_kj_mol_nm` |
| `DynamicsStage` (NVE / NVT / NPT) | `integrator = md` + tcoupl/pcoupl | All four CHARMM/AMBER ensembles |
| `dt_fs`, `temperature_K`, `pressure_bar`, `friction_ps` | direct knobs | Unit conversion in renderer (1 fs = 0.001 ps in `.mdp`) |
| `constraints` ∈ {none, h_bonds, all_bonds} | `constraints = none / h-bonds / all-bonds` | Direct |
| `RestraintSpec.selection` ∈ {heavy_atoms, backbone, ca} | `[ position_restraints ]` + `.ndx` group | Per-stage `.itp` overlay |
| `Observable.type` ∈ {trajectory, rmsd, rmsf, rg} | `gmx mdrun -x` + post-run `gmx rms / rmsf / gyrate` | Trajectory direct; analyses post-run |
| `Observable.stride_ps` | `nstxout-compressed = stride_ps / dt_fs * 1000` | Conversion |

That's ~70% of the published-paper protocols Crucible aims to handle.

### Phase 2 (post-pilot)

Bigger lifts; only worth it if a pilot actually requests them.

- **Lipid bilayers** — GROMACS' POPC/POPE building flow is via
  CHARMM-GUI (membrane builder, exports GROMACS deck directly) or
  the `slipids` workflow. Crucible's `LipidBilayer` IR field would
  emit the right `[ system ]` molecule list + a build-script
  shim that calls CHARMM-GUI's tooling. Not free, but tractable.
- **REMD** — GROMACS has native REMD via `gmx mdrun -multidir`. The
  `temperature_ladder_K` field maps to a per-replica `.mdp` directory
  layout. Mechanical port; ~3 days.
- **Constraints other than h-bonds via SHAKE** — LINCS is the
  GROMACS default for h-bonds; SHAKE is supported but slower. Just
  emit `constraint-algorithm = LINCS` and document the swap.

### Deferred (out of scope until concrete pilot demand)

- **Alchemical FEP** — GROMACS has its own `free-energy = yes`
  pathway with `init-lambda`, `couple-lambdas`, and `delta_lambda`.
  This is its own dialect; a faithful port is ~2 weeks. Defer until
  a pilot specifically asks for GROMACS-FEP (most do not — FEP+ /
  openmmtools dominates the FEP audience).
- **Metadynamics** — GROMACS-PLUMED is a separate compile of
  GROMACS itself. Crucible would need to emit PLUMED scripts and
  document the `gmx mdrun -plumed plumed.dat` invocation.
  Tractable, but couples to PLUMED-specific renderer state.
- **Constant-pH MD** — GROMACS has CpHMD, but the implementation
  variants (CHARMM-GUI's CpHMD vs. Bertran/Lindahl 2024 vs. ad hoc
  patches) make for a moving target. Defer until v2 IR's
  `ProtonationSpec` actually has a runnable target.

### Structurally incompatible

Things the IR carries that GROMACS literally can't represent without
forking GROMACS:

- **Differentiable simulation** (Molly's autodiff use case) —
  GROMACS is C/C++, no AD. Emit a clear error: "differentiable
  simulation requires Molly; route to MollyBackend."
- **In-process simulation** — GROMACS is always a subprocess; the
  Molly in-process path doesn't have a GROMACS analog. Not a real
  problem (Crucible's OpenMM path is also subprocess), just
  documenting.

## Renderer skeleton

`src/backends/GROMACSBackend.jl` is shipped as a stub:

- `supported_features` returns the MVP set above (`{:nvt, :npt,
  :explicit_solvent, :constraints, :pme, :thermostat, :barostat}`).
- `validate_spec` rejects anything outside the MVP coverage with a
  clear "deferred to Phase 2" / "deferred indefinitely" / "use
  MollyBackend instead" message.
- `prepare`, `preview_run`, `run!` raise
  `error("GROMACSBackend: rendering not yet implemented")` with a
  hint to set `--backend openmm` or watch this issue.

The skeleton's purpose is twofold:

1. The Router can claim "GROMACS is acknowledged" without falsely
   advertising it. `supported_features` is honest.
2. When pilot demand justifies the work, only the renderer body
   needs to be filled in — the public interface is locked.

## Outreach implication

In the Tier-2 cold-email template
([`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md)) the relevant line
moves from:

> *"Crucible's deliverable today is an OpenMM script."*

to:

> *"Crucible's primary deliverable is OpenMM. GROMACS export is
> scoped (see GROMACS_SCOPING.md) and will land alongside the first
> pilot that asks for it."*

That's a meaningful upgrade in the pharma conversation — it
acknowledges the TAM cap honestly and ties scope expansion to
pilot pull rather than speculative build.

## See also

- [`src/backends/GROMACSBackend.jl`](../src/backends/GROMACSBackend.jl)
  — the skeleton.
- [`src/backends/OpenMMBackend.jl`](../src/backends/OpenMMBackend.jl)
  — the reference renderer to mirror.
- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  Phase A weeks 7-9 — the planning context.
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) Tier 2 messaging —
  the outreach this unblocks.
