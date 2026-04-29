# Changelog

## Unreleased

### v1.19 — critical-moment detection + plot annotation + visualization doc (2026-04-29)

Closest the project will get to "labels critical moments on a
particle visualization." Honest scope: 2D summaries + flagged frames
in JSON; 3D rendering happens in PyMOL/VMD/ChimeraX/NGL via the
documented hand-off recipes.

- **`crucible events <workdir> [--format text|json|markdown]`** —
  heuristic critical-moment detection on observable CSVs:
  `:rmsd_jump`, `:rg_expansion`, `:distance_crossing` (default
  threshold 0.6 nm — covalent → nonbonded transition), `:hbond_drop`
  (50% drop in 10-frame running mean), `:energy_spike` (z > 3.0 in
  rolling 50-frame window on OpenMM StateDataReporter logs). Output
  is a list of `CrucibleEvent` records or a paste-ready Markdown
  table.
- **`crucible plot --annotate`** — overlays detected events as red
  vertical lines on the matplotlib PNGs. Composable with the
  existing `--out-dir` + `--python` flags. Title shows event count.
- **`docs/VISUALIZATION.md`** — honest scope doc + integration
  recipes for PyMOL / VMD / ChimeraX / NGL (notebook). Explicitly
  lists what's deliberately out of scope (embedded SPA viewer,
  real-time animation during runs, animated tutorials) so a reader
  knows whether their use case fits.
- New `src/spec/Events.jl` module exporting `CrucibleEvent` +
  `detect_events`. Pure Julia, no new deps.
- Tests: 868/868 (+8 events-detection assertions).

### v1.18 — role-specific reading guides (2026-04-29)

- **`docs/HOW_TO_READ.md`** — six role-specific reading guides in one
  doc. Each section has the same shape: minimum prep, reading order,
  hands-on exercises, "you've got it when…" checkpoint, and what to
  read past the basics.
  - **Wet-lab biologist** — uses Crucible as a tool, no coding required.
  - **Computational chemist** — already knows OpenMM, wants the
    architectural delta.
  - **Research software engineer** — here for the IR-as-contract
    pattern + the musings.
  - **PI evaluating adoption** — adoption decision matrix +
    sustainability questions.
  - **New PhD student** — 3-week curriculum tying Crucible to
    Frenkel & Smit + OpenMM docs.
  - **LLM-tooling engineer** — patterns worth stealing
    (structured-output as JSON Schema; provenance + lint + coverage
    triple; three-provider abstraction; transcripts → DuckDB).
- README's `## Documentation` section gains a pointer at the
  reading guides.
- `docs/USE_CASES.md` adds a "first time here?" callout pointing at
  the reading guides.
- Tests: 860/860 (no code changes).

### v1.17 — protein-engineering + use-case index + bench baseline (2026-04-28)

Third flagship application area + consolidation of the use-case
docs into a single index + a saved bench baseline for CI regression
detection.

- **`crucible templates init enzyme_design_remd`** — 8-replica
  T-REMD across 300–408 K for AlphaFold/RFdiffusion-style enzyme
  design candidates. 5 ns/replica with 2 ps exchange period.
  Tests whether a designed enzyme stays folded under physiological
  conditions; identifies mobile loops and metastable states.
- **`crucible templates init antibody_paratope_fep`** — annihilation
  FEP for antibody paratope mutations (or any protein-protein
  interface mutation). 11 λ × 3 ns. Run twice (WT + mutant), take
  ΔΔG = ΔG(mutant) - ΔG(WT). Generalizes to TCR-pMHC,
  hormone-receptor, enzyme-substrate.
- **`docs/PROTEIN_ENGINEERING_USE_CASES.md`** — application-area
  doc analogous to the cancer + materials docs. At-a-glance table,
  per-template "use this when / don't use this for / caveats /
  generalizes to" sections, the ΔΔG protocol pattern (run twice,
  diff with `--intent`), what's deferred (computational design
  loops, multi-state design, ms-scale folding).
- **`docs/USE_CASES.md` — single index** linking cancer +
  materials + protein engineering with a consolidated picking
  guide ("if you're doing X, start from Y") and the common
  workflow. README slimmed to one paragraph pointing at this index.
- **`tools/baselines/v1.16.json`** — saved `crucible bench` snapshot
  (n=30 per template, all 13 current templates). Future runs can
  diff against this with `crucible bench --baseline tools/baselines/v1.16.json`
  to detect renderer regressions.
- Tests: 860/860 (+34 from v1.16; new templates auto-exercised).

### v1.16 — materials-science use cases (2026-04-28)

A second flagship application area, alongside the cancer-MD templates
shipped in v1.15. Materials science is much wider than what Crucible's
organic-chemistry FF allowlist supports — this release ships what
fits and is honest about what doesn't.

- **`crucible templates init polymer_dynamics`** — PEG-in-water
  20-mer in TIP3P solvent, NPT production with Rg + RMSD
  observables. Generalizes to polyacrylic acid, polyelectrolytes,
  drug-conjugate polymers (combines with the cancer kinase
  templates), polymer gels.
- **`crucible templates init battery_electrolyte`** — 1 M LiPF₆ in
  ethylene carbonate (≈ 4,500 atoms), NPT equilibration → NVT
  production at 1 fs. Observables include Li⁺ ↔ EC carbonyl distance
  for coordination-shell analysis. NVT for production (not NPT) so
  short-time MSD isn't biased by box-volume fluctuations. Generalizes
  to LiTFSI, FSI, mixed-solvent electrolytes, Na/K-ion chemistries.
- **`docs/MATERIALS_USE_CASES.md`** — application-area doc analogous
  to `CANCER_USE_CASES.md`. At-a-glance template table, per-template
  scientific question + caveats + when-to-pick-which, the recommended
  workflow, and a candid "what's deferred" section covering metals
  (EAM/MEAM), catalysis (ReaxFF / QM-MM), ceramics, DPD-style
  coarse-grained models. Pointer at the ML-potentials lane
  (ANI/MACE/Allegro) as the credible path forward for the deferred
  regimes.
- README "Flagship use case" section restructured into "Flagship
  use cases" with cancer + materials side by side.
- Tests: 826/826 (+34 from v1.15; the new templates are
  auto-exercised by the existing per-template assertions).

