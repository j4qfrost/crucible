# Benchmark axes — reference

Canonical reference for the 10 axes the hallucination benchmark
([`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md))
grades against. Companion to
[`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) — the
verification doc tells you HOW to flip an entry; this one tells you
WHAT each field means and how it's scored.

> **Source of truth:**
> [`python/crucible/benchmark/scorer.py`](../python/crucible/benchmark/scorer.py).
> If anything below drifts from the code, the code wins.

## The 10 axes

| Axis | Type | Spec path | Grading rule |
|---|---|---|---|
| `protein_ff` | enum (string) | `force_field.protein` | case-insensitive equality |
| `water_model` | enum (string) | `system.solvent.model` | case-insensitive equality |
| `ensemble` | enum (string) | `protocol[-1].ensemble` (last DynamicsStage) | case-insensitive equality |
| `dt_fs` | float | `protocol[-1].dt_fs` | `math.isclose` (rel_tol=1e-6) |
| `temperature_K` | float | `protocol[-1].temperature_K` | `math.isclose` |
| `duration_ns` | float | `protocol[-1].duration_ns` | `math.isclose` |
| `pressure_bar` | float | `protocol[-1].pressure_bar` | `math.isclose` |
| `fep_lambda_count` | int | `len(protocol[FEPStage].lambda_windows)` | exact equality |
| `solvent_padding_nm` | float | `system.solvent.padding_nm` (added v0.4.0) | `math.isclose` |
| `thermostat` | enum (string) | `protocol[-1].thermostat` | case-insensitive equality |

Two universal rules across every axis:

1. **`None` ground truth is not scored.** When the paper deliberately
   doesn't specify a knob (or you couldn't find it during
   verification), set the `ExpectedProtocol` field to `None`. The
   scorer drops that axis from both numerator and denominator. This
   is intentional: an unspecified knob is not an LLM error.
2. **No partial credit.** A wrong protein FF doesn't get half a point
   for being in the AMBER family. The wedge is "did the LLM get the
   protocol right?" — partial credit makes that signal noisy.

## Per-axis detail

### `protein_ff`

Where: `force_field.protein` (top-level field on the spec).
Allowed values (mirror of `python/crucible/spec.py:PROTEIN_FF`):

- `amber14sb` (≈ ff14SB; the modern AMBER default)
- `amber99sb_ildn` (the long-MD-papers default)
- `amber03`
- `charmm36m` (CHARMM modern default)
- `opls_aam` (Schrödinger / OPLS family — the "atomistic" form)
- `martini3` (coarse-grained)
- `martini2_2` (older coarse-grained)

Common mappings the LLM will be asked to do:

- "ff14SB" → `amber14sb`
- "ff99SB-ILDN" → `amber99sb_ildn`
- "CHARMM36m" → `charmm36m`
- "OPLS3 / OPLS3e / OPLS4" → **gap** (not in allowlist; document the
  schema gap rather than picking the closest)
- "GAFF" → not a protein FF; the LLM should pick a protein FF
  separately. GAFF lives on the ligand axis (not graded yet).

### `water_model`

Where: `system.solvent.model`. Allowlist:

- `TIP3P` (90% of MD papers)
- `TIP4P_EW`
- `SPC_E`
- `implicit_GBSA` (no explicit water)
- `vacuum` (no solvent at all)

For *implicit* water that isn't GBSA (e.g. the ABSINTH or PB family),
the schema doesn't have a slot — gap to flag.

### `ensemble`

Where: the production-stage `DynamicsStage.ensemble`. The scorer
finds the LAST `DynamicsStage` in the protocol. If the paper has
multiple production stages with different ensembles, pick the one
whose duration matches the headline run.

Values: `NVE`, `NVT`, `NPT`. Most modern protein MD is NPT.

### `dt_fs`

Where: production-stage `dt_fs`. Float comparison via
`math.isclose(rel_tol=1e-6)` so 2.0 vs 2.0 matches but 2.0 vs
2.000001 also matches (avoids floating-point fragility).

Common values: 1.0, 2.0, 2.5, 4.0 (the last only with hydrogen-mass
repartitioning).

### `temperature_K`

Production temperature in Kelvin. **Always Kelvin in the IR** —
papers stating "37 °C" must be converted to 310.15 K (or 310.0 if
the paper rounds).

### `duration_ns`

Production duration in nanoseconds. For FEP, this is `duration_per_window_ns`;
for REMD, `duration_per_replica_ns`. For long-MD papers (μs / ms), the
unit conversion is exact: 1 μs = 1000 ns; 1 ms = 1,000,000 ns.

### `pressure_bar`

NPT only. Default benchmark expectation is 1.0 bar (atmospheric).
**Beware:** 1 atm = 1.01325 bar. If the paper says "1 atm," strict
verification puts 1.01325 in `ExpectedProtocol`; if it says "1 bar,"
put 1.0. The scorer's `math.isclose(rel_tol=1e-6)` separates them.

### `fep_lambda_count`

Number of λ-windows in the FIRST `FEPStage` of the protocol. Strict
integer comparison (no isclose). Common values: 11 (every 0.1), 22
(every ~0.05), the FEP+ default of 12.

If the paper has a multi-step decoupling-then-recoupling FEP (e.g.
4 charge windows + 12 vdW windows), pick which subprotocol to score.
Most reasonable: count the window-step that's the headline.

### `solvent_padding_nm`

Added in v0.4.0 (schema 0.3.0 → 0.4.0). Lives at
`system.solvent.padding_nm`. The solute-to-box-edge buffer; typical
1.0 nm (10 Å).

Unit notes:

- Papers stating "10 Å" → `1.0` nm.
- Papers stating "12 Å buffer" → `1.2` nm.
- Papers using a fixed box size rather than padding → `None`
  (deliberately unspecified; not an LLM failure).

### `thermostat`

Production-stage `thermostat`. Allowed values:

- `langevin` (most common in modern MD)
- `nose_hoover` (most common in classical MD)
- `andersen` (rare)
- `berendsen` (deprecated for production; common in equilibration)

If the paper uses Berendsen for production, score that — it's
historically common even though best practice has shifted.

## How to add an axis

Schema-side fields land via the migration framework
([`src/spec/Migrations.jl`](../src/spec/Migrations.jl)) — see
v1.44's `solvent_padding_nm` addition for the template. Once the
field exists in the IR:

1. Add the field to `ExpectedProtocol` in
   [`python/crucible/benchmark/papers.py`](../python/crucible/benchmark/papers.py).
2. Add an entry to `ScoreAxis` enum in
   [`scorer.py`](../python/crucible/benchmark/scorer.py).
3. Add a `_score_*` call in the `score()` function pulling the value
   from the spec and the expected from the entry.
4. Add a row to the table at the top of this file.
5. Add a section under "Per-axis detail" with the source-of-truth
   spec path, allowed values, and any unit-conversion warnings.
6. Update the [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md)
   cheat sheet to include the new axis.
7. Update the interactive `verify` prompt in
   [`benchmark/cli.py`](../python/crucible/benchmark/cli.py).

## See also

- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) —
  the public-facing landing page.
- [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md) — the
  per-paper verification procedure.
- [`python/crucible/benchmark/scorer.py`](../python/crucible/benchmark/scorer.py)
  — the source of truth for scoring rules.
- [`src/spec/schema.json`](../src/spec/schema.json) — the IR schema
  the axes draw from.
