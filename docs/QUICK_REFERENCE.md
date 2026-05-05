# Quick reference — every CLI surface

One-page cheatsheet for the Crucible CLI surface that's accumulated
through the v0.x → v1.7x development run. Organized by tier; deeper
docs linked under each section.

This doc is the *what's the syntax again?* lookup. For *why does X
exist?*, see [`docs/USER_PROFILES.md`](USER_PROFILES.md). For *how
do I extend X?*, see [`docs/POWER_USERS.md`](POWER_USERS.md).

## Tier 0 — `crucible` (Julia CLI)

The original 30-subcommand workhorse. Lives at `bin/crucible`.

| Subcommand | One-line |
|---|---|
| `crucible transpile --paper FILE` | LLM → MDSpec JSON |
| `crucible validate FILE` | Run gates 1+2 against a spec JSON |
| `crucible health FILE` | Gates 1+2+3 + lint + coverage; one report |
| `crucible render FILE --backend openmm\|molly\|gromacs` | MDSpec → runnable script |
| `crucible run FILE --workdir DIR` | Render + execute end-to-end |
| `crucible advise FILE` | GCP/AWS/Azure cloud-cost recommendation |
| `crucible doctor` | Smoke-check the install |
| `crucible templates list / init NAME` | 13 starter MDSpecs |
| `crucible diff A.json B.json [--intent]` | Structural / intent diff between specs |
| `crucible coverage FILE` | Provenance coverage + missing-paths |
| `crucible lint FILE` | Lint findings (extends gate 2) |
| `crucible explain FILE` | Human-readable summary of a spec |
| `crucible cite FILE` | Generate BibTeX entry for a transpiled paper |
| `crucible upgrade FILE --target VERSION` | Walk the migration chain to a target version |
| `crucible serve` | HTTP API server |
| `crucible info` | Allowlists + version + supported features |
| `crucible bench` | Internal benchmark harness (different from `benchmark` Python subcommand) |
| `crucible fmt FILE [--in-place]` | Pretty-print a spec |
| `crucible plot WORKDIR` | Generate trajectory plots |
| `crucible events WORKDIR` | Read the event log from a run |
| `crucible analyze WORKDIR` | Post-run analysis pipeline |
| `crucible trajstat WORKDIR` | Compute trajectory statistics |
| `crucible snapshot WORKDIR ARCHIVE` | Snapshot a workdir to a tarball |
| `crucible restore ARCHIVE DIR` | Restore from a snapshot |
| `crucible audit-transcripts` | Audit the local transcript store |
| `crucible export-jsonschema` | Emit `src/spec/schema.json` to stdout |
| `crucible import-jsonl FILE` | Bulk-import transcripts |
| `crucible parameterize SMILES` | Parameterize a ligand via OpenFF |
| `crucible verify FILE` | Cross-checker against a known-good fixture |
| `crucible walkthrough` | Launch the Pluto walkthrough notebook |
| `crucible hekate {bootstrap-venue, create-slot, publish-event, doctor}` | AT Protocol publisher |

Full source: [`src/cli/CLI.jl`](../src/cli/CLI.jl).

## Tier 1 — `python -m crucible` (top-level Python)

Pure-Python ops that don't shell out. From v1.24's bindings.

| Subcommand | One-line |
|---|---|
| `python -m crucible validate FILE` | Pure-Python Gates 1+2 |
| `python -m crucible lint FILE` | Lint + provenance coverage |
| `python -m crucible templates list / init NAME` | Same 13 templates |
| `python -m crucible migrate FILE [--target VER]` | Schema migration |
| `python -m crucible spec-describe [--format json]` | Allowlists + schema version |
| `python -m crucible corpus …` | Passthrough — see Tier 2 |
| `python -m crucible benchmark …` | Passthrough — see Tier 3 |

## Tier 2 — `python -m crucible corpus`

Whitepaper corpus with OpenAlex + DuckDB. From v1.29 + v1.42 + v1.48 + v1.65 + v1.67.

| Subcommand | One-line |
|---|---|
| `crucible corpus fetch NAME [--concept C] [--since YEAR] [--limit N]` | Fetch one author's works |
| `crucible corpus fetch-batch FILE [...]` | Bulk-fetch from a names file |
| `crucible corpus papers --author NAME [--since YEAR]` | List papers by author |
| `crucible corpus authors [--limit N]` | List local-DB authors |
| `crucible corpus coauthors AID` | List coauthors of an OpenAlex author ID |
| `crucible corpus stats` | Row counts per table |
| `crucible corpus query "SELECT …" [--format jsonl\|table]` | Read-only SQL escape hatch |
| `crucible corpus ui` | Streamlit GUI (opt-in `[corpus,ui]` extra) |

Default DB: `~/.local/share/crucible/corpus.duckdb` (override with `--db PATH`).

## Tier 3 — `python -m crucible benchmark`

Hallucination benchmark + longitudinal data layer. v1.31 → v1.76.