### v1.15 — cancer drug-discovery use cases (2026-04-28)

Crucible's flagship use case made explicit. Three cancer-research
templates that map to real, well-known oncology drug-discovery
patterns, plus a docs page explaining when to pick which.

- **`crucible templates init kinase_inhibitor_fep`** — Abl kinase +
  Imatinib analog (PDB `2HYY`) with decoupling FEP across 11 λ
  windows × 2 ns. Models the canonical kinase-inhibitor binding-ΔG
  workflow that Imatinib (Gleevec) established as a clinical
  paradigm.
- **`crucible templates init bcl2_ppi_inhibitor`** — Bcl-2 +
  Venetoclax-fragment (PDB `6O0P`) with 50 ns unbiased NPT
  production. Tracks ligand-residue distance + H-bond count.
  Generalizes to MDM2-p53, KRAS-G12C, MCL-1 — protein-protein
  interaction inhibitors more broadly.
- **`crucible templates init gpcr_oncogene_membrane`** — CXCR4-style
  GPCR oncogene in a 200-lipid POPC bilayer. Renderer
  auto-emits `MonteCarloMembraneBarostat` (XYIsotropic, ZFree).
  Generalizes across the GPCR-oncogene family (S1PR2, GPR55,
  EBI2, …) and to RTKs (EGFR/HER2/ALK) when the topology is
  user-supplied.
- **`docs/CANCER_USE_CASES.md`** — application-area doc with
  at-a-glance template table, per-template scientific question +
  caveats + when-to-pick-which guidance, recommended workflow,
  hard rules specific to cancer-MD work (don't fabricate
  experimental data, drug-likeness is downstream, the renderer
  owns unit conversion).
- **`examples/kinase_inhibitor_walkthrough.jl`** — end-to-end no-execute
  walkthrough showing template → validate → lint → cloud sizing →
  render → "what comes next." Runs in ~5 seconds, zero Python.
- README gains a "Flagship use case: cancer drug discovery"
  section pointing at the templates + docs.
- Tests: 792/792 pass (the new templates are auto-exercised by the
  existing per-template assertions). +51 from v1.14.

### v1.14 — SPA + info JSON + CI hygiene + architectural musings (2026-04-28)

Three rounds of polish, all unblocked.

- **SPA UI: PDF picker.** The `/` page now has a `<input
  type="file" accept="application/pdf">` next to the textarea.
  Selecting a PDF base64-encodes it client-side; clicking
  Transpile sends `paper_pdf_b64` to the existing endpoint.
  Closes the gap from v1.13's PDF-upload backend (which had no
  UI affordance).
- **`crucible info --format json`.** Machine-readable capability
  surface for tooling integration: schema_version, stage_types,
  source_types, observable_types, force_field allowlists per
  axis, backend → features map, templates list,
  openff_available, subcommand list (regex-extracted from
  `HELP_TEXT`).
- **`crucible run --quiet`.** Suppresses the framing output
  (workdir/script/python lines, hook announcements, the `----`
  separators, the exit line). Useful for piping into other
  tooling. CRUCIBLE_QUIET env override is the natural next step
  if a user requests it; flag-only for now.
- **CI hygiene**: both pipelines (GitHub Actions +
  Woodpecker) gain a "Migration smoke" step
  (`tools/migration_smoke.jl` round-trips every fixture through
  every registered migration target) and an "IR.md drift" step
  (regenerates `docs/IR.md` and asserts no diff). Catches
  schema-bump regressions that previously surfaced at review.
- **Four architectural musings** in `musings/`:
  - `why_subprocess_over_pythoncall.md` — the renderer's
    subprocess design choice.
  - `why_ir_as_contract.md` — why the LLM emits MDSpec JSON,
    not runnable Python. The most-important call the project
    has made.
  - `why_dual_ci.md` — why both GH Actions and Woodpecker run
    on every push.
  - `why_no_genie.md` — why HTTP.jl is the right web framework
    for Crucible's 8-endpoint surface.
  - `musings/README.md` indexes them with a "when to add a
    musing" guideline.
- Tests: 741/741 pass on Julia 1.10.

### v1.13.1 — health + migration smoke + per-stage seed + runner Dockerfile (2026-04-28)

Four small wins, all unblocked.

- **`crucible health <spec>`** — bundles validate + lint + coverage
  into one panel with a single-line verdict (`✓ ready` / `⚠ thin` /
  `⚠ noisy` / `✗ broken`). Triages a spec without three separate
  invocations.
- **Per-stage seed override**: `CRUCIBLE_SEED_STAGE_<i>` takes
  priority over `CRUCIBLE_SEED` for stage `<i>`. Useful when the user
  wants different randomization between equilibration and production
  for statistical independence across replicates. Renderer plumbs
  through every existing seeded callsite (`MinimizeStage`,
  `DynamicsStage`, `FEPStage`, `MetadynamicsStage`).
- **`tools/migration_smoke.jl`** — round-trips every fixture through
  every registered migration version + asserts Gate 1 still passes.
  Catches schema-bump drift before it reaches users. Currently 4/4
  pass.
- **`tools/runner.Dockerfile` + `runner-entrypoint.sh`** — containerized
  self-hosted GitHub Actions runner. Lets the user spin up the
  runner with `docker run -d --gpus all -e GHA_RUNNER_TOKEN=…
  crucible-runner` rather than installing the runner binary on the
  host. Token is read at container start (single-use, ~1 hour
  lifetime); SIGTERM gracefully deregisters.
- CLI 29 → 30 subcommands.
- Tests: 741/741 pass on Julia 1.10.

### v1.13 — unblocked-list cleanup (2026-04-28)

Six items off the "in-scope but not done" list, batched.

