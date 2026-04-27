# MDSpec — IR field reference

Auto-generated from `src/spec/schema.json` by `tools/regenerate_docs.jl`. Do not edit by hand.

**Schema version:** `0.1.0`

## Top-level fields

| field | type | required | notes |
|-------|------|----------|-------|
| `provenance` | `object` | ✓ |  |
| `force_field` | `object` | ✓ |  |
| `protocol` | `array` | ✓ |  |
| `notes` | `string` | ✓ |  |
| `warnings` | `array` | ✓ |  |
| `observables` | `array` | ✓ |  |
| `schema_version` | ``"0.1.0"`` | ✓ |  |
| `system` | `object` | ✓ |  |

## `system`

### system fields

| field | type | required | notes |
|-------|------|----------|-------|
| `has_ligand` | `boolean` | ✓ |  |
| `solvent` | `object` | ✓ | strict (no extra fields) |
| `source` | `object` | ✓ | strict (no extra fields) |
| `n_atoms_estimate` | `integer` | ✓ | min=1; max=10000000 |

### system.solvent fields

| field | type | required | notes |
|-------|------|----------|-------|
| `membrane` | oneOf | — |  |
| `model` | enum: `TIP3P`, `TIP4P_EW`, `SPC_E`, `implicit_GBSA`, `vacuum` | ✓ |  |
| `ions_NaCl_mM` | `number` | ✓ | min=0; max=5000 |

### system.source fields

| field | type | required | notes |
|-------|------|----------|-------|
| `coordinates` | string or null | — |  |
| `topology` | string or null | — |  |
| `ligand_smiles` | string or null | — |  |
| `type` | enum: `user_supplied`, `pdb_id`, `pdb_fetch`, `smiles`, `protein_ligand` | ✓ |  |
| `pdb_id` | string or null | — |  |

## `force_field`

### force_field fields

| field | type | required | notes |
|-------|------|----------|-------|
| `water` | enum: `TIP3P`, `TIP4P_EW`, `SPC_E`, `implicit_GBSA`, `vacuum` | ✓ |  |
| `protein` | enum: `amber14sb`, `amber99sb_ildn`, `amber03`, `charmm36m`, `opls_aam` | ✓ |  |
| `ligand` | enum: `user_supplied`, `gaff2`, `openff_sage_2_2_0` | ✓ |  |
| `lipid` | oneOf | — |  |

## `protocol` stages

Each stage is one of two shapes (oneOf):

### Stage kind: `minimize`

### fields

| field | type | required | notes |
|-------|------|----------|-------|
| `kind` | `"minimize"` | ✓ |  |
| `max_iterations` | `integer` | ✓ | min=1; max=1000000 |
| `tolerance_kj_mol_nm` | `number` | ✓ | min=0; max=1000000 |

### Stage kind: `remd`

### fields

| field | type | required | notes |
|-------|------|----------|-------|
| `pressure_bar` | number or null | ✓ |  |
| `kind` | `"remd"` | ✓ |  |
| `ensemble` | enum: `NVT`, `NPT` | ✓ |  |
| `dt_fs` | `number` | ✓ | max=5; > 0 |
| `thermostat` | enum: `langevin`, `nose_hoover`, `andersen`, `berendsen` | ✓ |  |
| `friction_ps` | `number` | ✓ | min=0; max=100 |
| `constraints` | enum: `none`, `h_bonds`, `all_bonds` | ✓ |  |
| `exchange_attempt_period_ps` | `number` | ✓ | max=1000; > 0 |
| `duration_per_replica_ns` | `number` | ✓ | max=10000; > 0 |
| `temperature_ladder_K` | `array` | ✓ | minItems=2 |

### Stage kind: `metadynamics`

### fields