| Subcommand | One-line |
|---|---|
| `crucible benchmark list / status` | Seed-set listing + verification progress |
| `crucible benchmark add --paper-id X --doi Y --title Z` | Append a `needs_verification` stub |
| `crucible benchmark verify --paper-id X` | Interactive axis-by-axis verification |
| `crucible benchmark run [--mock] [--corpus-db X] [--full-text]` | Score the seed set |
| `crucible benchmark report RUNS.jsonl [--out FILE] [--brief] [--trends-db X]` | Render markdown |
| `crucible benchmark publish [--mock] [--out FILE / --to-docs] [--brief]` | One-shot run → report |
| `crucible benchmark trends RUNS.db [--paper-id X]` | Per-paper rollup (JSON) |
| `crucible benchmark runs-stats RUNS.db [--provider X]` | Per-axis + per-provider accuracy (JSON) |
| `crucible benchmark runs-stats-md RUNS.db` | Same, markdown |
| `crucible benchmark export-jsonl RUNS.db [--out X] [--include-paper-text] [--since DATE] [--paper-id X] [--provider X]` | JSONL dump (option-3 flywheel feeder) |
| `crucible benchmark compare LEFT.db RIGHT.db` | Per-paper accuracy delta |
| `crucible benchmark watch RUNS.db [--interval N]` | Live tail (poll for new rows) |
| `crucible benchmark ui [--runs-db X] [--port N] [--headless]` | Streamlit dashboard (opt-in `[ui]` extra) |

## Tier 4 — workspace tools

CI-grade scripts under `tools/`. Not user-facing day-to-day, but
worth knowing for the maintainer.

| Script | One-line |
|---|---|
| `tools/check_workspace.py [--verbose]` | 7-check aggregator (schema-version × 2, fixtures, manifest, pydantic, doc-links, profile-shape) |
| `tools/check_doc_links.py [--verbose]` | Verify every `[text](path)` link resolves |
| `tools/check_profile_shape.py [--verbose]` | Enforce the 6-section playbook shape on `USER_PROFILE_*.md` |
| `tools/release_summary.py [--prefix X] [--since X] [--latest N]` | Compact one-line-per-version CHANGELOG view |
| `tools/install_precommit.sh [--force\|--dry-run]` | Opt-in pre-commit hook |
| `tools/migration_smoke.jl` | Walk every fixture through every migration target (Julia) |
| `tools/cross_lang_roundtrip.jl` | Read JSONL on stdin; round-trip via Julia loader |
| `tools/repair_manifest.sh` | Regenerate `Manifest.toml` for the local Julia version |
| `tools/sync-lexicons.jl` | Vendor `app.hekate.*` lexicons from `~/Projects/hekate` |
| `tools/regenerate_docs.jl` | Auto-generate `docs/IR.md` from `schema.json` |

## Environment variables

The most-load-bearing knobs:

| Variable | What |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic LLM provider auth |
| `CRUCIBLE_LOCAL_ENDPOINT` | OpenAI-compatible local LLM URL |
| `CRUCIBLE_LOCAL_MODEL` | Model name to send to the local endpoint |
| `CRUCIBLE_LOCAL_API_KEY` | API key for the local endpoint (default: `EMPTY`) |
| `CRUCIBLE_OPENALEX_EMAIL` | Polite-pool email for OpenAlex |
| `CRUCIBLE_SEED` | Seed for backend integrators |
| `CRUCIBLE_PRECISION` | Backend numerical precision (`single` / `mixed` / `double`) |
| `CRUCIBLE_CHECKPOINT_PERIOD_PS` | Checkpoint cadence in ps |
| `CRUCIBLE_RESUME_FROM` | Path to a checkpoint to resume from |
| `CRUCIBLE_PREVIEW_STEPS` | Override the preview-run step count |
| `CRUCIBLE_HEKATE_PUBLISH_EVENTS` | Set to `1` to actually publish AT Protocol events (default: dry-run) |
| `XDG_DATA_HOME` | Override the default DuckDB store location |
| `XDG_CACHE_HOME` | Override the PDF-text cache location |
| `CRUCIBLE_BIN` | Override the path to the Julia CLI binary (Python `cli_bridge`) |

## Common workflows

The combinations that show up most:

### "Reproduce a paper" (grad student)

```bash
crucible transpile --paper methods.txt --out spec.json
crucible health spec.json
crucible render spec.json --backend openmm > run.py
```

### "Audit a published paper" (reproducibility researcher)

```bash
crucible transpile --paper methods.txt --out spec.json
crucible coverage spec.json   # see assumed / missing fields
```

### "Set up the corpus from the campaign personas" (maintainer)

```bash
crucible corpus fetch-batch examples/persona_names_tier1.txt \
    --concept "molecular dynamics" --since 2018
crucible corpus stats
```

### "Score the benchmark + publish report" (eval)

```bash
crucible benchmark publish --corpus-db ~/.local/share/crucible/corpus.duckdb \
    --llm-model claude-opus-4-7 --to-docs
```

### "Compare two release-tag snapshots" (regression check)

```bash
crucible benchmark compare runs/v1.40.duckdb runs/v1.74.duckdb
```

### "Live-monitor a long benchmark" (publish + watch)

In terminal A:
```bash
crucible benchmark publish --corpus-db corp.duckdb --to-docs
```

In terminal B:
```bash
crucible benchmark watch corp.duckdb --interval 5
```

### "Pre-commit consistency" (maintainer)

```bash
bash tools/install_precommit.sh
# now `git commit` runs check_workspace.py automatically
```

## See also

- [`docs/USER_PROFILES.md`](USER_PROFILES.md) — task-oriented
  onboarding for specific adopter personas; pick a profile for
  the workflow that matches your goal.
- [`docs/HOW_TO_READ.md`](HOW_TO_READ.md) — reading-oriented
  guides for navigating the codebase.
- [`docs/POWER_USERS.md`](POWER_USERS.md) — extension contributor
  guide.
- [`README.md`](../README.md) — landing page; the
  always-on-but-shorter version of the install + smoke instructions
  here.
