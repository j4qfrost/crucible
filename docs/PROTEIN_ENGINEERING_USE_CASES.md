# Protein engineering use cases

Crucible's third flagship application area, alongside cancer drug
discovery (`docs/CANCER_USE_CASES.md`) and materials science
(`docs/MATERIALS_USE_CASES.md`). Where cancer-MD asks "does this
existing protein bind this drug" and materials-MD asks "what's the
bulk transport coefficient", protein engineering asks "is this
*designed* protein going to work?"

The two natural sub-questions:

1. **Stability.** A computationally designed enzyme — say, an
   AlphaFold or RFdiffusion output — should stay folded at 310 K,
   physiological ionic strength. T-REMD samples conformational
   ensembles to test this faster than long-timescale unbiased MD.
2. **Affinity.** Antibody affinity maturation, TCR-pMHC tuning,
   hormone-receptor optimization — all map to "what's the ΔΔG of
   this point mutation at the binding interface?" Annihilation FEP
   on the mutated residue gives a number that's directly comparable
   to single-mutation BLI/SPR experiments.

## At a glance

| Template | Question it answers | Typical compute |
|---|---|---|
| `enzyme_design_remd` | Does my designed enzyme stay folded? Where are the mobile loops? | 8 GPUs × ~2 days (REMD) |
| `antibody_paratope_fep` | What's the ΔΔG of this paratope mutation? | 1 GPU × ~3 days (per run; need ≥2 for ΔΔG) |

Both use `:user_supplied` source — designed proteins start as
predicted/built structures, not crystal structures.

```bash
crucible templates init enzyme_design_remd    --out spec.json
crucible templates init antibody_paratope_fep --out spec.json
```

## 1. Enzyme design stability — T-REMD ensemble

**Use this when**: you have an AlphaFold/RFdiffusion/ProteinMPNN
candidate + want to know if it folds stably before wet-lab synthesis.

**What the template does**:

1. Loads pre-built topology + coordinates.
2. Standard equilibration ladder (heavy-atom restrained → backbone
   restrained → free).
3. **8-replica T-REMD** across 300–408 K (exponential ladder, ratio
   ≈ 1.10 → ~25-30% acceptance heuristic for ≤200-residue proteins).
4. 5 ns per replica with exchange every 2 ps. Outputs to
   `remd_*.nc` (multistate netcdf for openmmtools-side analysis).

**Caveats**:

- 5 ns/replica is a starter. Folding-stability work needs 50+
  ns/replica.
- T-ladder is for soluble proteins ≤ 200 residues. Bigger designs
  → REST2 (replica exchange with solute tempering) which biases
  the protein temperature alone, leaving water at 300 K. Crucible's
  `:remd` doesn't auto-emit REST2 yet; that's a future stage type.
- Multi-GPU: 8 replicas → 8-GPU node ideal. The renderer auto-emits
  `mpi4py` + per-rank `CUDA_VISIBLE_DEVICES` binding (see v1.10.1
  changelog).

**Generalizes to**:

- Membrane protein design (combine with `:gpcr_oncogene_membrane`
  pattern — membrane bilayer + REMD)
- De-novo binder design (RFdiffusion → MPNN → AlphaFold cycle, MD
  validation)
- Loop-grafted antibody scaffolds (test that the graft doesn't
  destabilize)

## 2. Antibody paratope ΔΔG — annihilation FEP

**Use this when**: you have an antibody + antigen complex (or any
protein-protein interface) + a candidate paratope mutation. You want
to predict whether the mutation strengthens, weakens, or doesn't
affect binding.

**What the template does**:

1. Loads pre-built topology + coordinates with the mutated residue
   tagged as `resname MUT`.
2. Equilibration ladder (heavy-atom → backbone → free), longer
   than usual (5 ns NPT) because PPI interfaces relax slowly.
3. **Annihilation FEP** across 11 λ windows × 3 ns. Annihilation
   (not decoupling) is the correct alchemy for protein-side
   mutations — we want to remove all the residue's contributions,
   not just intermolecular ones.
4. Outputs `fep_*_u_kln.csv` for downstream `pymbar.MBAR` analysis.

**The ΔΔG protocol**:

1. Run the template twice — once with the mutant residue, once
   with WT.
2. ΔG_mutant − ΔG_WT = ΔΔG (positive = mutation hurts binding,
   negative = mutation helps).
3. Use `crucible diff --intent <wt_spec> <mutant_spec>` to confirm
   the only spec difference is the mutated residue.
4. For statistical confidence, run each side ≥3 times with
   different `CRUCIBLE_SEED_STAGE_<i>` values; report mean ± SE.

**Caveats**:

- 3 ns/window is a starter. Convergent ΔΔG for protein-protein
  interfaces needs 5–10 ns/window plus error analysis (BAR or
  bootstrap).
- Single-step annihilation can be unstable for charged residues.
  For Asp/Glu/Lys/Arg/His mutations, use a *complex+free* leg pair
  to cancel net-charge artifacts (Crucible doesn't auto-do this
  yet — manual extension).
- Reference experimental data: ΔΔG predictions in the 0.5–2.0
  kcal/mol range are the practical target. Larger differences are
  meaningful but harder to converge; smaller differences are below
  most FEP setups' noise floor.

**Generalizes to**:

- TCR-pMHC affinity maturation
- Hormone-receptor agonist tuning
- Enzyme-substrate KM optimization
- Any single-point mutation at a protein-protein interface

## What's deferred

- **Computational design itself.** Crucible doesn't generate
  designs — it validates designs after they're produced by
  RFdiffusion/MPNN/Rosetta. The IR represents "fixed structure to
  simulate"; design-loop integration would be a separate tool that
  emits a sequence of MDSpecs and post-processes them.
- **Multi-state design** (designing for binding A AND not binding
  B). Manual: run two specs, diff with `crucible diff`.
- **Ensemble FEP** (multiple starting structures averaged). The
  IR doesn't have a "ensemble" concept; run N specs with different
  seeds, average post-hoc.
- **Long-timescale folding** (ms scale). Even REMD doesn't reach
  this; specialized tools (Anton, MSMs) needed.

## Recommended workflow

Same skeleton as the other use cases — see the workflow section in
`docs/CANCER_USE_CASES.md`. The protein-engineering specifics:

1. **Build the input first.** AlphaFold/RFdiffusion → PDBFixer →
   tleap. Crucible doesn't auto-handle this; it's pre-Crucible
   tooling. The `:user_supplied` source assumes you've done it.
2. **For ΔΔG**: build TWO topologies — WT and mutant — sharing the
   same coordinates as much as possible. The `resname MUT` trick
   is just so the FEP `target_selection` can find the relevant
   residue.
3. **Always run with `--seed`** for reproducibility, and run replicate
   seeds for statistics.

## See also

- `docs/CANCER_USE_CASES.md` — the kinase + PPI + GPCR templates
  use the same FEP/REMD primitives.
- `docs/MATERIALS_USE_CASES.md` — for systems where the question is
  bulk-property rather than design.
- `musings/why_ir_as_contract.md` — why design-loop integration is
  deliberately separate from Crucible's IR.