| field | type | required | notes |
|-------|------|----------|-------|
| `dt_fs` | `number` | ✓ | max=5; > 0 |
| `bias_factor` | `number` | ✓ | min=1; max=100 |
| `bias_deposit_period_ps` | `number` | ✓ | max=1000; > 0 |
| `cvs` | `array` | ✓ | minItems=1 |
| `constraints` | enum: `none`, `h_bonds`, `all_bonds` | ✓ |  |
| `duration_ns` | `number` | ✓ | max=100000; > 0 |
| `bias_height_kj_mol` | `number` | ✓ | max=1000; > 0 |
| `well_tempered` | `boolean` | ✓ |  |
| `kind` | `"metadynamics"` | ✓ |  |
| `ensemble` | enum: `NVT`, `NPT` | ✓ |  |
| `temperature_K` | `number` | ✓ | min=0; max=1000 |
| `thermostat` | enum: `langevin`, `nose_hoover`, `andersen`, `berendsen` | ✓ |  |
| `friction_ps` | `number` | ✓ | min=0; max=100 |
| `pressure_bar` | number or null | ✓ |  |

### Stage kind: `free_energy`

### fields

| field | type | required | notes |
|-------|------|----------|-------|
| `target_selection` | `string` | ✓ |  |
| `dt_fs` | `number` | ✓ | max=5; > 0 |
| `constraints` | enum: `none`, `h_bonds`, `all_bonds` | ✓ |  |
| `duration_per_window_ns` | `number` | ✓ | max=100; > 0 |
| `kind` | `"free_energy"` | ✓ |  |
| `ensemble` | enum: `NVT`, `NPT` | ✓ |  |
| `temperature_K` | `number` | ✓ | min=0; max=1000 |
| `thermostat` | enum: `langevin`, `nose_hoover`, `andersen`, `berendsen` | ✓ |  |
| `friction_ps` | `number` | ✓ | min=0; max=100 |
| `lambda_windows` | `array` | ✓ | minItems=2 |
| `fep_kind` | enum: `decouple`, `annihilate` | ✓ |  |
| `pressure_bar` | number or null | ✓ |  |

### Stage kind: `dynamics`

### fields

| field | type | required | notes |
|-------|------|----------|-------|
| `role` | enum: `equilibrate`, `production` | ✓ |  |
| `dt_fs` | `number` | ✓ | max=5; > 0 |
| `restraints` | `object` | ✓ | strict (no extra fields) |
| `constraints` | enum: `none`, `h_bonds`, `all_bonds` | ✓ |  |
| `barostat` | oneOf | ✓ |  |
| `duration_ns` | `number` | ✓ | max=10000; > 0 |
| `kind` | `"dynamics"` | ✓ |  |
| `ensemble` | enum: `NVE`, `NVT`, `NPT` | ✓ |  |
| `temperature_K` | `number` | ✓ | min=0; max=1000 |
| `thermostat` | enum: `langevin`, `nose_hoover`, `andersen`, `berendsen` | ✓ |  |
| `friction_ps` | `number` | ✓ | min=0; max=100 |
| `pressure_bar` | number or null | ✓ |  |

### restraints fields

| field | type | required | notes |
|-------|------|----------|-------|
| `kind` | enum: `harmonic`, `flat_bottom` | ✓ |  |
| `selection` | enum: `heavy_atoms`, `backbone`, `ca`, `none` | ✓ |  |
| `k_kj_mol_nm2` | `number` | ✓ | min=0; max=1000000 |

## `observables`

### observable fields

| field | type | required | notes |
|-------|------|----------|-------|
| `selection` | `string` | ✓ |  |
| `stride_ps` | `number` | ✓ | > 0 |
| `type` | enum: `rmsd`, `rmsf`, `energy`, `trajectory`, `rg` | ✓ |  |

## Hard rules

- The LLM never invents force-field parameters. The `protein`, `water`, and
  `ligand` fields are restricted to the enums above; mappings from paper-stated
  names happen at extraction time and are logged as warnings.
- Numeric fields carry units in their names (`temperature_K`, `dt_fs`,
  `duration_ns`, `pressure_bar`, `friction_ps`, `k_kj_mol_nm2`,
  `tolerance_kj_mol_nm`). The renderer is the only code that converts; the
  LLM never does unit math.
- Provenance is required for every numeric field that came from the paper.
  The `provenance` object is keyed by JSONPath-ish strings (e.g.
  `"protocol[2].temperature_K"`).