- **Real `MollyBackend.preview_run`**. The renderer plumbs
  `CRUCIBLE_PREVIEW_STEPS` through the rendered Julia script (mirroring
  OpenMMBackend's pattern); the backend's `preview_run` shells out to
  julia with the env set + tails stdout for finite-energy assertions.
  Same shape as OpenMMBackend, no new deps. (`run!` was already a real
  shell-out — no change there.)
- **Web `POST /api/transpile` accepts `paper_pdf_b64`**. Decodes the
  base64-encoded PDF to a tempfile, ingests via `PDFAdapter` (uses
  `pdftotext` if present), then runs the same transpile path as the
  text variant. Trade-off: base64 inflates payload ~33% but keeps the
  endpoint JSON-only — no multipart parser in Crucible. New
  `paper_chars` field in the response.
- **`crucible plot <workdir>`** — emits PNG plots (one per CSV) via a
  matplotlib subprocess. Skips cleanly when matplotlib isn't installed.
  Same subprocess-over-PythonCall precedent as the rest of the
  pipeline. Output goes to `<workdir>/plots/` by default.
- **`crucible run --pre-run-hook 'cmd' --post-run-hook 'cmd'`** (also
  via `CRUCIBLE_PRE_RUN` / `CRUCIBLE_POST_RUN` env vars) — shell hooks
  that fire before / after the python subprocess. Hook env includes
  `CRUCIBLE_WORKDIR`, `CRUCIBLE_SPEC`, and (post-hook only)
  `CRUCIBLE_RUN_RC` so hooks can branch on success/failure. Trade-off:
  hooks are shell strings; the author owns escaping.
- **`crucible templates list`** now surfaces per-template
  `coverage_score` + lint findings count + stage count. Sortable at a
  glance.
- **`crucible diff --intent`** — adds an "Intent" header to the
  Markdown diff that buckets the change as FF swap / source change /
  protocol resize / parameter retune / etc. Useful for the
  option-3 corpus's human-review pass.
- **`CONTRIBUTING.md`** — human-facing equivalent of `AGENTS.md`. Same
  hard rules + workflow patterns, longer-form prose. Setup, common
  workflows (adding stages / FFs / parameterizers / schema bumps),
  CI conventions, "not currently accepted" list.
- `Base64` added to `Project.toml` (was implicit; now a declared dep
  for Julia 1.10's stricter precompilation).
- Tests: 733/733 pass on Julia 1.10 (offline; +5 with
  `CRUCIBLE_RUN_OPENMM=1`).

### v1.12 — GPU CI smoke + quantum-MD outlook (2026-04-27)

- **`.github/workflows/gpu-smoke.yml`** — closes the live-OpenMM-on-
  real-GPU CI gap. Targets the self-hosted-snowman runner registered
  by `tools/gha-runner-setup.sh`. Renders the `vanilla` template,
  invokes `crucible run` with `--platform auto --precision mixed --seed 42`,
  asserts the workdir contains the expected files. Gated on the
  `gpu-smoke` PR label so unrelated PRs don't queue behind it.
  `CRUCIBLE_GPU_VENV` env / repo secret picks the conda env name
  (default `crucible-openmm`).
- **`crucible doctor` reports OpenMM platforms list** (CPU /
  CUDA / HIP / OpenCL / Reference) so the user knows which
  platforms the install actually exposes — not just "openmm is
  installed."
- **`docs/QUANTUM_OUTLOOK.md`** — project's standing view on
  quantum computing for MD. Conclusion: don't scaffold a
  quantum backend; the IR-relevant extension is a future
  `QuantumParameterizer <: LigandParameterizer`, but only when a
  vendor publishes a ligand-binding result on real hardware
  (~2028+). The more impactful adjacent lane is ML potentials
  (ANI / MACE / Allegro) — adding those to the `LIGAND_FF_ALLOWLIST`
  is the correct next move when they mature, using the existing
  constph/Martini scaffolding pattern. AGENTS.md gets a short
  note pointing at this doc.
- Tests: 715/715 pass on Julia 1.10.

### v1.11.2 — run --resume + bench --baseline (2026-04-27)

Two ergonomic add-ons that compose with v1.11/v1.11.1.

- **`crucible run --resume`** — auto-finds the most recent `.chk`
  in the workdir and threads it through as `CRUCIBLE_RESUME_FROM`
  for the launched python subprocess. One-flag failover after a
  crash mid-run. Errors clearly (rc=3) when no checkpoints are
  present.
- **`crucible bench --save baseline.json` + `--baseline base.json
  [--threshold 20]`** — bench can now save a JSON snapshot or
  compare against one. Per-template render + validate timings are
  diffed; entries that drift more than `--threshold`% are flagged
  as regressions. Returns rc=4 when regressions are present, so
  CI pipelines can gate on this output. JSON output mode includes
  the `regressions` array for machine consumption.
- Tests: 715/715 pass on Julia 1.10.

### v1.11.1 — checkpoint/resume for long runs (2026-04-27)

Long REMD / production runs survive node reboots + queue evictions.

- **`CRUCIBLE_CHECKPOINT_PERIOD_PS`** — when set, every dynamics
  stage gets a `CheckpointReporter` that writes a `<stage>.chk`
  file every N picoseconds. Per-stage filenames so a
  multi-stage protocol can be inspected mid-run.
- **`CRUCIBLE_RESUME_FROM=<path>`** — the rendered script's first
  dynamics stage replaces `setPositions / setVelocities` with
  `loadCheckpoint(path)`. Subsequent stages run as normal. Pattern:
  if a 100 ns production run dies at 73 ns, set
  `CRUCIBLE_RESUME_FROM=$WORKDIR/production_4.chk` and re-run; the
  protocol's earlier minimize/equilibrate stages execute first
  (cheap), then production resumes from the checkpoint.
- Trade-off: env-var-only, no IR pollution. Papers don't state
  checkpoint cadence; it's a runtime knob like seed + precision.
- Tests: 711/711 pass on Julia 1.10.

### v1.11 — `crucible run` + deterministic seeding (2026-04-27)

Closes the spec→results loop and adds reproducibility plumbing.

- **`crucible run <spec> [--workdir path] [--platform X]
  [--precision P] [--seed N] [--python /path/to/py]`** — renders,
  invokes python, streams stdout, returns the python rc. Validates
  first; refuses to run if gates 1-3 fail (rc=2). The flags
  override the matching `CRUCIBLE_*` env vars for the launched
  subprocess, so each invocation is self-contained. Trade-off:
  Crucible doesn't manage the python venv — `--python` lets the
  user point at their own openmm install (and `crucible doctor`
  already verifies it).
- **Deterministic seeding** via `CRUCIBLE_SEED`. The renderer
  emits `_crucible_seed_integrator()` and `_crucible_init_velocities()`
  helpers; every LangevinIntegrator + setVelocitiesToTemperature
  call goes through them. When the env is set, a fresh run is
  byte-reproducible up to the integrator's deterministic-forces
  knob. `CRUCIBLE_DETERMINISTIC_FORCES=1` clamps the remaining
  CUDA/HIP nondeterminism (perf cost; off by default).
- CLI 27 → 28 subcommands.
- Tests: 707/707 pass on Julia 1.10.

### v1.10.1 — multi-GPU REMD + precision control (2026-04-27)

Closes the remaining substantive GPU gaps on top of v1.10's AMD work.

- **Multi-GPU REMD sharding (MPI-aware)**. The REMD renderer now
  emits a try-import for `mpi4py`; under `mpirun -np K`, each rank
  pins itself to a unique `CUDA_VISIBLE_DEVICES` (and
  `HIP_VISIBLE_DEVICES`) and openmmtools auto-distributes replicas
  across ranks via `mpiplus`. Single-process invocation still
  works — the script falls through cleanly when mpi4py is absent.
  Trade-off: the rendered script is environment-aware (the same
  file works mpi-launched OR standalone) rather than emitting two
  variants. Override per-node GPU count via
  `CRUCIBLE_GPUS_PER_NODE`.
- **Precision control via `CRUCIBLE_PRECISION`** env (`single` /
  `mixed` / `double`, default `mixed`). Applied at platform level
  on CUDA / HIP / OpenCL — CPU + Reference ignore it. Trade-off:
  precision is not in the IR (papers don't state it; it's a
  runtime tradeoff, not a paper fact). The renderer plumbs the
  env through, the script logs the effective value at startup.
- `crucible doctor` reports the active `CRUCIBLE_PLATFORM` and
  `CRUCIBLE_PRECISION` env vars.
- Tests: 700/700 pass on Julia 1.10.

### v1.10 — AMD/ROCm support (2026-04-27)

Closes the "renderer assumes CUDA" gap. Trade-off documented in
`OpenMMBackend._emit_protocol`: rather than hard-defaulting to CUDA
(which AMD users had to override every run), the script now picks a
platform via auto-fallthrough so the same rendered script Just Works
on NVIDIA, AMD, or CPU-only boxes.

- **Renderer platform fallthrough**: `_crucible_pick_platform()` in
  every rendered script tries CUDA → HIP → OpenCL → CPU and falls
  through to whichever is available. `CRUCIBLE_PLATFORM=<name>` still
  forces a specific platform. AMD users with `openmm-hip` installed
  no longer need to touch the env.
- **`crucible doctor` multi-vendor probe**: detects NVIDIA via
  `nvidia-smi`, AMD via `rocm-smi --showproductname --showmeminfo`,
  Intel via `intel_gpu_top` presence. Reports cleanly per vendor.
- **AMD cloud advisor entries**: `RX_7900_XT` (gfx1100, local rig
  template — `$0/hr`) and `MI300X` (Azure ND_MI300X_v5).
- **VRAM headroom check**: every benchmark entry gains a `vram_gb`
  field; advisor estimates per-system memory usage at ~150 bytes
  per atom + 25% margin (× 2 for FEP) and flags when the chosen
  GPU is likely to OOM. `CloudCandidate` gains `vram_gb` +
  `fits_system` fields exposed in JSON output.
- **Local-rig recommendation**: `$0/hr` candidates are kept in the
  candidates list but excluded from the cloud "chosen" slot. When
  one fits the system, the advisor surfaces a separate warning
  ("local rig option: RX_7900_XT finishes in 3.93 h at $0").
- README adds a "GPU acceleration" section documenting the
  fallthrough behavior and the conda install hint for `openmm-hip`.
- Tests: 693/693 pass on Julia 1.10.

### v1.9.3 — Pluto + info catch-up + starter_session.sh (2026-04-27)

Closing-out polish for the autonomous session. Brings the Pluto
notebook + `crucible info` output up to schema 0.3.0, and adds a
"first 5 minutes" UX demo script.

- **Pluto notebook banner**: now reads "Schema: v0.3.0 (5 stage
  types … 8 observable types incl. SASA / distance / hbonds)".
- **`crucible info`**: header reads "schema v0.3.0" (was "v1.5"),
  "Schema version" line tracks the current schema (was hard-coded
  "0.1.0"), new "Observable types" line lists all 8.
- **`examples/starter_session.sh`**: shell-script walkthrough that
  runs `crucible doctor → templates list → templates init →
  fmt → lint → coverage → validate → render → advise → explain →
  cite → trajstat` against a fresh workdir. The "first 5 minutes"
  demo for a no-LLM, no-Python user. Self-documenting.
- Tests: 680/680 pass on Julia 1.10.

### v1.9.2 — crucible analyze (2026-04-27)

- **`crucible analyze <workdir> [--format text|markdown|json]`** —
  walks every observable CSV in a workdir (rmsd / rmsf / rg / sasa
  / distance / hbonds), runs `summarize_observable` on each, and
  emits a report. Markdown output is paste-ready for PR descriptions
  / lab notebooks; JSON output feeds external tooling. Complements
  `trajstat` (which lists files) by actually reducing them.
- CLI 26 → 27 subcommands. Tests: 680/680 pass on Julia 1.10.

### v1.9.1 — import-jsonl + LLM prompt v1.9 + explain polish (2026-04-27)

Closes the JSONL round-trip (`templates_to_jsonl` → `import-jsonl`)
and brings the LLM prompt up to schema 0.3.0.

- **`crucible import-jsonl <file.jsonl> [--db path]`** — read a
  JSONL training-pair file (the format `templates_to_jsonl.jl` emits
  + the format `export_transcripts_jsonl` produces) and insert each
  record into a TranscriptStore. Closes the round-trip:
  `crucible templates init … | templates_to_jsonl > seed.jsonl &&
   crucible import-jsonl seed.jsonl` populates the local store with
  six idealized examples. Skipped lines (malformed JSON or missing
  spec_json) are reported, never fatal.
- **LLM transpile prompt v1.9**: now opens with "MDSpec v0.3.0
  schema" (was 0.1.0); the observables enum lists the new
  `:sasa` / `:distance` / `:hbonds` types; rule 14 explains
  the `:distance` selection format ("selA, selB").
- **`crucible explain`** surfaces coarse-grained protein force
  fields with a `(coarse-grained — runtime requires martinize2)`
  hint, so the explainer reflects the v2 IR scaffolding state.
- Tests: 673/673 pass on Julia 1.10. CLI 25 → 26 subcommands.

### v1.9 — schema 0.3.0 / new observables / corpus auditing (2026-04-27)

Schema additive bump + two CLI commands aimed at the option-3 fine-
tune corpus quality story.

- **Schema bump 0.2.0 → 0.3.0** (additive). The
  `observables[].type` enum gains `:sasa`, `:distance`, and
  `:hbonds`. Migration registered as identity (existing specs
  remain semantically valid; only the version string moves).
  `migrate_spec_json` default target advances to `0.3.0`.
  Fixtures migrated in place.
- **OpenMM renderer**: post-run mdtraj block emits the new
  observables. `:sasa` via `mdtraj.shrake_rupley` (per-frame
  total nm²); `:distance` parses a "selA, selB" string and emits
  `mdtraj.compute_distances` over the first atom of each;
  `:hbonds` via `mdtraj.baker_hubbard` per frame (count). Each
  writes a CSV alongside the existing rmsd/rmsf/rg outputs.
- **`crucible export-jsonschema [--out path]`** — dump the
  current `schema.json` to stdout (or a file). Useful for IDE
  schema integration, external validators, and the option-3
  training pipeline that consumes the schema as a typing prior.
- **`crucible audit-transcripts <db.duckdb> [--threshold 0.5]
  [--format text|json]`** — walks every row in a TranscriptStore,
  re-runs Crucible's lint, prints a coverage-score histogram +
  the worst-N entries by score. Provides a single pane to spot
  low-quality entries before they pollute the fine-tune corpus.
- New `iter_transcripts(store)` API (replaces ad-hoc DBInterface
  queries elsewhere).
- **CLI dispatch test bug fix**: the help-text regex now accepts
  hyphenated subcommands (was `\w+`, now `[\w-]+`). Without this,
  `export-jsonschema` and `audit-transcripts` failed the dispatch
  coverage check.
- CLI 23 → 25 subcommands.
- Tests: 665/665 pass on Julia 1.10 (offline; +5 with
  `CRUCIBLE_RUN_OPENMM=1`).

### v1.8.1 — cite / explain / templates_to_jsonl (2026-04-27)

Closes the "what does this spec do?" story. Three small additions
that compound: `cite` lists provenance entries grouped by source,
`explain` produces a paragraph-length natural-language summary
derived from IR fields, and `tools/templates_to_jsonl.jl` exports
all six templates as the option-3 fine-tune training-pair format
(notes-as-paper-text + spec_json).

- **`crucible cite <spec>`** — pretty-print every Provenance
  entry, grouped by source (`paper` / `paper_default` / `user` /
  `assumed` / `runtime_default`), with cite + confidence on each.
  Useful for a "what does this LLM extract vs. assume" review.
- **`crucible explain <spec>`** — natural-language summary
  derived from IR. Per-stage one-liners cover all five stage
  types (`MinimizeStage` / `DynamicsStage` / `FEPStage` /
  `REMDStage` / `MetadynamicsStage`); membrane / constant-pH /
  warning fields surface inline. The output is suitable for
  pasting into a paper or a slack message.
- **`tools/templates_to_jsonl.jl`** — exports every template as a
  JSONL training pair (`{paper_text, spec_json, schema_version,
  method_kind, split}`). Seeds the option-3 fine-tune corpus with
  six idealized examples (one per method), letting downstream
  training start before users have logged 1k real sessions.
- CLI 21 → 23 subcommands.
- Tests: 652/652 pass on Julia 1.10.

### v1.8 — bench / upgrade / GHA runner / template provenance (2026-04-27)

Polishing pass. Each item is small-ish on its own; together they
round out the dev-ops + flywheel story.

- **`crucible upgrade <spec> [--out path] [--target ver]`** — wraps
  `migrate_spec_json` so users (and the option-3 transcript-corpus
  tooling) can bring older fixtures up to the current schema in one
  call. Default target tracks current schema (0.2.0).
- **`crucible bench [--repeat N] [--format text|json]`** — micro-
  benchmarks render_script + run_validation across all templates.
  Catches renderer regressions; JSON output is machine-readable for
  CI baseline tracking.
- **`tools/gha-runner-setup.sh`** — idempotent registration of a
  self-hosted GitHub Actions runner on snowman, so the GH-side CI
  can survive a private-repo billing clamp. Documented but not
  auto-invoked: needs a token from the repo settings page each
  time it's set up. Creates a systemd user unit so the runner
  survives reboots.
- **MarkdownRenderer + PlutoRenderer** now have explicit handlers
  for `FEPStage`, `REMDStage`, `MetadynamicsStage`. (Previously
  rendering any spec with a v1+ stage would error at the
  no-method dispatch.)
- **Template provenance enrichment**. Templates now carry plausible
  per-field provenance entries (paper / paper_default / assumed
  by category), giving a coverage_score around 0.7-0.9 — exercises
  the lint + coverage system as positive training examples for
  the option-3 fine-tune corpus.
- **CLI 19 → 21 subcommands** (`upgrade`, `bench`).
- **Tests**: 630/630 pass on Julia 1.10 (offline; +5 with
  `CRUCIBLE_RUN_OPENMM=1`).

### v1.7 — Martini IR / fmt / trajstat / LLM prompt v1.6 (2026-04-27)

Sibling polish pass to v1.6: another v2 IR scaffold + two small CLI
utilities + a meaningful update to the LLM transpile prompt.

- **Martini coarse-grained protein FF scaffolding**. New entries
  `:martini3` and `:martini2_2` in `PROTEIN_FF_ALLOWLIST` (also
  exposed via `CG_PROTEIN_FF` for convenience). Schema enum widened.
  `_rule_coarse_grain_coherence` rejects atomistic water with CG
  protein and warns on sub-10-fs timesteps. `_rule_constraints_timestep`
  splits its hard cap: 5 fs for atomistic, 30 fs for CG. JSON Schema
  `dt_fs` cap raised 5 → 30. OpenMMBackend's `_emit_forcefield`
  emits a `NotImplementedError` stub pointing at `martinize2` —
  trade-off note: Martini ecosystem has multiple incompatible
  toolchains; v1.x ships IR + validation, v2 commits the renderer.
  `:coarse_grain` added to `required_features` + supported_features.
- **`crucible fmt <spec> [--in-place]`** — pretty-print MDSpec JSON.
  Tiny recursive printer (preserves insertion order; doesn't sort
  keys to avoid surprising diffs). Round-trips schema-valid.
- **`crucible trajstat <workdir>`** — walks the workdir, classifies
  files (`:trajectory` / `:timeseries` / `:checkpoint` / `:spec` /
  `:script` / `:other`) by extension. Optional mdtraj sniff for
  per-trajectory frame + atom counts when `mdtraj` is on PATH.
- **LLM transpile prompt v1.6**. New rules 9-13 for enhanced
  sampling, membranes, coarse-grained, constant-pH; updated
  `system.source.type` enum; new fallback-behavior section
  ("never fabricate; emit warnings; round-trip serves as v2
  training signal"); added cross-field invariants for the new
  stage types.
- **CLI 17 → 19 subcommands** (`fmt`, `trajstat`).
- **Tests**: 563/563 pass on Julia 1.10. New files:
  `martini_test.jl` (9 testsets), `cli_extras_test.jl` (4 testsets).

### v1.6 — templates / snapshot / constph IR / v1.5 walkthrough (2026-04-27)

A polish pass focused on user onboarding (templates, snapshot/restore,
walkthrough notebook) plus IR scaffolding for the next big feature
(constant-pH MD).

- **`crucible templates`** — six canned starter MDSpecs:
  `vanilla`, `smiles`, `protein_ligand_fep`, `remd`, `membrane`,
  `metadynamics`. Templates are programmatic (function builders in
  `src/spec/Templates.jl`), so they're guaranteed schema-valid and
  zero-drift on schema bumps. Trade-off documented in the source.
  Subcommands: `list`, `show <name>`, `init <name> [--out path]`.
  Tests pin every template through Gates 1-2 + Router dispatch.
- **`crucible snapshot` / `crucible restore`** — pack a workdir
  (MDSpec + script + logs/trajectories) into a reproducible
  `.tar.gz` with a checksumed manifest. `--max-size-mb` truncates
  large files to a stub recording original size + sha256. Restore
  verifies sha256 by default (`--no-verify` to skip). Trade-off
  noted: shells out to `tar` rather than using `Tar.jl` stdlib +
  `CodecZlib`, matching the project's subprocess-over-pure-Julia
  precedent.
- **MarkdownRenderer** for `LintReport` + `CoverageReport`. Full
  GFM tables for both, embeddable in PR descriptions or README.
- **Web frontend new endpoints**: `/api/lint`, `/api/coverage`,
  `GET /api/templates`, `GET /api/templates/<name>`. Single-page
  UI gains "Lint" and "Coverage" buttons.
- **Constant-pH MD IR scaffolding (v2)**. New `ProtonationSpec`
  attaches optionally to `SystemSpec.protonation`. Schema entry,
  JSON round-trip, validation rule (`_rule_protonation_coherence`),
  `:constph` + `:titration` features, `OpenMMBackend.supported_features`
  declares them. Renderer emits a `NotImplementedError` stub with
  remediation hint pointing at `openmm-constph`. Trade-off: ship
  IR shape + validation now so user transcripts collected in v1.x
  forward-compat with the eventual v2 runtime.
- **`examples/walkthrough_v15_methods.jl`** — Pluto notebook that
  picks a template, validates, lints, costs, and renders the
  script in one flow. No Python deps needed; offline iteration
  for the full v1.5 method surface.
- **CLI**: 14 → **17 subcommands** (added `templates`,
  `snapshot`, `restore`).
- **Tests**: 532/532 pass (up from 471). New files:
  `templates_test.jl`, `snapshot_test.jl`, `constph_test.jl`.

### v1.5.2 — diagnostic + quality CLI (2026-04-27)

UX-only polish: three new CLI subcommands and one new module that
landlines the option-3 fine-tune flywheel's quality story.

- **`crucible doctor`** — environment diagnostic. Probes python,
  openmm, openff-toolkit, pdbfixer, mdtraj, openmmtools,
  openmm-plumed, openmm-forcefields. Reports versions + remediation
  hints. GPU detection via `nvidia-smi`. Surface-level verdict line
  ("all green" / "good" / "partial" / "IR + LLM only") so the user
  knows at a glance what's runnable.
- **`crucible coverage <spec>`** — provenance-coverage report.
  Per-source breakdown (`:paper`, `:paper_default`, `:assumed`,
  `:user`, `:runtime_default`), quality score [0.0–1.0] weighted
  toward `:paper`, and an explicit list of numeric fields missing
  a provenance entry. The score directly feeds transcript-quality
  ranking for the option-3 training corpus.
- **`crucible lint <spec> [--format text|json]`** — advisory checks
  beyond Gates 1-3. Rules: `:short_production`, `:no_equilibration`,
  `:rmsd_no_trajectory`, `:trajectory_observable_no_stride`,
  `:provenance_low`, `:assumed_dominates`, `:fep_few_windows`,
  `:fep_short_window`, `:remd_few_replicas`, `:metad_no_well_tempered`.
  Never blocks; returns a `LintReport` the caller decides what to
  do with.
- New module `src/spec/Coverage.jl` exporting `CoverageReport`,
  `LintFinding`, `LintReport`, `provenance_coverage`,
  `coverage_score`, `lint`.
- `crucible info` updated for the new subcommands (now 14 total).
- New test file `test/coverage_test.jl` (10 testsets).
- Tests: 428/428 pass on Julia 1.10.

### v1.5.1 — schema bump + Molly gating + Pluto refresh (2026-04-27)

Polish pass following v1.5.

- **Schema version bump 0.1.0 → 0.2.0**. `MDSpec.schema_version` and the
  `const` in `schema.json` both now read `"0.2.0"`. Real
  `_migrate_v0_1_to_v0_2` registered in `Migrations.jl`: fills nullable
  defaults for `system.source.ligand_smiles`, `system.solvent.membrane`,
  and `force_field.lipid` so old transcripts forward-compatibly upgrade.
  Existing fixtures migrated in place; default `target` of
  `migrate_spec_json` advanced to `"0.2.0"`.
- **MollyBackend rejects v1+ stages explicitly**. `validate_spec` now
  emits a per-stage error pointing at OpenMMBackend for `FEPStage` /
  `REMDStage` / `MetadynamicsStage`, and a separate error for
  `LipidBilayer` membrane systems. Replaces the generic "missing
  features" line for these cases.
- **Router auto-prefers OpenMM** for any spec demanding `:alchemy`,
  `:remd`, `:metadynamics`, `:membrane`, `:biased_sampling`,
  `:multi_replica`, or `:plumed` — even when the only thing Molly is
  missing is one of these.
- **Pluto notebook refresh**. Top-of-page banner lists v0.2.0 schema
  + 5 stage types + 5 source types + lipid bilayer note. Section 2
  (`## 2. Transpile`) gains a `provider_kind` selector for
  `recorded` / `anthropic` / `local` so the offline iteration path
  works without environment manipulation.
- **New test file**: `test/molly_gating_test.jl` — 6 testsets pinning
  the Molly rejection messages + the Router preference for OpenMM
  on v1+ features.
- **Tests**: 401/401 pass on Julia 1.10 (offline; +5 with
  `CRUCIBLE_RUN_OPENMM=1`).

### v1.5 — enhanced sampling + membranes (2026-04-26)

The remaining items from the v1+ deferred list, partly closed.

- **`REMDStage` (replica-exchange MD)**. Temperature ladder + exchange-attempt period; renderer emits real `openmmtools.multistate.ParallelTemperingSampler` code that writes `remd.nc` (multistate netcdf) for downstream WHAM/MBAR. Validation rule enforces strictly increasing T and warns on aggressive ratios that hurt acceptance.
- **`MetadynamicsStage` + `CollectiveVariable`** (distance / angle / dihedral / RMSD). Renderer emits an `openmm-plumed` `PlumedForce` block with auto-generated `METAD` line (well-tempered + bias-factor by default). Schema covers up to 8 CVs per stage. Validation rules check CV atom-group counts, RMSD reference presence, and the well-tempered/bias-factor coherence.
- **Membrane / lipid bilayer support**. `LipidBilayer` (composition + n_lipids + chol_mol_fraction) attaches to `SolventSpec.membrane`; `ForceFieldSpec.lipid` enum allowlist covers `:charmm36_lipid`, `:lipid21`, `:slipids`. The OpenMMBackend renderer auto-switches to `MonteCarloMembraneBarostat` (XYIsotropic, ZFree) for NPT stages in membrane systems — physically-correct semi-isotropic coupling, no user action needed. New `_rule_membrane_coherence` semantic rule.
- **Multi-GPU advisor candidates**: `A100x4`, `A100x8`, `L4x4` rows in `benchmarks.toml` with `default_gpu_count` + `multi_gpu_factor` fields. Advisor scales runtime by parallelism factor when the spec demands replicas (REMD), making multi-GPU instances cost-competitive only when actually utilized. New warning when `n_replicas > 1`.
- **`Stage` count → 5**: `MinimizeStage`, `DynamicsStage`, `FEPStage`, `REMDStage`, `MetadynamicsStage`. `OpenMMBackend.supported_features` now includes `:remd`, `:metadynamics`, `:plumed`, `:multi_replica`, `:membrane`.
- **Three new examples**: `examples/remd_protein_folding.jl` (8-replica T-REMD), `examples/membrane_protein.jl` (GPCR in POPC), and the existing `protein_ligand_fep.jl` is now joined by these for a complete sampling-method coverage.
- **Three new test files**: `remd_test.jl` (8 testsets), `metadynamics_test.jl` (7 testsets), `membrane_test.jl` (10 testsets). 386/386 tests pass on Julia 1.10.

### v1.0 — heavy lifts (2026-04-26)

The deferred v1 items shipped in one push.

- **Real `OpenFFParameterizer` (SMILES → AMBER topology)**. Subprocess implementation via `src/ligand/parameterize_openff.py`: SMILES → RDKit conformer → OpenFF Sage typing → AM1-BCC charges → Interchange → `ligand.parm7` / `ligand.rst7` / `ligand.pdb`. No PythonCall dep added — keeps the package light per the project preference. `parameterizer_available()` probes the configured python without exploding on the user.
- **`:smiles` SystemSource type**. Pure-ligand path. `OpenMMBackend.prepare()` invokes the parameterizer when `source.type == :smiles` and the renderer loads the AMBER files. The BYO-topology gate goes away for ligand-only systems.
- **`:protein_ligand` SystemSource type**. Combined protein + small-molecule path. PDBFixer fetches + repairs the protein, OpenFF parameterizes the ligand from SMILES, `SMIRNOFFTemplateGenerator` (openmm-forcefields) registers the ligand against the protein force field. All at script-runtime — no prepare-time round-trip needed. Requires `openff-toolkit + openmmforcefields` at execution.
- **`FEPStage` (alchemical free-energy)**. New stage type with `kind ∈ (:decouple, :annihilate)`, `lambda_windows::Vector{Float64}`, `target_selection`, `duration_per_window_ns`. Schema entry, JSON round-trip, semantic gates (lambda monotonic, range [0,1], NPT-pressure required). Renderer emits real `openmmtools.alchemy.AbsoluteAlchemicalFactory` code that runs each λ window and writes a `u_kln.csv` for downstream MBAR analysis. `:alchemy` is now in `OpenMMBackend.supported_features`.
- **`WebRenderer` real implementation + `crucible serve`**. HTTP.jl-based frontend (no Genie dep). Endpoints: `GET /`, `GET /health`, `POST /api/transpile|validate|render|advise|parameterize`. Single-page UI with paper paste / spec edit / backend choice / cloud advise — all server-rendered. CLI: `crucible serve --host --port`.
- **CLI: `parameterize` + `verify`**. `crucible parameterize <smiles> --out <dir> [--ff openff_sage_2_2_0]` runs the OpenFFParameterizer directly. `crucible verify <spec> [--backend X]` runs gates 1-3 + render in one shot, exits non-zero on failure.
- **Two new semantic rules**: `_rule_smiles_source_coherence` (SMILES sources need ligand_smiles + non-:user_supplied ligand FF + a 4-char pdb_id for protein_ligand), `_rule_fep_lambda_monotonic` (λ windows strictly increasing, bracketing [0,1], NPT requires pressure).
- **Examples**: `examples/from_smiles.jl` (ethanol-in-vacuum, end-to-end), `examples/protein_ligand_fep.jl` (1ubq + p-cresol decoupling FEP scaffolding).
- **Tests**: `test/smiles_test.jl` (12 assertions for IR + validation + render), `test/fep_test.jl` (8 assertions for round-trip + schema + render), `test/web_test.jl` (6 endpoints, free-port server boot/teardown). `parameterizer_test.jl` rewritten for the real subprocess implementation.
- **Schema**: SystemSource now allows `ligand_smiles` and the source `type` enum gains `smiles` + `protein_ligand`. Added `free_energy` kind to the protocol oneOf with full property list.

### v0.5 (2026-04-26)

- **Crucible CLI** (`bin/crucible`): 7 subcommands — `transpile`, `validate`, `render`, `advise`, `summarize`, `diff`, `walkthrough`. Pipeline usable from a shell without Pluto.
- **`MarkdownRenderer`**: GFM-rich rendering of `MDSpec`, `ValidationReport`, `SpecDiff` for CLI / PR descriptions / README.
- **`diff_specs(a, b)` + `crucible diff`**: structured per-field diff between two specs. The training signal for the option-3 fine-tune (LLM-emitted vs. user-corrected pairs).
- **`docs/IR.md`** auto-generated from `schema.json` via `tools/regenerate_docs.jl`.
- **`examples/lifecycle.jl`**: full option-3 flywheel demo (transpile → log → user-edit → diff → log → JSONL).
- **`tools/regenerate_fixtures.sh`**: drift check for the recorded LLM fixture against a live Anthropic call.
- **`tools/check.sh`**: pre-commit gate runner — `Pkg.test()` + IR docs drift + fixture drift.
- **NVE ensemble support** (VerletIntegrator) and **CHARMM36m** rendering coverage.
- **Schema-version migration framework** (`src/spec/Migrations.jl`) so future schema bumps preserve historical transcripts.
- **`KineticsSpec` + `KineticsBackend` stub**: proof the SimBackend abstraction extends past MD; v1+ wires Catalyst.jl in.
- **`SECURITY.md`** with the project's secrets-handling policy.
- **`docs/VERIFICATION_ROUTINE.md`** documenting what the 2-week verification routine should do.
- **Schema tightening**: NPT/NVE invariants enforced at Gate 1 (was Gate 2-only).
- **JSONL transcript export** for sharing the data flywheel across machines.
- **CHANGELOG / README / AGENTS.md / LICENSE** all polished.

### v0.4 / v1 partial (2026-04-26)

- **PDBFixer auto-build path** (v1 #1): `:pdb_fetch` source type now downloads a PDB by ID, fixes missing atoms/residues, adds hydrogens at pH 7, solvates with the requested water model, and saves the prepared system. Canonical-residue protein systems only — ligand systems still require BYO topology.
- **Real trajectory output**: `DCDReporter` per stage at the requested observable stride (was emitting comments).
- **Real observable computation**: post-run `mdtraj` block computes RMSD / RMSF / Rg from the trajectory and writes CSV files. Wrapped in `try/except` so the script still runs without `mdtraj` installed.
- **ArxivAdapter PDF download**: when `pdftotext` is on PATH, the adapter downloads the PDF and extracts the full body text (was abstract-only).
- **PDB column-alignment fix**: `test/fixtures/alanine_dipeptide.pdb` regenerated to strict PDB v3 column rules; OpenMM now loads it cleanly.
- **OpenMMBackend renderer**: relaxed topology requirement — PDB-only systems no longer demand a separate `.prmtop`.

### v0.3 (2026-04-26)

- `.woodpecker.yml` matrix on Julia 1.10 + 1.11; consolidated to Woodpecker (GHA + Forgejo Actions removed)
- Live OpenMM smoke in CI via a separate pipeline step that installs OpenMM in a venv and runs `Pkg.test()` with `CRUCIBLE_RUN_OPENMM=1`
- `Manifest.toml` committed for reproducible builds
- `poppler-utils` installed in CI, real `PDFAdapter` test
- `examples/walkthrough.jl` end-to-end demo using `RecordedProvider` (no API key needed)

### v0.2 (2026-04-26)

- `TranscriptStore` (DuckDB-backed append-only log) — Phase A of the option-3 fine-tune flywheel
- `RecordedProvider` for deterministic LLM tests without consuming API tokens
- Live `AnthropicProvider` smoke gated on `CRUCIBLE_RUN_ANTHROPIC=1` + `ANTHROPIC_API_KEY`
- Pluto Gate 5: `@bind run_button` gating prevents accidental production runs on spec edits
- `PlutoUI`, `HypertextLiteral`, `DuckDB`, `DBInterface`, `Dates` added to `Project.toml`

### v0.1 (2026-04-26)

- Renderer correctness: integers/floats are now text-formatted (was emitting raw bytes via `write(io, ::Number)`)
- OpenMM restraints: real `CustomExternalForce` honoring selection (heavy_atoms / backbone / ca) and harmonic k; auto-removed at end of stage
- Live `run!` for both backends via subprocess (no PythonCall dep added — keeps the package light)
- Validation Gate 4 (`gate_preview`): rendered scripts honor `CRUCIBLE_PREVIEW_STEPS` env var, every dynamics stage wrapped in `_cap()`; preview run parses log for NaN/Infinity/blowup
- Molly's `supported_features` now advertises `:constraints` so the Router dispatches implicit-solvent NVT specs to Molly
- Alanine-dipeptide test fixture + integration testset (live OpenMM smoke gated on `CRUCIBLE_RUN_OPENMM=1`)
- CI: consolidated to Woodpecker only (`.woodpecker.yml` matrix on Julia 1.10 + 1.11). GitHub Actions and Forgejo Actions removed
- 60 tests passing on both Julia 1.10 and 1.11

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
