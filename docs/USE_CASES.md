# Use cases — index

Crucible covers three flagship application areas. Each ships canned
templates, an in-depth doc explaining when to pick which, and an
honest "what's deferred" section.

> **First time here?** [`HOW_TO_READ.md`](HOW_TO_READ.md) has
> role-specific reading guides — pick the one matching your background
> (wet-lab biologist, computational chemist, research software
> engineer, PI, PhD student, LLM-tooling engineer) for a curated path
> through the project.

| Domain | Doc | Templates | Question shape |
|---|---|---|---|
| **Cancer drug discovery** | [`CANCER_USE_CASES.md`](CANCER_USE_CASES.md) | `kinase_inhibitor_fep`, `bcl2_ppi_inhibitor`, `gpcr_oncogene_membrane` | "Will this candidate drug bind this oncogenic target?" |
| **Materials science** | [`MATERIALS_USE_CASES.md`](MATERIALS_USE_CASES.md) | `polymer_dynamics`, `battery_electrolyte` | "What's the bulk transport / conformational property of this material?" |
| **Protein engineering** | [`PROTEIN_ENGINEERING_USE_CASES.md`](PROTEIN_ENGINEERING_USE_CASES.md) | `enzyme_design_remd`, `antibody_paratope_fep` | "Is this designed protein going to work?" |

Plus six general-purpose templates that don't fit a single domain
neatly: `vanilla`, `smiles`, `protein_ligand_fep`, `remd`, `membrane`,
`metadynamics`. List them all with:

```bash
crucible templates list
```

## Picking a starting point

If you're new to Crucible and not sure which template to start from:

- **You have a paper that describes a specific MD protocol.** Use the
  LLM transpile path: `crucible transpile pdf paper.pdf --provider
  recorded:test/fixtures/recorded_anthropic_spec.json` (or
  `--provider anthropic` if you have the API key set). The output is
  a fresh `MDSpec` matching the paper.
- **You're doing kinase-inhibitor work.** `kinase_inhibitor_fep`.
- **You're doing PPI inhibitor work** (Bcl-2, MDM2, KRAS, MCL-1).
  `bcl2_ppi_inhibitor`.
- **You have a GPCR or another membrane oncogene.** `gpcr_oncogene_membrane`.
- **You have an AlphaFold/RFdiffusion design.** `enzyme_design_remd`.
- **You're maturing an antibody.** `antibody_paratope_fep`.
- **You're doing electrolyte transport.** `battery_electrolyte`.
- **You're doing polymer chain dynamics.** `polymer_dynamics`.
- **None of the above, but it's a small ligand in solvent.**
  `smiles`.
- **None of the above, but it's a generic protein-ligand FEP.**
  `protein_ligand_fep`.
- **None of the above and you want to start blank.** `vanilla`.

## Common workflow across all domains

```bash
crucible doctor                                   # confirm tooling
crucible templates list                           # see options + per-template lint+coverage
crucible templates init <name> --out spec.json    # seed a spec
crucible health spec.json                         # validate + lint + coverage in one panel
crucible advise spec.json --budget-hours N        # cloud sizing
crucible run spec.json --workdir runs/<date> \    # render + execute
    --seed 42 --precision mixed
crucible analyze runs/<date> --format markdown    # observable summary
crucible plot runs/<date>                         # PNG plots (needs matplotlib)
crucible snapshot runs/<date> --out result.tar.gz # pack for sharing
```

Each step is independently usable — you can stop after any of them
and resume later. The templates' `notes` fields explain what each
step expects.

## What's deferred across the board

Listed in each use-case doc with the rationale, but in summary:

- **Quantum / EAM / catalysis FFs** — see `docs/QUANTUM_OUTLOOK.md`
  + `musings/quantum_outlook_eli5.md` for the "ML potentials are
  the path forward" argument.
- **Constant-pH MD runtime** — IR is scaffolded; renderer raises
  with a pointer at `openmm-constph`.
- **Martini coarse-graining runtime** — IR is scaffolded; renderer
  raises with a pointer at `martinize2`.
- **REST2 (replica exchange with solute tempering)** — would need
  a new stage type beyond plain T-REMD; not yet scaffolded.
- **Multi-state / ensemble design loops** — Crucible's IR is for
  "validate one design"; orchestrating N designs is the calling
  application's job.

## Adding a new use case

The pattern documented in `CONTRIBUTING.md` § "Adding a new stage
type" / "Adding a new force-field family" covers the IR side. For
a new application-area docs page, copy the structure of any of the
three above:

1. At-a-glance template table.
2. Per-template "use this when / don't use this for / caveats /
   generalizes to" sections.
3. Honest "what's deferred" section.
4. Recommended workflow that ties together the existing CLI surface.

The audit-friendliness invariant: a reviewer should be able to read
the doc, look at the templates, and verify the doc's claims match
what the templates actually emit (`crucible templates show <name>`
+ `crucible explain <spec>`).
