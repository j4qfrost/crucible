# Changelog

## Unreleased

### v1.91 — strategy feedback loop + sequencing/qualification rubrics (2026-05-22)

Closes three gaps surfaced in a strategy-doc audit. Docs-only; no
code, schema, or test changes.

- **`docs/FEEDBACK_LOOP.md`** (new) — the maintenance contract for
  the plan + campaign docs. Documents the monthly signal sweep +
  quarterly strategy review (pinned to the Week-13 / Week-26 gate
  dates the plans already ship with), which signals get collected
  (all already named in the existing docs), how each plan doc's
  revision surface differs (ADOPTION_PLAN decision gates,
  COMMERCIAL_VALIDATION_PLAN kill criteria + spend tranches,
  CAMPAIGN KPI thresholds, USER_PROFILE failure modes), and the
  branch → commit → CHANGELOG → checks recording ritual. Why: the
  plans were written once with no documented path for adopter
  evidence to revise them — the Frozen Plan failure mode.
  Cross-linked from `docs/ADOPTION_STRATEGY_PLAYBOOK.md` and
  `docs/ADOPTION_PLAN.md`.
- **`docs/COMMERCIAL_VALIDATION_PLAN.md`** — added a warm-lead
  qualification rubric next to the spend-tranche table. The "≥3
  warm leads" Tranche-2 trigger and the Phase A / kill-criteria
  counts all key off "warm" but the term was undefined. Rubric
  scores cold / lukewarm / warm / hot on observable actions
  (replied / held a call / requested follow-up / named budget or
  timeline / introduced onward), with warm = two-or-more criteria
  and a 6-week decay rule.
- **`docs/CAMPAIGN_2026Q2.md`** — added an email-sequencing
  framework after the cold-email templates. Defines a three-touch
  per-recipient sequence (first email → Day 5–7 follow-up →
  8–12-week milestone re-engage), cadence rules, and a touch-budget
  table proving the sequence stays inside the existing 35-email /
  13-week cap (it trades breadth for depth, never adds volume).

### v1.88 — live local-LLM smoke (closes #3) (2026-05-05)

Opt-in test module that exercises `LocalOpenAIProvider` against a
real running OpenAI-API-compatible LLM server, complementing the 8
unit tests (which inject `http_post=` and prove only the parser).

- **`python/tests/test_local_llm_live.py`** — 2 tests; gated on
  `CRUCIBLE_LIVE_LOCAL_LLM=1` so the regular suite still skips
  cleanly.
- Configurable via the existing `CRUCIBLE_LOCAL_ENDPOINT` /
  `CRUCIBLE_LOCAL_MODEL` env vars (defaults: localhost Ollama,
  `qwen2.5-coder:3b`).
- Module-scoped fixture probes `/v1/models` first; skips
  gracefully if the endpoint isn't reachable, so accidentally
  setting the env var on a box without Ollama doesn't break CI.
- Tests:
  1. Round-trip a real Methods paragraph through the provider;
     accept either `out.ok` (schema-valid) or fail-soft
     (`spec is None` + non-empty `raw_response`). Asserts the
     fail-soft contract — no exception escapes regardless of
     model output quality.
  2. Unknown model name → fail-soft, with the URL or "model" /
     "not found" surfaced in the raw_response.
- Verified live against snowman's Ollama (`qwen2.5-coder:3b`) —
  both tests pass in ~21 s; default suite is **220 passed,
  2 skipped**.

### v1.87 — `tools/precompile_offline_bundle.sh` (closes #2) (2026-05-05)

Closes the doc-to-deployment gap from `docs/AIR_GAPPED.md`. Until
now an operator following the doc had to hand-execute six tar
commands; this script makes the bundle a single command.

- **`tools/precompile_offline_bundle.sh`** — bundles, in order,
  six layers (each independently skippable):
  1. Python wheels via `pip download python[corpus,llm-anthropic]`
  2. Julia depot — uses a *throwaway* `JULIA_DEPOT_PATH` rooted in
     staging so we capture only the Project's transitive deps
     (the user's full `~/.julia` is way too large).
  3. OpenMM + scientific Python stack (optional `--openmm`)
  4. Ollama model weights (repeatable `--ollama-model` flag)
  5. Source tree via `git archive` (clean — no `.git/`, no untracked)
  6. `MANIFEST.txt` with timestamp, HEAD SHA, host, and SHA256
     sums of every artifact
- **`tools/verify_offline_bundle.sh`** — companion script. Unpacks
  the bundle into a scratch dir, sha256-checks every file, asserts
  source/Project.toml is intact, and runs the workspace check
  against the unpacked tree. Run before scp'ing across the
  air-gap; exit 0 = good to ship.
- Auto-names the output (`crucible-airgap-vN.NN-YYYYMMDD.tar.gz`)
  from CHANGELOG.md if `--out` is omitted.
- Smoke-tested end-to-end on snowman:
  - source-only bundle: 560 KB, 243 SHA256 sums verified
  - Python-wheels bundle: 26 MB, 22 wheels, 265 SHA256 sums verified

### v1.86 — wire air-gap audit into GHA CI (2026-04-29)

Adds a new `air-gap-audit` job to `.github/workflows/ci.yml` so
the egress baseline + doctor `--offline` audits gate every PR
automatically, not just on operator-run audits.

- Job sets up Python 3.11, installs `python[llm-anthropic]`, and
  runs `tools/audit_offline.sh --skip-julia`.
- Runs in parallel with the Julia matrix (no `needs:` chain) so
  it doesn't block the slower path.
- Fails the PR if any of: workspace consistency drifts, a new
  outbound call site lands without a baseline bump + AIR_GAPPED.md
  update, or the runtime env is air-gap-hostile (e.g. someone
  hard-codes `ANTHROPIC_API_KEY` into a default).
- Pure-Python so finishes in tens of seconds; pairs with the
  existing Julia matrix as a separate fast lane.

### v1.85 — `tools/audit_offline.sh` (composite air-gap gate) (2026-04-29)

A single one-shot gate that composes v1.81 (egress inventory),
v1.82 (Python doctor), v1.83 (egress baseline check), and v1.84
(Julia doctor) into one command. Designed for operator
pre-deployment, CI nightlies, and compliance reviews.

- **Steps** (sequential, all run; failures tallied):
  1. `tools/check_workspace.py` (8 invariants incl. egress baseline)
  2. `tools/inventory_egress.py` (full categorized dump)
  3. `python -m crucible doctor --offline`
  4. `crucible doctor --offline` (Julia; auto-skipped if absent)
- Flags: `--skip-julia` (Python-only CI), `--quiet` (failures only).
- Auto-detects `python/.venv/bin/python` to use the real install,
  falls back to system python.
- Exit code = number of failed steps.
- Verified end-to-end: clean shell exits 0; setting
  `ANTHROPIC_API_KEY=sk-test` produces a step-3 failure with
  exit 1.
- `docs/AIR_GAPPED.md` "Verification scripts" section refactored
  to point to `audit_offline.sh` as the recommended composite gate.

### v1.84 — Julia `crucible doctor --offline` (2026-04-29)

Adds the `--offline` flag to the existing Julia-side `crucible
doctor` (the v1.82 Python equivalent has shipped; this brings the
two surfaces into parity so a single audit story covers both
runtimes).

- **`crucible doctor --offline`** — after the existing diagnostic
  (Python/OpenMM/OpenFF/GPU probes) emits an "Air-gap audit"
  section. Errors on `ANTHROPIC_API_KEY` set or
  `CRUCIBLE_HEKATE_PUBLISH_EVENTS=1`; warns on
  `CRUCIBLE_OPENALEX_EMAIL` set or `CRUCIBLE_LOCAL_ENDPOINT` not
  pointing at localhost / private-net (10./172.16-31./192.168.).
- Exit code = number of errors (so CI can treat as a hard gate;
  warnings are informational and don't fail).
- Help text in `--help` now shows `[--offline]`.
- Parses cleanly under Julia 1.12.

### v1.83 — egress baseline gate (8th workspace check) (2026-04-29)

Wires `tools/inventory_egress.py` (v1.81) into
`tools/check_workspace.py` so the air-gap commitment becomes a
hard gate at pre-commit/CI time rather than an audit run by hand.

- **`tools/baselines/egress.json`** — per-category counts of every
  outbound-network call site currently in the codebase: 7 stdlib
  urllib, 2 anthropic_sdk, 10 julia_HTTP. Schema-versioned for
  future extension.
- **`_check_egress_baseline()` in `check_workspace.py`** — runs
  `inventory_egress.py --format json`, tallies by category, and
  fails if any category has *more* sites than the baseline.
  Decreases pass silently (improvements). Adding a new egress site
  forces a deliberate baseline bump + an `AIR_GAPPED.md` update —
  the audit can no longer drift unobserved.
- Verified end-to-end: simulating "urllib +1" produces
  `✗ egress_baseline: urllib: 7 > baseline 0` and exit 1.
- All 8 workspace checks pass; **220/220 pytest** unchanged.

### v1.82 — `crucible-py doctor` (Python install + air-gap audit) (2026-05-05)

Python equivalent of the Julia `crucible doctor`, plus an
`--offline` mode that audits the running env against the v1.80
AIR_GAPPED.md commitments.

- **`python -m crucible doctor`** — pure-Python smoke check;
  reports installed-version per base dep (pydantic, jsonschema)
  + each optional extra (duckdb, streamlit, anthropic) + live
  `SCHEMA_VERSION` + `CRUCIBLE_PROVIDER` config.
- **`python -m crucible doctor --offline`** — enforces air-gap
  invariants:
  - **Errors** on `ANTHROPIC_API_KEY` set (forbidden) or
    `CRUCIBLE_HEKATE_PUBLISH_EVENTS=1` (AT Protocol publishing
    enabled).
  - **Warns** on `CRUCIBLE_OPENALEX_EMAIL` set (corpus fetch
    would hit OpenAlex) or `CRUCIBLE_LOCAL_ENDPOINT` not pointing
    to localhost / private-net.
  - **OK** when all checks are air-gap-friendly.
- `--format json` for CI integration. Exit code = error count
  (warnings don't fail).
- 6 new tests; **220/220 pytest** (was 214).

### v1.81 — `tools/inventory_egress.py` (static-analysis audit) (2026-05-05)

Companion to v1.80's `AIR_GAPPED.md`: a static-analysis script that
catalogs every potential outbound-network call in the codebase.
Useful for the air-gapped audit when a new dep adds an opaque
external touchpoint — diff the inventory before vs. after to see
exactly what shifted.

- **`tools/inventory_egress.py`** — pattern-matches Python + Julia
  source for outbound calls across 10 categories: stdlib urllib,
  third-party requests / httpx, Anthropic + OpenAI SDKs, Julia
  HTTP.jl + Downloads, Pkg server, subprocess to curl/wget, DNS
  lookups. Skips comment lines (don't false-positive on docs that
  describe disabled paths). Skips `.venv`, `__pycache__`,
  `node_modules`, `build`, `dist`. Two output formats: text
  (grouped by category for human reading) + JSON (for
  machine-readable diffs).
- **`--strict`** flag (forward-looking): exits non-zero on any
  uncategorized hit. The current pattern set covers everything
  in the codebase; if a new pattern shows up, the strict gate
  fails and we add a category.
- **First-run inventory:** 19 sites total — 2 anthropic SDK
  (LLM call), 10 Julia HTTP.jl (input adapters + atproto + LLM),
  7 stdlib urllib (corpus OpenAlex + corpus full-text PDF +
  Python LocalLLM + 1 test mock). Every site maps cleanly to an
  entry in the AIR_GAPPED.md external-touchpoint table.

### v1.80 — `LocalOpenAIProvider` + `docs/AIR_GAPPED.md` (2026-05-05)

Two slices that compose into the locked-down-research story.

- **`python/crucible/llm/local.py`** — `LocalOpenAIProvider`. Pure
  stdlib (urllib); no third-party HTTP dep. Hits
  `/v1/chat/completions` with `response_format` binding the
  canonical MDSpec schema (matches the Julia-side `LocalProvider`
  contract; OpenAI-compatible servers handle this directly).
  Fail-soft on connection refused / non-JSON / empty choices /
  invalid spec content. Constructor accepts an injectable
  `http_post=` for tests + falls back to `CRUCIBLE_LOCAL_*` env
  vars (same names as the Julia side).
- **`docs/AIR_GAPPED.md`** — comprehensive zero-egress deployment
  guide. Three threat-model tiers (on-prem / air-gapped install /
  air-gapped + audit); complete external-touchpoint inventory
  with per-touchpoint neutralization (PyPI, JuliaHub,
  conda-forge, OpenAlex, Anthropic API, Hugging Face, GitHub
  CDN, DOI resolvers, AT Protocol). Step-by-step air-gapped
  install (mirror Python wheels + Julia depot + OpenMM env + LLM
  weights). Runtime configuration template + zero-egress
  verification with `tcpdump`. Determinism table per-layer. Three
  update paths. Honest "when this isn't enough" section
  addressing the poisoned-model-weights threat.
- 8 new tests for `LocalOpenAIProvider`. **214/214 pytest**
  (was 206). 7 workspace checks green.

### v1.79 — native Python LLM provider (2026-05-05)

Companion to the v1.24 cli_bridge: pure-Python `LLMProvider` so
headless Python services don't need to shell out to Julia for the
transpile call. Same contract as the Julia-side
`Crucible.LLMProvider`; cross-language consistency continues to be
the schema's responsibility.

- **`python/crucible/llm/`** — new module:
  - `provider.py`: `LLMProvider` ABC + `TranspileResult` dataclass +
    `MockLLMProvider` (deterministic, no deps, returns named
    templates).
  - `anthropic.py`: `AnthropicLLMProvider` using the `anthropic`
    SDK with structured-output tool-use binding `schema.json` as
    the `emit_mdspec` tool's `input_schema`. Fail-soft on rate
    limits / network / invalid output. Constructor accepts an
    injectable `client=` for tests.
  - `__init__.py`: re-exports the public API.
- **`python/pyproject.toml`** — new optional extra
  `[llm-anthropic] = ["anthropic>=0.40"]`. The base interface has
  no third-party deps.
- 12 new tests (5 mock + 7 anthropic-with-mocked-client). **206/206
  pytest** (was 194).
- The local-LLM (Ollama / vLLM / llama.cpp) provider is queued for
  v1.80; same shape, different transport.

### v1.78 — refactor: extract `seed_patcher` from `benchmark/cli.py` (2026-05-05)

`benchmark/cli.py` had grown to 943 lines via 36 accreted slices.
Most of the bulk is short cmd_* dispatchers, but ~110 lines were a
text-munging algorithm (the `_patch_entry` regex + indent-walking
that powers `benchmark verify`) that's distinct in shape from the
surrounding CLI dispatch.

- **`python/crucible/benchmark/seed_patcher.py`** — new module.
  `patch_entry(text, paper_id, new_values, verified_by, notes_extra)`
  + four small helpers (`_replace_expected_protocol`,
  `_strip_status_and_verified_by`, `_inject_status_lines`,
  `_append_to_notes`). Same algorithm; cleaner shape (each helper
  does one thing instead of one long function).
- **`benchmark/cli.py`** — `_patch_entry` is now a one-line
  re-export of `seed_patcher.patch_entry` so existing imports +
  tests keep working unchanged. Top-of-file docstring updated with
  a section map (Seed-set / Run+report / Data-layer reads / UI).
- Net change: **cli.py 943 → 840 lines (-103); seed_patcher.py
  140 new lines**. The two-file shape is more navigable than the
  one-file shape was.
- 194/194 pytest unchanged. The `_patch_entry`-targeting tests in
  `test_corpus_benchmark_bridge.py` still pass via the re-export.

### v1.77 — `release_summary.py --by-theme` (grouped CHANGELOG view) (2026-05-05)

Groups versions by inferred theme so the post-v1.40 changelog
becomes scannable by area rather than just by date.

- **`tools/release_summary.py --by-theme`** — title-keyword
  classifier with 11 themes ordered by relevance:
  Schema / IR, Benchmark layer, Corpus tier, Adoption / docs,
  CI / tooling, LLM / providers, AT Protocol / hekate,
  Python bindings / packaging, Renderers / backends,
  Validation gates / lint, UI / dashboard, then Misc.
- First-match-wins keyword logic (e.g. "schema 0.4.0" hits
  Schema / IR before reaching Benchmark layer's "axis"). Ordered
  list per theme means tweaking is a single-line edit.
- Composes with the existing `--prefix` / `--since` / `--latest`
  filters: `release_summary.py --since v1.40 --by-theme` shows the
  themed view of just the recent run.
- Useful sanity check for "did I ship balanced work?" — a quick
  glance reveals if one theme dominates an arbitrary release window.

### v1.76 — Streamlit dashboard for the benchmark runs DB (2026-05-05)

Companion to v1.29's corpus GUI: a browsable dashboard for the
longitudinal data the runs store has been collecting since v1.45.

- **`python/crucible/benchmark/ui.py`** — Streamlit dashboard with
  4 tabs:
  - **Overview** — per-provider rollup table (provider, outcomes,
    runs, avg accuracy).
  - **Per-paper trends** — table of all papers with avg accuracy +
    last-run-at + drill-in line chart of one paper's history.
  - **Per-axis accuracy** — overall + per-provider slice via a
    selectbox.
  - **Raw rows** — paginated 500-row view of `benchmark_runs`.
  - Sidebar: DB-path picker, headline metrics (`rows`, `runs`,
    `papers_touched`), schema-version distribution.
- **`python -m crucible benchmark ui [--runs-db PATH] [--port N]
  [--headless]`** — launches Streamlit. Same opt-in pattern as
  `corpus ui`: streamlit lives in the `[ui]` extra; the module's
  import-guard fails with a clear remediation hint when missing.
- Read-only — mutations go through `benchmark run` /
  `benchmark publish` from the CLI.
- 194/194 pytest (+1 smoke test for the missing-streamlit error
  path; UI body is glue and tested via the corpus/store +
  runs_store suites it queries).

### v1.75 — `docs/QUICK_REFERENCE.md` (single-page CLI cheatsheet) (2026-05-05)

The CLI surface has accumulated to ~80 subcommands across 4 tiers
(Julia CLI / Python pure / corpus / benchmark) plus the workspace
tooling. This is the single-page lookup for "what's the syntax
again?" — intentionally light on prose, heavy on tables.

- **`docs/QUICK_REFERENCE.md`** — five sections:
  - Tier 0: 30-subcommand `crucible` Julia CLI (transpile, render,
    run, advise, doctor, templates, diff, coverage, lint, explain,
    cite, upgrade, serve, info, bench, fmt, plot, events, analyze,
    trajstat, snapshot, restore, audit-transcripts,
    export-jsonschema, import-jsonl, parameterize, verify,
    walkthrough, hekate).
  - Tier 1: `python -m crucible` pure-Python ops (validate, lint,
    templates, migrate, spec-describe).
  - Tier 2: `corpus *` (fetch, fetch-batch, papers, authors,
    coauthors, stats, query, ui).
  - Tier 3: `benchmark *` (list, status, add, verify, run,
    report, publish, trends, runs-stats, runs-stats-md,
    export-jsonl, compare, watch).
  - Tier 4: workspace tools (`tools/check_workspace.py` + 9
    others).
  - Environment variables reference.
  - 6 common-workflow recipes (reproduce / audit / corpus seed /
    benchmark publish / regression compare / live-monitor /
    pre-commit).
- **`README.md`** — Documentation section now lists
  `QUICK_REFERENCE.md` first, before `USER_PROFILES.md` and
  `HOW_TO_READ.md`. Order: cheatsheet → task-oriented profile →
  reading-oriented guide.
- All 7 workspace checks green at this commit (the new doc's
  ~50 cross-references all resolve).

### v1.74 — `crucible benchmark watch` (live tail of runs DB) (2026-05-05)

A second mode for the runs DB beyond the v1.45 batch-query model: a
poll-and-print tail for live monitoring of an in-progress run.

- **`python -m crucible benchmark watch <runs-db> [--interval N]`**
  — polls `benchmark_runs` every N seconds (default 5); emits each
  new row as JSONL on stdout. Bounded by `--max-iterations` so
  tests run deterministically; default unbounded for production.
  Default `--since` is "5 minutes ago" — a freshly-launched watch
  picks up an in-progress run.
- **`runs_store.rows_since(conn, since_run_at=, since_run_id=)`**
  — extracted helper that the watch loop uses. Available as a
  Python API for anyone writing custom monitoring.
- Use case: `crucible benchmark publish` in one terminal,
  `crucible benchmark watch ~/.local/share/crucible/corpus.duckdb`
  in another. The watch terminal shows progress as each paper
  scores; useful for the long real-LLM runs (≥ minutes-per-paper).
- 3 new tests (rows_since strictly-newer filter, watch with
  `--max-iterations 1`, watch with bad `--since` exits 2).
  **193/193 pytest** (was 190).

### v1.73 — README "Tools" section for script discoverability (2026-05-04)

The v1.41–v1.72 run added 7 CI-grade scripts under `tools/`. None
were discoverable from the README. This adds a dedicated "Tools"
section between the examples and the option-3 flywheel
description.

- **README.md** — new "Tools" section listing every CI-grade
  script:
  - `check_workspace.py` (7-check aggregator)
  - `check_doc_links.py` (cross-reference auditor)
  - `check_profile_shape.py` (USER_PROFILE_*.md shape)
  - `release_summary.py` (compact CHANGELOG view)
  - `install_precommit.sh` (opt-in git hook installer)
  - `migration_smoke.jl` (already documented; included for
    completeness)
  - `cross_lang_roundtrip.jl` (used by cross-language tests)
- All 7 workspace checks still green at this commit.

### v1.72 — `tools/install_precommit.sh` (opt-in pre-commit hook) (2026-05-04)

Wires the v1.56+v1.68+v1.70 workspace checks into git's pre-commit
hook so they fire automatically on every `git commit` rather than
only when invoked manually.

- **`tools/install_precommit.sh`** — idempotent installer. Drops
  a sentinel-marked hook (`# crucible-precommit-v1`) at
  `.git/hooks/pre-commit` that invokes
  `tools/check_workspace.py`. Re-running refreshes in place.
  Refuses to overwrite a non-Crucible hook without `--force` so
  it doesn't silently clobber a user's existing setup.
- Three flags: bare invocation installs; `--force` overwrites
  foreign hooks; `--dry-run` prints the hook content without
  writing.
- The hook prefers `python/.venv/bin/python` when present
  (matches v1.49's argparse-passthrough subprocess pattern), so
  the check runs against the same crucible.spec the test suite
  uses.
- **Opt-in:** the installer doesn't run automatically. Drivers
  (CI, contributors, the maintainer) invoke it explicitly.
  `git commit --no-verify` remains the escape hatch.

### v1.71 — `tools/release_summary.py` (one-line CHANGELOG view) (2026-05-04)

The CHANGELOG has grown to 70+ versions / ~3000 lines; scanning
"what changed in v1.5x?" is now slow. This emits a compact
one-line-per-version view for navigation.

- **`tools/release_summary.py`** — parses CHANGELOG headers
  (`### v1.42 — title (date)`) and emits a column-aligned table:
  ```
  v1.69  2026-05-04  export-jsonl --include-paper-text + Tier-2 personas file
  v1.68  2026-05-04  doc-links auditor + workspace-check integration
  …
  ```
- Three filters: `--prefix v1.4` (everything in the v1.4x cluster),
  `--since v1.50` (everything from a baseline), `--latest 10` (most
  recent N).
- Strips backticks from titles for compact display; preserves the
  date as parsed from the header.
- Useful for orientation when joining the project mid-stream — `tools/release_summary.py --latest 30` is a fast catch-up.

### v1.70 — profile-shape auditor + code-span-aware link checker (2026-05-04)

Two CI-side polish slices that compound the v1.68 doc-rot defense.

- **`tools/check_profile_shape.py`** — enforces the v1.59
  `ADOPTION_STRATEGY_PLAYBOOK.md` 6-section shape across all
  `USER_PROFILE_*.md` files (you-leave-with hook, pre-flight,
  30-minute path, first-week / multi-day path, failure modes,
  when-to-read-X-next). Tolerates synonyms for the longer-cadence
  sections (instructor's "1-week course module," pharma POC's
  "30-day path"). Catches new profiles that skip a section.
  All 6 current profiles conform.
- **`tools/check_doc_links.py`** — bug fix: strips inline + fenced
  code spans before matching links. Eliminates a false-positive on
  changelog entries that document link syntax verbatim.
- **`tools/check_workspace.py`** — seventh check added.
  All 7 workspace checks green.

### v1.69 — `export-jsonl --include-paper-text` + Tier-2 personas file (2026-05-04)

Two slices that compose the corpus + benchmark layers into the
option-3 fine-tune flywheel feeder format.

- **`benchmark export-jsonl --include-paper-text`** — joins each
  runs row with `corpus.paper_text_for_doi(entry.doi)`, producing
  self-contained `(paper_id, mdspec_score, paper_text)` rows.
  Exactly the shape the option-3 fine-tune
  (`docs/ADOPTION_PLAN.md` Phase 4) wants for training data
  preparation. Missing-from-corpus DOIs surface as
  `paper_text: null` so downstream filters can drop them.
- **`--corpus-db`** flag on `export-jsonl` — optional separate
  corpus-DB path; defaults to reusing `runs_db` (the friction-
  minimum config when one DuckDB file holds both tables).
- **`examples/persona_names_tier2.txt`** — the 6 Tier-2 industry
  CADD personas from `docs/CAMPAIGN_2026Q2.md`. Includes a
  caveat: industry-name OpenAlex matches are less reliable than
  academic ones; verify before trusting the works list.
  Companion to the Tier-1 file from v1.65.
- 1 new test (end-to-end: seed corpus → run → export with text
  join → assert shaw row has populated paper_text, others `None`).
  **190/190 pytest** (was 189).

### v1.68 — doc-links auditor + workspace-check integration (2026-05-04)

Catches doc-rot — the regression class where a renamed/moved doc
leaves stale cross-references behind in the rest of the doc set.
v1.57–v1.62 shipped 11 new docs with hundreds of cross-references;
this auditor enforces they keep resolving.

- **`tools/check_doc_links.py`** — scans every `.md` under
  `docs/`, `musings/`, `examples/`, plus the workspace-root markdown
  files (README, AGENTS, CONTRIBUTING, SECURITY, CHANGELOG). For
  each `[text](path)` link, resolves the target and verifies it
  exists. Skips external (`http://`, `mailto:`) + anchor-only
  links. Exit code = number of broken links.
- **First-run finding:** 1 broken link out of 331 — a forward-
  reference in `docs/ON_PREM.md` to the
  `ON_PREM_DEPLOY_DOCKER.md` doc that's deferred per the
  commercial-validation plan. Fixed inline (link → plain text +
  "(planned, not yet written)" qualifier).
- **`tools/check_workspace.py`** — sixth check added:
  `doc_links` invokes `check_doc_links.py` as a subprocess.
  All 6 checks green at this commit.
- Designed for pre-commit + CI integration alongside the
  v1.56 schema/manifest/pydantic guards.

### v1.67 — `corpus query` (read-only SQL escape hatch) (2026-05-04)

When `papers` / `coauthors` / `authors` don't cover a one-off
analysis, drop into read-only SQL.

- **`python -m crucible corpus query <SQL> [--format jsonl|table]`**
  — runs SQL against the corpus DB. Refuses anything starting with
  a write keyword (INSERT, UPDATE, DELETE, DROP, CREATE, ALTER,
  TRUNCATE, REPLACE, MERGE, ATTACH, DETACH, COPY, PRAGMA) — use
  the `upsert_*` / `fetch` / `fetch-batch` CLI for mutations.
  Refusal exits 2 with a clear error.
- Refusal is keyword-based with leading-comment-stripping; safe
  for the typo case ("DELETE" vs "SELECT"), not adversarial
  isolation. The DB user owns the file; if they want to mutate
  it, they can open `duckdb <path>` directly.
- Two output formats: `jsonl` (default; one row per line) and
  `table` (tab-separated, with a header row, for human reading).
- 13 new tests covering: SELECT round-trip, table format, 9
  parametrized write-keyword refusals (case-insensitive +
  whitespace-tolerant), comment-prefixed SELECT allowed, empty
  SQL → exit 2. **189/189 pytest** (was 176).

### v1.66 — benchmark seed-set structural invariants (2026-05-04)

Catches the regression class that bit v1.37/v1.38: a fabricated
DOI, a duplicate paper_id, a `verified` entry without a
`verified_by` stamp. CI-enforced from this commit forward.

- **`python/tests/test_seed_set_invariants.py`** — 12 structural
  checks on `python/crucible/benchmark/papers.py`:
  - `paper_id` unique
  - `paper_id` matches `^[a-z0-9_]+$` (slug convention)
  - DOI matches Crossref pattern (`^10\.\d{4,9}/\S+$`) — catches
    fabrications like the v1.38-corrected `10.1021/jp067192x`
  - DOI unique across the seed set
  - `status="verified"` requires non-empty `verified_by`
  - title non-empty
  - title under 300 chars (readability cap)
  - `status` value in known set (defense-in-depth on the Literal)
  - `ExpectedProtocol` axes within schema's allowed numeric ranges
    (catches typos like `dt_fs=200` vs `dt_fs=2.0`)
  - verified entries have non-empty `notes` (the audit trail)
  - seed-set size ≥ 5 (statistical floor)
  - seed-set size ≤ 50 (runaway-growth guard)
- The invariants intentionally don't validate scientific content —
  that's the human-verification work in
  `docs/HOW_TO_VERIFY_A_PAPER.md`. These check the *shape*, not
  the values.
- 12 new tests; **176/176 pytest** (was 164).

### v1.65 — `corpus fetch-batch` + Tier-1 personas names file (2026-05-04)

Bulk-ingestion path for the corpus tier. Lets a maintainer fetch
all 10 Tier-1 personas from `docs/CAMPAIGN_2026Q2.md` in one
command rather than 10 sequential `corpus fetch` calls.

- **`python -m crucible corpus fetch-batch <names-file>`** —
  reads one author display-name per line; skips `#` comments and
  blank lines; per-author failures (no match, OpenAlex error)
  log + continue rather than aborting the batch. Exit code is the
  number of failed authors (0 = all green; useful for CI / cron).
  JSON summary on stdout: `{n_total, n_failed, results: [{name,
  n_works, error?}, …]}`.
- **`_fetch_author` helper** — extracted the shared fetch logic
  out of `cmd_fetch` so `cmd_fetch_batch` calls the same code
  path. Both gain consistent error handling.
- **`examples/persona_names_tier1.txt`** — the 10 Tier-1 personas
  ready to ingest:
  ```
  crucible corpus fetch-batch examples/persona_names_tier1.txt \
      --concept "molecular dynamics" --since 2018
  ```
- 3 new tests (skip comments+blanks, empty file → exit 1,
  partial failure → exit n_failed). **164/164 pytest** (was 161).

### v1.64 — `benchmark compare` + `export-jsonl --since` (2026-05-04)

Two longitudinal-tracking improvements on the v1.45 runs DB layer.

- **`benchmark export-jsonl --since YYYY-MM-DD`** — the underlying
  `export_jsonl(since=…)` was already in v1.50; this exposes the
  filter via CLI. Useful for incremental exports to a fine-tune
  pipeline ("only rows since the last export"). Validates ISO-format
  parse before opening the DB; fails with exit 2 + a clear message
  if the date is malformed.
- **`benchmark compare <left.db> <right.db>`** — diff two runs DB
  snapshots. Output JSON: `common_papers`, `only_in_left`,
  `only_in_right`, and a per-paper `deltas` array sorted by
  delta-percentage-point descending. Useful for tracking drift
  across schema bumps, model swaps, prompt refinements, or simply
  "did Crucible improve between these two release tags?". Uses the
  trends accessor; consistent with the existing avg-pct
  computation.
- 2 new tests (since-filter behavior, end-to-end compare).
  **161/161 pytest** (was 159).

### v1.63 — end-to-end benchmark integration tests (2026-05-04)

Per-module unit tests cover the building blocks; this file covers
the full v1.41–v1.55 chain (run → trends → stats → export → publish)
in 10 e2e tests. Catches regressions where individual unit tests
pass but the wired-together pipeline breaks (interface drift,
config-name mismatch, etc.).

- **`python/tests/test_benchmark_e2e.py`** — 10 tests covering:
  - All 6 CLI subcommands exit 0 in the full pipeline
  - Every artifact (DB, runs JSONL, report MD, export JSONL) is
    written and non-empty
  - Two distinct run_ids land in the runs DB after `run` + `publish`
  - Per-paper accuracy is upserted into the corpus's
    `benchmark_scores` table (v1.48 wiring)
  - Report includes the trends section when corpus DB doubles as
    runs DB
  - `publish --brief` produces the summary table; trends section
    survives orthogonally
  - Export JSONL has 10 outcome rows × 10 axes per row, all
    rehydrated from JSON
  - `schema_version` recorded in each row matches the live
    `SCHEMA_VERSION` constant
  - `python -m crucible benchmark` passthrough dispatches via
    `sys.executable` (catches the v1.49 argparse REMAINDER fix)
- All run on the v1.53 `MockTranspileProvider` — no network, no
  live LLM, no GPU.
- 10 new tests; **159/159 pytest** (was 149).

### v1.62 — adoption FAQ (cross-profile common questions) (2026-05-04)

Closes the v1.57–v1.61 adoption-strategy doc set with an FAQ
covering questions that span multiple user profiles.

- **`docs/ADOPTION_FAQ.md`** — five categories:
  - **Does this actually work?** — benchmark stance, what failures
    are caught, the failure mode that worries us most.
  - **What's it cost?** — software (Apache 2.0), compute
    (~$0.05/paper Anthropic; local-mode electricity), maintainer
    time (~10 min/paper for researchers, 30 days for pharma POC).
  - **How do I integrate it?** — Python / Julia / R-Rust-Go-TS /
    macOS-Linux-Windows / offline-airgap / dependency list.
  - **What's the IP / data story?** — what leaves the network,
    where transcripts are stored, attribution rules, no telemetry.
  - **Where does this go from here?** — roadmap pointers, bus
    factor, LLM-model-change story, OpenMM/Molly version pinning,
    GROMACS support scoping.
  - **Help / community** — issue templates, Discord status, paid
    POC entry.
- The FAQ deliberately doesn't repeat anything from the profile
  docs; it answers cross-profile questions and points at the
  profile docs for role-specific detail.

### v1.61 — three-length project pitch (2026-05-04)

The first artifact every adopter sees. Three pitches at three
lengths (60s elevator / 5m dinner-conversation / 30m
boardroom-deck) that share one wedge and end at the same place
("here's what you do next").

- **`docs/PROJECT_PITCH.md`** — non-overlapping pitches:
  - **60s:** the wedge sentence — *"the LLM doesn't write Python;
    it emits a typed IR with provenance, and the validator catches
    silent errors before runtime."*
  - **5m:** problem (reproducibility-as-translation), solution
    (IR-as-contract), today (shipped capabilities), what-you-do-next
    (three profile pointers).
  - **30m:** 10-slide outline mapping to existing docs
    (architecture diagrams, hallucination benchmark, on-prem mode,
    fine-tune flywheel, adoption timeline). Per-audience
    call-to-action at the close.
- **Pitch maintenance rules** at the bottom — when to update each
  length, what triggers a rewrite. Cross-checks against
  `musings/scaling_modes.md` to keep the canonical pitch
  consistent.
- Companion to `docs/USER_PROFILES.md` (each pitch ends pointing
  there) and `docs/ADOPTION_TIMELINE.md` (each phase has a
  matching pitch length).

### v1.60 — adoption timeline (when to activate each profile) (2026-05-04)

Bridges the strategic 18-month `docs/ADOPTION_PLAN.md` and the
180-day `docs/COMMERCIAL_VALIDATION_PLAN.md` with the seven user
profiles in `docs/USER_PROFILES.md`. Answers the question
"when does each profile get actively onboarded?" rather than just
"what does each profile need?".

- **`docs/ADOPTION_TIMELINE.md`** — phase-by-phase activation
  table:
  - Phase 0 (months 0-3): grad student + reproducibility
    researcher (only prerequisite: working install).
  - Phase 1 (months 3-9): + JOSS reviewer + open-source maintainer
    (prerequisite: tagged release + methods paper draft).
  - Phase 2a (months 9-18): + instructor / TA (prerequisite:
    polished walkthrough notebooks + cited paper).
  - Phase 2c (months 9-18): + pharma POC + data engineer
    (prerequisite: on-prem mode + verified benchmark + fine-tune
    flywheel data layer).
- **What-not-to-do per phase** — explicit anti-patterns that
  produce dropouts (don't pitch pharma in Phase 0; don't submit
  to JOSS pre-paper; don't activate instructors before the
  walkthroughs polish).
- **Cross-reference table** mapping each phase activation to the
  doc that walks it + the doc that gates it. Maintainers can use
  this as the activation checklist.
- Companion to `ADOPTION_STRATEGY_PLAYBOOK.md` (the *how*) and
  `scaling_modes.md` (the *strategic frame*).

### v1.59 — adoption-strategy playbook meta-doc (2026-05-04)

The "record notes as you go" piece complementing v1.57+v1.58.
Distills the patterns that emerged while writing seven user-profile
docs into a reusable playbook for future adoption-doc work.

- **`docs/ADOPTION_STRATEGY_PLAYBOOK.md`** — captures:
  - The three orthogonal axes (role / outcome / cadence) and why
    organizing around role is correct for adoption.
  - The 6-section shape every `USER_PROFILE_*.md` follows
    (one-paragraph hook with concrete artifact, pre-flight,
    30-minute path, first-week path, failure modes, next-reads),
    with notes on what each section requires.
  - Five anti-patterns to avoid: The Tour, The Pre-Flight
    Inflation, The Aspirational Failure Mode, The Endless
    Cross-Reference, The Missing Outcome.
  - Time-to-value calibration (≤30 min, 1 day, 1 week, 30 days)
    with what's possible at each cadence.
  - The bar for adding a new profile: real adopter, real outcome,
    real time-to-value measurement. Speculative profiles harm the
    set.
  - Sequencing notes: which profiles are plausible-but-unevidenced
    (HPC admin, wet-lab biologist, AI/ML researcher) and why we're
    deliberately waiting.
  - Maintenance rules: 30-min paths track current project state;
    drift is a regression, not a budget revision.
- Companion to `musings/scaling_modes.md` (strategic) and
  `docs/CAMPAIGN_2026Q2.md` (operational); this is the
  *tactical* playbook for individual artifacts.

### v1.58 — three more user-profile docs (reproducibility / data eng / JOSS) (2026-05-04)

Rounds out the v1.57 user-profile index with three more dedicated
adoption docs.

- **`docs/USER_PROFILE_REPRODUCIBILITY_RESEARCHER.md`** — the
  audit-the-paper workflow. 30-minute path: extract Methods →
  transpile → `crucible coverage` → manual cross-check of `assumed`
  + missing fields. The audit becomes a benchmark contribution
  via `benchmark add` + `verify`.
- **`docs/USER_PROFILE_DATA_ENGINEER.md`** — the option-3
  fine-tune flywheel data-layer story. Walks the three stores
  (transcripts, corpus, benchmark runs); export to warehouse via
  JSONL or DuckDB COPY-to-Parquet; schema migration for historical
  records; streaming hook patterns. Honest scope: Crucible ships
  clean inputs; curation pipeline is the team's domain.
- **`docs/USER_PROFILE_JOSS_REVIEWER.md`** — JOSS / pyOpenSci /
  national-lab eval review. 30-minute smoke path mapped to the 6
  required criteria; 3-4 hour deep review with prep cheat sheet
  for likely findings (LLM-correctness, JSON-vs-protobuf,
  language choice, migration story). Designed so the reviewer can
  finish in one sitting without grep-spiraling.
- **`docs/USER_PROFILES.md`** — index now lists 7 profiles
  (3 dedicated to existing onboarding paths, 3 new dedicated docs,
  1 routing to the maintainer guide). Chooser updated.
- All three follow the v1.57 shape (one-paragraph hook, pre-flight,
  30-minute path, first-week path, failure modes, next-read
  pointers) so they cross-reference cleanly.

### v1.57 — task-oriented user-profile docs for adoption (2026-05-04)

Adoption-strategy artifacts: dedicated docs that take a specific
kind of person from "I just heard about Crucible" to "I have
produced something useful with it." Companion to the existing
reading-oriented guides in `docs/HOW_TO_READ.md` — the two are
non-overlapping by design.

- **`docs/USER_PROFILES.md`** — index. Five profiles (grad
  student / postdoc, pharma CADD POC eval, instructor / TA,
  reproducibility researcher, open-source maintainer) with
  primary outcome + first artifact + time-to-value per row.
  Includes a chooser ("if you have a paper and want to reproduce
  its MD…") and a process for adding new profiles (don't
  speculate; talk to a real person first).
- **`docs/USER_PROFILE_GRAD_STUDENT.md`** — most common adopter
  pattern. 30-minute path from clone → runnable OpenMM script
  reproducing a published Methods section. First-week path
  (preview → production → analysis). Failure modes (OPLS3 not in
  allowlist, missing salt-concentration extraction, Gate 3 path
  issues, no API budget, blown-up production run).
- **`docs/USER_PROFILE_PHARMA_POC.md`** — Tier-2 audience from
  the campaign doc. 30-day eval path: install → public benchmark
  baseline → internal protocol baseline → accuracy + iteration →
  written eval. Explicit "is/isn't": measures protocol fidelity,
  doesn't measure FEP convergence or LP correctness. Pilot scope
  pointer ($5K-$15K POC per the commercial-validation plan).
- **`docs/USER_PROFILE_INSTRUCTOR.md`** — instructor / TA. 1-week
  course module: 5 lectures + 1 lab + 1 homework that produces a
  real PR contribution to the benchmark seed set. Variants for
  computational-drug-discovery, MD-methodology, and AI-for-science
  courses.
- **`README.md`** — Documentation section now points users at the
  profile index FIRST, then the reading guides, with the
  task/reading distinction called out.
- All four new docs follow the same shape (one-paragraph hook,
  pre-flight, 30-minute path, first-week path, failure modes,
  next-read pointers) so they cross-reference cleanly.

### v1.56 — `tools/check_workspace.py` aggregate consistency check (2026-05-04)

Bundles the cross-file invariants that v1.41–v1.55 introduced into
a single fail-fast script. Designed for pre-commit hooks + CI gates.

- **`tools/check_workspace.py`** — five checks, each independent
  with a one-line failure message; exit code = number of failed
  checks.
  1. Python `SCHEMA_VERSION` matches `src/spec/schema.json` const
  2. Python `SCHEMA_VERSION` matches `src/spec/MDSpec.jl` keyword
     default
  3. Every test fixture under `test/fixtures/*.json` declares a
     `schema_version` in `{0.1.0, 0.2.0, 0.3.0, 0.4.0}` (catches
     stale fixtures after migration registry changes)
  4. `Manifest.toml` uses `manifest_format = "2.0"` (Pkg modern;
     guards against Julia version-skew regression)
  5. `python/pyproject.toml` pins `pydantic>=2` (the v1 split was
     painful enough to be load-bearing)
- All 5 checks green at this commit. Run with `--verbose` to see
  passes too.

### v1.55 — `publish --brief` + `--to-docs` (2026-05-04)

Two UX improvements on the v1.50 publish flow.

- **`benchmark publish --brief`** — propagates the v1.52 brief
  flag through the run + report pipeline; the canonical landing
  page can now be regenerated as either the verbose detail page
  (default) or the one-table summary (campaign-asset-friendly).
- **`benchmark publish --to-docs`** — convenience: writes to
  `<repo_root>/docs/HALLUCINATION_BENCHMARK.md` regardless of
  CWD. Resolves the path relative to the package, so
  `cd /tmp && python -m crucible benchmark publish --mock --to-docs`
  hits the right file.
- 1 new test (publish --brief uses summary table). **149/149
  pytest** (was 148).

### v1.54 — BENCHMARK_AXES.md reference + `spec-describe` CLI (2026-05-04)

Two reference-layer additions: a canonical doc for the 10 benchmark
axes and a quick CLI for inspecting the IR's allowlists.

- **`docs/BENCHMARK_AXES.md`** — per-axis reference: spec path,
  grading rule, allowed enum values, common LLM mappings, unit-
  conversion warnings (Å → nm, °C → K, atm vs bar, μs/ms → ns).
  Includes a "How to add an axis" runbook (7-step checklist
  spanning IR, scorer, papers, docs, verify-CLI). Companion to
  `docs/HOW_TO_VERIFY_A_PAPER.md` — that doc covers the verification
  procedure; this one covers what each axis means.
- **`python -m crucible spec-describe [--format json]`** — prints
  the schema version + every allowlist (protein / water / ligand /
  lipid FF, lipid composition, CG protein FFs). Useful for users
  writing custom adapters or hand-editing specs without consulting
  source. Text by default; `--format json` for scripting.
- 148/148 pytest unchanged (CLI smoke verified manually).

### v1.53 — `corpus authors` + `MockTranspileProvider` class (2026-05-04)

Two small surface improvements.

- **`python -m crucible corpus authors [--limit N]`** — list authors
  in the local DB ordered by local-works-count desc. Closes the
  "browse without DuckDB" gap (previously you had to query the DB
  directly to see what was ingested).
- **`crucible.benchmark.MockTranspileProvider`** — promoted from an
  inline lambda inside `cmd_run`'s `--mock` path to a real testable
  class. Constructor takes `template_name=` so tests can pin a
  specific template; default is `"vanilla"`. Lives in
  `benchmark/runner.py` and is re-exported from `crucible.benchmark`.
  The CLI's `--mock` path now uses it, so what tests exercise is
  what production runs do.
- 3 new tests (mock provider returns named template, mock default,
  corpus authors lists local rows). **148/148 pytest** (was 145).

### v1.52 — `--brief` reports + `runs-stats-md` (2026-05-04)

Two report-layer surface improvements that lean on the v1.45 data
layer.

- **`render_report(..., brief=True)`** + **`benchmark report --brief`**
  — emits a single Per-paper-summary table (one row per paper:
  status, score, elapsed) instead of the verbose per-axis breakdown.
  The full report extracted to `_per_paper_verbose` helper so the
  brief/verbose split is one line. Reduces a typical 5-paper
  benchmark report from ~80 lines to ~12 — practical for blog
  embeds + cold emails.
- **`render_runs_stats_md(conn)`** + **`benchmark runs-stats-md
  <db>`** — markdown variant of the JSON `runs-stats` output.
  Three sections (per-provider rollup, per-axis accuracy,
  schema-version distribution). Embeddable in any markdown
  document.
- 4 new tests (brief mode, brief-on-empty, runs-stats-md emit,
  runs-stats-md empty). **145/145 pytest** (was 141).

### v1.51 — cross-language migration smoke (2026-05-04)

Pins the migration parity invariant: a v0.1.0 spec migrated through
the Python migration registry must serialize to JSON that Julia's
`spec_from_json` parses cleanly, and the parsed-as-dict result must
equal Python's pydantic-validated round-trip.

- **`python/tests/test_cross_language_consistency.py`** —
  `test_python_migration_output_parses_cleanly_in_julia` builds an
  old-shape v0.1.0 spec, walks it through the Python migration
  chain (`0.1.0 → 0.2.0 → 0.3.0 → 0.4.0`), and pipes the result
  through Julia's `spec_from_json` + `spec_to_json` via the existing
  `cross_lang_roundtrip.jl` script. Asserts:
  - Julia parses without error
  - Round-tripped Julia output deep-equals Python's pydantic
    round-trip
  - `padding_nm` (added in v0.4.0) survives the migration on both
    sides
- Catches the regression class where the Python and Julia
  migration registries drift (e.g. one adds a backfill field the
  other doesn't, or one renames a key).
- 1 new test; **141/141 pytest** (was 140).

### v1.50 — `benchmark export-jsonl` + one-shot `benchmark publish` (2026-05-04)

Two CLI surface improvements that lean on the v1.45 + v1.48 data
layer.

- **`python -m crucible benchmark export-jsonl <runs.db>
  [--out X] [--paper-id Y] [--provider Z]`** — dumps the runs table
  to JSONL, one row per line, with `per_axis` rehydrated from JSON.
  Designed as the **option-3 fine-tune flywheel feeder**
  (`docs/ADOPTION_PLAN.md` Phase 4) — the JSONL is the wire format
  the training corpus consumes; per-row provenance lets the trainer
  filter to "high-quality runs only" downstream.
- **`python -m crucible benchmark publish [--mock] [--corpus-db X]
  [--out report.md]`** — one-shot: runs the benchmark, renders the
  report, optionally writes to a markdown path. Auto-includes the
  trends section when `--corpus-db` is set (it's also the runs DB
  by default). Reduces the publish cycle from 3 commands
  (run → report → cp) to 1.
- **`python/crucible/benchmark/runs_store.py`** — new
  `export_jsonl(conn, since=, paper_id=, llm_provider=)` generator.
- 3 new tests (export round-trip, export filters, publish writes
  markdown). **140/140 pytest** (was 137).

### v1.49 — fix passthrough subcommand argparse + verify-doc thermostat (2026-05-04)

Two cleanup slices around v1.47–v1.48.

- **`python/crucible/__main__.py`** — `python -m crucible corpus
  --db PATH stats` was failing with `unrecognized arguments: --db`
  because `argparse.REMAINDER` notoriously stops on unknown-option
  tokens. Fix: dispatch the `corpus` and `benchmark` subcommands
  via `sys.argv` slicing **before** the outer argparse runs. Also
  fixes `crucible-py migrate --target` to default to the live
  `SCHEMA_VERSION` (was hard-coded `"0.3.0"` from before v1.44).
- **`docs/HOW_TO_VERIFY_A_PAPER.md`** — cheat-sheet expanded from 8
  axes to 10 (`solvent_padding_nm` + `thermostat` added in v1.44 and
  v1.47). With unit-conversion warning ("commonly stated as 10 Å
  buffer" → convert to nm).
- 137/137 pytest unchanged (the bug only surfaced in a real CLI
  invocation; the existing tests use the inner CLI directly).

### v1.48 — corpus ↔ benchmark linkage (per-paper score writeback) (2026-05-04)

Closes the loop between the corpus and the benchmark: a successful
`benchmark run --corpus-db <X>` now upserts per-paper accuracy back
into the corpus DB so the corpus tier (GUI, future API) can surface
"this paper's last benchmark accuracy was Y%" alongside the rest of
the metadata.

- **`python/crucible/corpus/store.py`** — new `benchmark_scores`
  table:
  `(doi, paper_id, last_run_at, last_total, last_max, last_provider,
  n_runs)`. PK `(doi, paper_id)`. Two methods:
  `upsert_benchmark_score(doi, paper_id, total, max_score, provider)`
  (uses `now()` instead of `CURRENT_TIMESTAMP` to dodge the same
  DuckDB binder quirk as v1.29) and
  `benchmark_score_for_doi(doi)` returning the latest score with a
  pre-computed `last_pct`.
- **`python/crucible/benchmark/cli.py`** — `cmd_run` now writes
  per-paper score back to the corpus DB when `--corpus-db` is set
  AND the outcome is ok AND the entry has a DOI. Best-effort: if
  the corpus is open elsewhere, the upsert is wrapped in the
  existing run loop with no extra connection.
- **`stats()`** in `corpus.store` now includes `benchmark_scores`
  in its row-count summary.
- 4 new tests (round-trip, increment-and-replace, DOI normalization,
  end-to-end run-writes-back). **137/137 pytest** (was 133).
- End-to-end smoke verified: `benchmark run --corpus-db X` produces
  5 rows in the corpus's `benchmark_scores` table.

### v1.47 — 10th benchmark axis (thermostat) + runs-stats CLI (2026-05-04)

Two slices: extend the benchmark to grade the production-stage
thermostat (already in the IR; previously ungraded), and surface the
longitudinal runs DB through a JSON-emitting `runs-stats` subcommand
(per-axis accuracy + per-provider breakdown + schema-version
distribution).

- **`python/crucible/benchmark/scorer.py` + `papers.py`** — adds
  `ScoreAxis.THERMOSTAT` (now 10 axes); `ExpectedProtocol.thermostat`
  (`Optional[str]`). Scorer compares case-insensitive against
  `production.thermostat`. No schema bump — the field was already on
  `DynamicsStage`.
- **`python/crucible/benchmark/cli.py`** — interactive `verify`
  prompt now includes the 10th axis.
- **`python/crucible/benchmark/runs_store.py`** — three new
  accessors: `per_axis_accuracy(conn, llm_provider=None)`,
  `per_provider_summary(conn)`,
  `schema_version_distribution(conn)`. Per-axis is computed in
  Python (parses `per_axis` JSON column) for cross-DuckDB-version
  portability.
- **`python -m crucible benchmark runs-stats <db> [--provider X]`**
  — prints stats + schema-version distribution + per-provider
  rollup + per-axis accuracy as JSON. Optional `--provider` slice
  for per-provider per-axis accuracy.
- 6 new tests (2 thermostat scorer + 4 stats accessors). **133/133
  pytest** (was 127).
- End-to-end smoke verified: `benchmark run` → `runs-stats`
  surfaces the new axis + per-provider numbers.

### v1.46 — schema-version guards + trend reporter (2026-05-04)

Two slices that close around the v1.44 schema bump experience: pin
schema-version drift across files at test time, and surface the
longitudinal runs-DB data in the canonical markdown report.

- **`python/tests/test_spec.py`** — two new guard tests:
  `SCHEMA_VERSION` (Python pydantic) must equal both
  `src/spec/schema.json:properties.schema_version.const` AND the
  default `schema_version="…"` keyword in `src/spec/MDSpec.jl`. The
  v1.44 bump touched 3 places that needed coordinated updates;
  these tests catch the partial-bump regression class.
- **`python/crucible/benchmark/reporter.py`** — new
  `render_trend_section(runs_db)` that emits a markdown table of
  per-paper avg-accuracy + n-runs + last-run-at + distinct
  providers. `render_report(..., trends_db=conn)` injects the
  section above the methodology footer. Empty when the runs table
  is empty (so unconditional callers don't get a header with no
  body).
- **`python -m crucible benchmark report --trends-db <path>`** —
  optional flag to include the longitudinal table.
- End-to-end smoke verified: `benchmark run --corpus-db X` records
  to DuckDB; `benchmark report --trends-db X` pulls the trends
  back into the published markdown.
- 4 new tests; **127/127 pytest** (was 123).

### v1.45 — benchmark runs store + recorded-fixture cross-lang test (2026-05-04)

Two slices in one. Together they upgrade the benchmark from a one-shot
report into a longitudinal data layer (the option-3 fine-tune
flywheel substrate, `docs/ADOPTION_PLAN.md` Phase 4) and pin the
recorded-transcript round-trip across both languages.

- **`python/crucible/benchmark/runs_store.py`** — DuckDB-backed store
  for benchmark outcomes. Schema:
  `benchmark_runs(run_id, paper_id, run_at, llm_provider, llm_model,
  ok, elapsed_s, total, max_score, per_axis, error, schema_version,
  crucible_version)`. PK `(run_id, paper_id)` so re-running a paper
  in the same invocation is idempotent.
- **`python -m crucible benchmark run`** — new flags:
  `--runs-db <path>` (or reuses `--corpus-db`), `--llm-model <name>`.
  Every outcome appends one row tagged with the IR `schema_version`.
- **`python -m crucible benchmark trends [--paper-id X] <runs.db>`**
  — per-paper rollup (`avg_pct`, `n_runs`, `last_run_at`, distinct
  providers). The longitudinal view that lets us answer "did Crucible
  get better at Mobley 2007 between v1.42 and v1.45?".
- **`python/tests/test_cross_language_consistency.py`** —
  parametrized with `recorded_anthropic_spec` + `known_good_spec`
  fixtures. Python pydantic-validates → Julia round-trips → parsed-
  as-dict equality holds. Catches the failure mode where a
  transcript stored under one schema version silently fails to load
  on the other side.
- 10 new pytest tests (8 runs-store unit + 2 recorded-fixture
  cross-lang). **123/123 pytest pass** (was 113).
- 928/928 Julia unchanged.

### v1.44 — schema 0.4.0: solvent_padding_nm + 9th benchmark axis (2026-05-04)

First real schema bump in this session. Adds
`system.solvent.padding_nm` (the solute-to-box-edge buffer in nm —
typically 1.0–1.5, commonly stated in Methods sections, previously
invisible to the benchmark scorer). Backward-compatible: optional
field defaulting to `null`.

- **`src/spec/MDSpec.jl` + `src/spec/schema.json`** — `padding_nm`
  added to `SolventSpec` (Julia struct) and the JSON Schema under
  `system.solvent` (`{"type": ["number", "null"], "minimum": 0,
  "maximum": 10}`). `$id` and `schema_version` const bumped to
  `0.4.0`.
- **`python/crucible/spec.py`** — pydantic model gets the same
  field with `Field(default=None, ge=0.0, le=10.0)`. `SCHEMA_VERSION`
  bumped to `0.4.0`.
- **`src/spec/Migrations.jl` + `python/crucible/migrate.py`** —
  registered `0.3.0 → 0.4.0` migration that backfills
  `padding_nm: None` on old specs. Maintains the load-bearing
  invariant: every historical transcript still loads cleanly into
  the current schema (option-3 fine-tune flywheel survives).
- **`python/crucible/benchmark/scorer.py` + `papers.py`** — adds
  `SOLVENT_PADDING_NM` to `ScoreAxis` (now 9 axes) and
  `solvent_padding_nm` to `ExpectedProtocol`. The scorer reads
  `spec.system.solvent.padding_nm`; old verified entries with
  `solvent_padding_nm=None` simply drop the axis from numerator +
  denominator (no false negatives).
- **`python/crucible/benchmark/cli.py`** — interactive `verify`
  prompt now includes the 9th axis.
- **Test fixtures** — `test/fixtures/recorded_anthropic_spec.json` +
  `test/fixtures/known_good_spec.json` bumped to 0.4.0 with
  `padding_nm: null`. Per-test-file `"0.3.0"` strings updated.
- **Migration smoke** — `tools/migration_smoke.jl`'s
  `REGISTERED_VERSIONS` extended with `"0.4.0"`. The smoke walks
  every fixture through every registered target.
- Tests: 928/928 Julia + 113/113 Python (Python +1 for the new
  `0.3.0 → 0.4.0` migration test). Cross-language round-trip
  unchanged at 8/8 — Python emit / Julia parse symmetry holds across
  the schema bump.

### v1.43 — interactive `benchmark verify` CLI (2026-05-04)

Lowest-friction path to flipping a `needs_verification` entry to
`verified`. Closes the "remember-the-syntax" friction at the keyboard;
reading the paper is still the bottleneck (and rightly so).

- **`python -m crucible benchmark verify --paper-id <id> [--initials AQN] [--force]`**
  walks the 8 `ExpectedProtocol` axes interactively. For each axis:
  enter a value, `none` (paper doesn't specify), or empty (keep
  current). Confirms once, then surgically patches `papers.py`:
  - replaces the `expected=ExpectedProtocol(...)` body with the new
    field values
  - strips any existing `status=`/`verified_by=` lines and re-inserts
    canonical `status="verified"` + `verified_by="<initials> <YYYY-MM-DD>"`
    just before the entry's closing `),`
  - appends a `[verify <stamp>] <axis>: paper does not specify` note
    for every axis the user marked `none`
- The patcher uses **indent-based termination** for both the
  `BenchmarkEntry(...)` block and the inner `ExpectedProtocol(...)`
  block — naive `[^)]*\)` regexes hit early-close on parens-in-titles
  like `"(PubMed PMID 20947758)"` or `"(Lindorff-Larsen et al., 2010)"`.
  Real-papers smoke-tested against the Shaw 2010 entry; all 5
  benchmark tests still pass after the patch.
- **`docs/HOW_TO_VERIFY_A_PAPER.md`** — new section §4a documents the
  interactive command as the recommended path; the by-hand procedure
  is now §4b.
- 3 new tests (subcommand registration, unknown-paper rejection,
  patcher unit test). **112/112 pytest** (was 109).

### v1.42 — corpus full-text fetch (PDF → pdftotext) (2026-05-04)

`paper_text_for_doi` learns to fetch + extract OA PDFs on demand.
Bridges the gap between title+abstract (medium signal) and the
sidecar Methods file (best signal) — when a paper is OA and has a
direct PDF URL on OpenAlex, the LLM input upgrades automatically.

- **`python/crucible/corpus/store.py`** — `paper_text_for_doi` now
  takes `prefer_full_text=False` (default) / `True`, plus a
  `cache_dir` override. With full-text on, resolution is:
  1. cached `<cache_dir>/<work_id>.txt`
  2. download `pdf_url` → `pdftotext -layout` → cache → return
  3. fall back to `title + abstract`
  4. fall back to `None` (DOI not in corpus)
  Network errors, missing `pdftotext`, no `pdf_url`, and corrupt
  PDFs all silently fall through. Tests don't pay for outbound
  HTTP.
- **`python/crucible/benchmark/cli.py`** — `benchmark run` learns
  `--full-text` and `--full-text-cache <dir>`. Off by default;
  on-demand for verified-only benchmark runs.
- **`_post_process_pdftotext`** — collapses 3+ blank lines (paragraph
  separator) and strips trailing whitespace per line. Output is
  noticeably more LLM-friendly than raw pdftotext.
- 4 new tests (cache hit, fallback to abstract, off-by-default,
  post-process). **109/109 pytest pass** (was 105).
- No new runtime deps — uses stdlib `urllib` + system `pdftotext`
  (already a CI dep for `PDFAdapter` tests).

### v1.41 — cross-language consistency tests (2026-05-04)

Pins the load-bearing IR-as-contract invariant: a `MDSpec` emitted
by Python's pydantic models must round-trip byte-equivalent (after
JSON normalization) through the Julia loader. Without this test,
silent divergence between the two ports can creep in over schema
bumps; the polyglot story (`musings/ecosystem_alternatives.md`)
collapses if it isn't pinned.

- **`tools/cross_lang_roundtrip.jl`** — single Julia process reads
  JSONL from stdin, parses each line via `Crucible.spec_from_json`,
  re-emits via `Crucible.spec_to_json`. Amortizes Julia's ~3 s
  startup over arbitrarily many specs.
- **`python/tests/test_cross_language_consistency.py`** — runs six
  representative templates (vanilla, smiles, protein_ligand_fep,
  remd, membrane, metadynamics) through the round-trip; asserts
  parsed-as-dict equality, provenance-key-set equality, and stage
  discriminator preservation. Skips when `julia` isn't on PATH.
  Module-scoped fixture: 8 tests share one Julia subprocess.
- 105/105 pytest pass (was 97; +8 cross-language). Total wall-clock
  ~4.4 s.
- 928/928 Julia tests unchanged.

### v1.40 — verification guide + `benchmark add` CLI (2026-05-04)

Lowers the friction on the highest-leverage paywall-gated punch-list
item: verifying ≥1 benchmark seed entry against its source.

- **`docs/HOW_TO_VERIFY_A_PAPER.md`** — step-by-step procedure for
  flipping a `needs_verification` entry to `verified`. Covers
  pre-flight (paywall workarounds), the 8 axes mapped to where in a
  paper to look, the three rules (`None` is real, cite the section,
  document allowlist gaps), the 7-step procedure (find → read → map
  → edit → test → score → commit), and common pitfalls (atm vs bar,
  ambiguous "AMBER", FF outside the allowlist, multi-system papers).
  Time budget: 15-45 min per paper once the source is in hand.
- **`python/crucible/benchmark/cli.py`** — new `add` subcommand:
  ```
  python -m crucible benchmark add \
      --paper-id mobley_2007_alchemical \
      --doi 10.1016/j.jmb.2007.06.002 \
      --title "Predicting Absolute Ligand Binding Free Energies …"
  ```
  Appends a `needs_verification` stub to `papers.py` with all
  `ExpectedProtocol` axes `None` until human-verified. Rejects
  duplicate `paper_id`s; refuses to mutate if the file's layout
  has drifted from the expected sentinel.
- **`docs/PUNCHLIST.md`** — verification entry now references
  `HOW_TO_VERIFY_A_PAPER.md` with the per-paper time budget.
- 2 new tests; **97/97 pytest pass** (was 95).
- 928/928 Julia tests unchanged.

### v1.39 — CI matrix adds Julia 1.12 + Manifest sync (2026-05-04)

Closes the *Manifest.toml CI matrix decision* item from
`docs/PUNCHLIST.md` per the recommended option (1): bump CI to
include 1.12 and commit the regenerated Manifest. Costs one extra
CI cell per PR; eliminates the local-vs-tracked Manifest drift that
`tools/repair_manifest.sh` was leaving in `git status`.

- **`.github/workflows/ci.yml`** — `julia-version` matrix expanded
  from `["1.10", "1.11"]` to `["1.10", "1.11", "1.12"]`. Live OpenMM
  smoke job stays pinned to 1.10 to keep total build time reasonable.
- **`Manifest.toml`** — regenerated under Julia 1.12.5 (manifest_format
  2.0). The format is forward-compatible with Julia 1.7+, so the 1.10
  and 1.11 cells should resolve cleanly; if they don't, fall-back is
  option 2 (drop 1.10, reduce the compatibility claim).
- **`docs/PUNCHLIST.md`** — *Manifest.toml CI matrix decision* entry
  removed per the file's "punch list, not history" convention.
- 928/928 Julia tests pass on 1.12.5 locally; 1.10 / 1.11 validate on
  first CI run after this commit.

### v1.38 — fix Mobley 2007 fabricated DOI + Salomon-Ferrer subtitle (2026-05-04)

- **`python/crucible/benchmark/papers.py`** — second pass of
  Crossref-driven DOI verification (the v1.37 pattern, applied to
  the remaining 4 entries):
  - **Mobley 2007**: DOI `10.1021/jp067192x` was **fabricated** —
    404 on both Crossref API and doi.org. The real paper is in
    *J. Mol. Biol.* (not *J. Phys. Chem. B*) at
    `10.1016/j.jmb.2007.06.002`. Corrected. Author list
    expanded from 3 → 6 (added Graves, McReynolds, Shoichet).
  - **Salomon-Ferrer 2013**: title was missing the "2. Explicit
    Solvent Particle Mesh Ewald" subtitle (the paper is part 2 of
    a series). Title corrected; full author list added.
  - Sugita-Okamoto 1999, Wang 2015, Salomon-Ferrer 2013 DOIs all
    verified correct against Crossref bibliographic metadata.
- **`docs/HALLUCINATION_BENCHMARK.md`** — seed-set list updated to
  match (Shaw not Lindorff-Larsen as #1; Mobley DOI corrected; SF
  series-2 noted).
- **`examples/loom_demo/README.md`** — Mobley DOI updated.
- **Tests:** Python benchmark + bridge suite still 23/23.

### v1.37 — benchmark seed slug correction + Loom under-specified variant (2026-05-04)

- **`python/crucible/benchmark/papers.py`** — corrected the
  `lindorff_2010_bpti` entry. DOI `10.1126/science.1187409`
  resolves to Shaw et al. 2010, *Science* 330, 341 — *Atomic-Level
  Characterization of the Structural Dynamics of Proteins* (the
  Anton BPTI 1ms paper) — NOT the ff99SB-ILDN force-field paper as
  the prior title claimed. Lindorff-Larsen is co-author #3, not
  first.
  - Slug renamed: `lindorff_2010_bpti` → `shaw_2010_bpti`.
  - Title corrected.
  - `duration_ns = 1_000_000.0` — ✓ verified from PubMed abstract
    PMID 20947758 ("a 1-millisecond simulation").
  - All other `ExpectedProtocol` fields stay `needs_verification`:
    they are widely cited in secondary literature but the Science
    SI is paywalled and has not been read by a human. The notes
    field flags exactly which axes are evidence-backed vs.
    cargo-culted.
- **`examples/loom_demo/methods_underspecified.txt`** — new file.
  A Methods paragraph derived ONLY from the Shaw 2010 public
  abstract. Demonstrates the LLM's behavior on under-specified
  Methods sections (the realistic case for many MD papers) and
  ties the Loom recording to a real, attributed DOI without
  fabricating SI-level detail. Pairs with the existing
  `methods.txt` (synthetic Abl+imatinib FEP, full detail) — pick
  one based on the audience.
- **`examples/loom_demo/README.md`** — documents both Methods
  files and updates the seed-set DOI list to reflect the Shaw
  2010 correction.
- **Tests:** Python benchmark + bridge suite still passes (23/23).
  Julia full suite passes 928/928 (no Julia changes in this slice).

### v1.36 — `_explain_spec` lifted to shared module + Manifest repair tool (2026-05-04)

- **`src/spec/Explain.jl`** — new shared module hosting
  `_explain_spec` and `_stage_one_liner`. Lifted verbatim from
  `src/cli/CLI.jl`. Reason: `src/atproto/HekatePublisher.jl:130`
  was calling `Crucible._explain_spec`, but the function lived in
  `Crucible.CLI`, not `Crucible` — so the `try/catch` around the
  call silently fell back to the placeholder summary `"Crucible
  run."` for every published `app.hekate.*` review-session record.
- **`src/cli/CLI.jl`** — removed the duplicate definitions.
  `cmd_explain` now calls `Crucible._explain_spec(spec)`.
- **`src/Crucible.jl`** — `include("spec/Explain.jl")` after the
  rest of `spec/`. No new exports (`_explain_spec` is intentionally
  underscored — prose, not API).
- **`tools/repair_manifest.sh`** — idempotent script that fixes
  ownership on `Manifest.toml` (sudo chown if root-owned) then
  regenerates against the local Julia. Unblocks running the full
  Julia test suite locally — including the v1.33 atproto tests
  that currently only run in an isolated env.
- **Follow-up:** with the namespace bug fixed, the silent
  `catch` in `HekatePublisher.publish_review_session_from_run`
  remains as defense in depth, but the prose summary will now
  populate cleanly for every published record.
- **Tests:** no new tests; this is a pure refactor + ops script.
  Behavior change is observable only at runtime (atproto records
  carry the real summary instead of the fallback).

### v1.35 — Loom demo assets + GROMACS scoping + GROMACSBackend skeleton (2026-05-04)

- **`examples/loom_demo/`** — zero-pre-work record kit for campaign
  asset #1:
  - `methods.txt` — synthesized representative Methods paragraph
    (Abl + imatinib FEP). Clearly marked as a demo input; swap with
    a real paper's Methods before publishing the Loom.
  - `record_session.sh` — exact terminal invocations per the
    scene-by-scene script in `docs/LOOM_DEMO_SCRIPT.md`. Pre-flight
    hint included for warming the JIT.
  - `README.md` — recording checklist, real-paper substitution
    guide (cross-references the `HALLUCINATION_BENCHMARK.md` seed
    set), and the apps-stall rationale for shipping the synthesized
    file at all.
- **`docs/GROMACS_SCOPING.md`** — Phase A weeks 7-9 deliverable
  from the commercial-validation plan. Walks through what the
  GROMACS input deck actually is (`.top` + `.gro` + `.mdp` + `.ndx`
  + shell driver), an MVP coverage map (~70% of published-paper
  protocols, 1:1 IR mappings for the 8 axes), Phase 2 scope
  (membranes, REMD via `mdrun -multidir`), explicitly-deferred
  pieces (alchemical FEP — its own dialect; metadynamics — needs
  GROMACS-PLUMED compile; CpHMD — moving target), and structural
  incompatibilities (Molly autodiff). Closes the TAM-cap argument
  flagged in the salt-mines verdict by Tier-2 personas.
- **`src/backends/GROMACSBackend.jl`** — scaffolding only. Implements
  `supported_features`, `validate_spec` (rejects out-of-MVP specs
  with clear "use OpenMM" / "deferred to Phase 2" messages), and
  `estimate_resources`. `render_script` / `prepare` / `preview_run`
  / `run!` raise "not yet implemented" pointing at the scoping doc.
  Wired into `Crucible.jl` includes + exports. Renderer body lands
  alongside the first pilot that asks for it.
- Tier-2 cold-email template upgrades from "Crucible's deliverable
  is OpenMM" to "OpenMM primary; GROMACS scoped, lands with the
  first pilot that asks for it" — a meaningful pharma-conversation
  upgrade that ties scope expansion to pilot pull rather than
  speculative build.
- Tests: 95/95 Python unchanged. Julia full-suite still blocked on
  the pre-existing Manifest.toml ownership/version mismatch (v1.33
  follow-up). GROMACSBackend syntax-checked via `Meta.parseall`.

### v1.34 — Loom demo script + ON_PREM.md (2026-05-04)

Two campaign assets shipped, both gating Phase A outreach in
`docs/COMMERCIAL_VALIDATION_PLAN.md`.

- **`docs/LOOM_DEMO_SCRIPT.md`** — 60-second demo script for
  campaign asset #1. Scene-by-scene narration + visual cues, asset
  checklist (real paper PDF, methods.txt sidecar, terminal theme,
  mic), re-record triggers (CLI surface change, benchmark publishes,
  on-prem ships), and three tier-aware variants (60s default, 75s
  for pharma, 50s for academic). Distribution map covers cold-email
  embed (asset #6), Twitter/X (asset #3), landing page (asset #9),
  Practical Cheminformatics guest post (asset #5), ACS COMP
  submission (asset #8). Recording is the user's job; the script is
  the gate.
- **`docs/ON_PREM.md`** — campaign-grade documentation of
  on-prem mode. Phase A weeks 4-6 deliverable; the doc that
  unblocks the pharma IP-policy conversation. Quickstarts for
  Ollama, vLLM, and llama.cpp; model-selection guide
  (Qwen2.5-Coder 7B → 32B, Llama 3.1 70B); explicit hard
  guarantees (no third-party API call, no telemetry, deterministic
  rendered scripts, no auto-update phone-home); explicit
  *non*-guarantees (model-weight provenance, OpenMM-conda updates,
  per-server LLM logging); a network-policy preflight script
  pharma security teams can hand to their auditors; 30-day POC
  scope ($5K-$15K, fixed fee, written eval).
- **No code changes.** `LocalProvider` (`src/llm/LocalProvider.jl`,
  ~95 lines) was already shipped — turns out Phase A weeks 4-6 was
  blocked on the *doc*, not the code.
- Tests: 95/95 Python + 868/868 Julia unchanged (pure docs).

### v1.33 — hekate AT Protocol integration (2026-05-04)

- **`src/atproto/`** — new `Crucible.ATProto` module: an AT-Protocol
  record-authoring layer scoped to `app.hekate.*` records (paper-review
  session announcements). Surface includes a HekateConfig (env +
  `~/.config/crucible/hekate.toml` overlay), an XRPC client
  (createSession + create/get/list/deleteRecord with one-time 401 retry
  and an injectable HTTP transport for tests), a hand-rolled validator
  against four vendored Hekate lexicons (venue / slot / recurrence /
  event), typed builders (`build_venue` / `build_slot` /
  `build_recurrence` / `build_event`) that validate before returning, a
  one-time bootstrap (`bootstrap_venue!` + `create_slot!`), and a
  `publish_review_session_from_run` hook wired into `cmd_run` so a
  successful simulation can announce a review session over AT Protocol.
- **CLI**: new `crucible hekate {bootstrap-venue, create-slot,
  publish-event, doctor}` subcommand. HELP_TEXT updated.
- **`tools/sync-lexicons.jl`** — vendor `app.hekate.*` lexicons from
  `~/Projects/hekate/lexicons/app/hekate/` into `src/atproto/schemas/`,
  with sha256 receipts that catch local edits. (Agent fixed a bug
  where the receipt comparator was comparing `<hex>  <name>` against
  bare hex and always tripping the local-edit guard.)
- **Live publishing is double-gated.** Default is dry-run (no network
  side effects). To publish: set `CRUCIBLE_HEKATE_PUBLISH_EVENTS=1`
  AND have a cached venue+recurrence URI from a prior bootstrap.
- 47 atproto-specific tests pass in an isolated environment that
  mounts `src/atproto/` against a stub `Crucible` module.
- **Known issues (deferred to v1.34):**
  - `Manifest.toml` is root-owned and pinned to Julia 1.10.11; the
    local toolchain is Julia 1.12.5 and `Pkg.instantiate` fails
    resolving `Statistics 1.10`. **Pre-existing**, unrelated to this
    feature, but the full Crucible test suite can't run on this
    machine until the manifest is regenerated. Run
    `sudo chown frosty Manifest.toml && rm Manifest.toml && julia --project -e 'using Pkg; Pkg.instantiate()'`
    to fix.
  - `HekatePublisher.publish_review_session_from_run` references
    `Crucible._explain_spec`, but `_explain_spec` is defined in
    `Crucible.CLI` (`src/cli/CLI.jl:1073`), not `Crucible`. The call
    is wrapped in try/catch so the description silently falls back
    to "Crucible run." Follow-up fix: lift `_explain_spec` (and
    `_stage_one_liner`) out of CLI.jl into a shared `src/spec/Explain.jl`
    that both CLI and atproto can import.
- Tests: 868 + 47 atproto Julia (the latter run in isolation only,
  pending manifest fix); 95/95 Python unchanged.

### v1.32 — corpus ↔ benchmark bridge (2026-05-04)

- **`python/crucible/corpus/store.py`** — adds `find_by_doi(doi)` and
  `paper_text_for_doi(doi)` accessors. `find_by_doi` accepts both bare
  (`10.1000/x`) and URL-form (`https://doi.org/10.1000/x`) DOIs and
  matches case-insensitively. `paper_text_for_doi` returns
  `title + abstract` for benchmark feeding.
- **`python/crucible/benchmark/cli.py`** — `benchmark run` now accepts
  `--corpus-db <path>`. Resolution order for paper text:
  1. `<papers-dir>/<paper_id>.txt` sidecar (Methods-section, best signal)
  2. corpus DB by DOI (title + abstract, medium signal)
  3. `entry.title` (worst-case fallback)
- **End-to-end smoke verified.** Seeding the corpus with one of the
  benchmark seed-set DOIs + abstract, then running the benchmark with
  `--corpus-db`, produces a real JSONL output where the LLM (mock
  transpile against the vanilla template) is scored against the
  expected protocol on 6 of 8 axes. Pipeline ready for live LLM input
  the moment the seed-set entries are human-verified.
- Tests: 95/95 Python (was 87; +8 covering DOI normalization,
  title-only fallback, parser arg presence, end-to-end seed-set
  compatibility); 868/868 Julia unchanged.

### v1.31 — hallucination benchmark framework (2026-05-04)

- **`python/crucible/benchmark/`** — Phase A weeks 2-3 deliverable
  from `docs/COMMERCIAL_VALIDATION_PLAN.md`. End-to-end framework for
  measuring LLM protocol-extraction accuracy:
  - `papers.py` — `BenchmarkEntry` + `ExpectedProtocol` dataclasses;
    seed set of 5 canonical MD papers (Lindorff-Larsen 2010,
    Mobley/Chodera/Dill 2007, Sugita & Okamoto 1999, Wang 2015 FEP+,
    Salomon-Ferrer 2013), all marked `needs_verification` until a
    human reads the source. The framework refuses to score unverified
    entries unless `allow_unverified=True` is passed — fabricated
    ground truth is the worst possible failure mode (per the
    technical-feasibility expert in the salt-mines verdict).
  - `scorer.py` — 8 binary axes (protein FF, water model, ensemble,
    dt, T, duration, pressure, FEP λ-count). No partial credit.
    `None` ground truth drops the axis from both numerator and
    denominator.
  - `runner.py` — transpile-callback agnostic; pass any
    `(text) -> MDSpec` callable. Defaults to subprocess via
    `cli_bridge.transpile`; tests inject a mock so CI doesn't pay
    for live LLM tokens.
  - `reporter.py` — markdown report generator suitable for
    `docs/HALLUCINATION_BENCHMARK.md` or direct paste into a blog
    post / arXiv preprint (campaign asset #2 + #4 in
    `docs/CAMPAIGN_2026Q2.md`).
  - `cli.py` — `python -m crucible benchmark {list,status,run,report}`
    subcommands. Wired into the top-level dispatcher.
  - 15 new pytest tests covering scorer correctness, runner error
    handling, reporter rendering. **87/87 total pytest pass** (was 72).
- **`docs/HALLUCINATION_BENCHMARK.md`** — public landing page for
  the benchmark. Methodology, scope, honesty constraints (no
  fabricated ground truth, no cherry-picking, flag pretrained-on-the-
  paper effects), seed-set list, reproduce instructions,
  add-a-paper checklist.
- The benchmark **deliberately ships with seed entries marked
  `needs_verification`** so the first published numbers are the
  human-verified ones. Smoke runs with mock transpile work
  end-to-end; real LLM runs unblock as soon as the verification
  pass completes (Phase A weeks 2-3).
- Tests: 87/87 Python (was 72; +15); 868/868 Julia unchanged.

### v1.30 — python-for-app-layer musing (2026-04-30)

- **`musings/python_for_app_layer.md`** — evaluation of Python on
  two axes (performance + stall-avoidance):
  - **Performance: neutral.** Hot paths are subprocesses (OpenMM
    via rendered script) or C++/FFI (DuckDB, JSON Schema validators);
    the orchestration-layer language barely moves the throughput
    needle. Cold-start asymmetry favors Python (~50 ms vs Julia
    TTFX), but Crucible's CLI uses PackageCompiler AOT to mostly
    close that. Not a reason to use Python; not a reason against.
  - **Stall-avoidance: Python materially wins.** Web hosting
    (Streamlit Cloud / HF Spaces / Fly.io / Render), packaging
    (`pip install` is path-of-least-resistance), error reporting
    (Sentry SDK), telemetry (OpenTelemetry SDK), dashboard
    frameworks (Streamlit / Gradio / Panel), and contributor
    pipelines are all an order of magnitude more mature than the
    Julia equivalents. The asymmetry is about deploy-ecosystem
    maturity, not language quality.
  - **Recommendation: formalize the split that's already
    happening.** Library stays in Julia (IR, validation, renderers,
    LLM transpile, scientific test suite); app / UI / deploy layer
    drifts toward Python (v1.24 bindings, v1.29 corpus GUI as
    empirical evidence). Subprocess is the seam, exactly as
    `why_subprocess_over_pythoncall.md` argued. Adding new Python
    services on top is purely additive; no Julia code changes.
  - Three triggers for revisiting documented (Pluto cloud-deploy
    lands, Julia web framework hits Streamlit ergonomics,
    contributors prefer single-language ownership).
  - Defended against the "slippery slope to Python for everything"
    concern: the library's hard contract (IR + schema + 5 gates)
    is language-symmetric by test; the app layer has no hard
    contract beyond "consume the IR"; the subprocess seam is
    mechanical, not discipline-based; the base `crucible` install
    stays lean (extras are opt-in).
- Tests: 868/868 Julia + 72/72 Python unchanged (pure docs).

### v1.29 — corpus feature (OpenAlex + DuckDB) + Streamlit GUI (2026-04-30)

- **`docs/CORPUS_DESIGN.md`** — design + standalone-vs-integrated
  evaluation. Recommends OpenAlex (primary) + Semantic Scholar
  (secondary) for the data source, DuckDB with adjacency tables for
  storage (rejects Neo4j / Memgraph / Apache AGE / Kuzu as overkill
  for the corpus size), and **in-Crucible Phase 1 / standalone Phase
  2 if it earns it** for the host. Module is designed
  standalone-shaped from day 1 so the future `corpusquest` lift is
  a `git mv` away. Trigger conditions for the lift documented.
- **`python/crucible/corpus/`** — Phase-1 Python implementation:
  - `openalex.py` — OpenAlexClient (urllib-based, polite pool via
    `CRUCIBLE_OPENALEX_EMAIL`); `Author`, `Work`, `WorkAuthor`
    dataclasses; abstract reconstruction from OpenAlex's inverted
    index; concept resolution for filtering.
  - `store.py` — DuckDB-backed `CorpusStore` with adjacency-table
    schema (works, authors, work_authors, work_references, concepts,
    work_concepts) and queries: `papers_by_author`, `coauthors`
    (ranked by shared-work count), `papers_citing_author`,
    concept-filter, `stats`.
  - `cli.py` — subcommands `fetch`, `papers`, `coauthors`, `stats`,
    `ui`. Wired into `python -m crucible corpus …` via the existing
    bindings entry point.
  - `ui.py` — **Streamlit GUI** (single file). Three tabs (Papers,
    Coauthors, Citation neighborhood), sidebar with DB-path picker
    + fetch-new-author form + live stats, JSONL export of the
    current paper view, opt-in via `pip install crucible[corpus,ui]`.
  - `schema.sql` — DuckDB schema (mirrored as Python statements in
    `store.py` for runtime; the file is the source of truth for
    documentation + future migrations).
- **`python/pyproject.toml`** — adds two optional-dependency groups:
  `corpus` (just duckdb) and `ui` (streamlit + duckdb). The base
  `crucible` install stays lean.
- **Tests** — `test_corpus_openalex.py` (mocked HTTP for the API
  client), `test_corpus_store.py` (in-memory DuckDB for the schema
  + queries), `test_corpus_cli.py` (CLI dispatcher). 72/72 pytest
  tests pass (was 50; +22 for corpus + GUI surface).
- The corpus directly unblocks Phase A weeks 2–3 of
  `docs/COMMERCIAL_VALIDATION_PLAN.md` (the 20-paper hallucination
  benchmark) and feeds per-persona paper lists for the Q2
  campaign cold-email personalization.

### v1.28 — campaign AI-receptivity sub-ranking (2026-04-29)

- **`docs/CAMPAIGN_2026Q2.md`** — added a new section sub-ranking
  the named personas by likely receptivity to *software that's
  mostly built by AI* (Crucible's actual provenance). Ranking based
  on public posture (papers, blogs, employer signal):
  1. **Brooke Husic** (Princeton; formerly Anthropic) — earliest
     critical-feedback target.
  2. **Frank Noé** (Microsoft AI for Science / FU Berlin) — highest
     conceptual alignment.
  3. **Patrick Walters** (Relay; *Practical Cheminformatics*) —
     highest-leverage industry-CADD megaphone.
  4. **Tom Miller** (Iambic Therapeutics) — best strategic-bridge
     persona.
  Plus honorable mentions (Deane, Greener, Koller). Captures the
  **receptivity-discernment trade-off**: high-AI-fluency audiences
  are also the most discerning, so the sequencing rule is "reach
  out *after* the hallucination benchmark publishes (Phase A week
  4), not before." AI-receptivity ≠ low bar; it means "familiar
  enough to evaluate fairly."
- Tests: 868/868 unchanged (pure docs).

### v1.27 — 2026-Q2 advertising campaign (LinkedIn + GitHub-grounded targeting) (2026-04-29)

- **`docs/CAMPAIGN_2026Q2.md`** — concrete creative + targeting plan
  that operationalizes Phase A of `docs/COMMERCIAL_VALIDATION_PLAN.md`.
  Covers: positioning (one sentence + one paragraph; wedge =
  provenance + 5-gate validator, not "LLM that writes code"),
  GitHub-grounded ecosystem snapshot (OpenMM 1.9k stars, Molly.jl
  475, OpenFF Toolkit 392, openmmtools 319, all verified
  2026-04-29), 3-tier key-figures map (10 academic OSS leads, 8
  pharma CADD personas, 7 conference / community surfaces),
  three-message stack (academic / pharma / founder-narrative),
  10-asset deliverable matrix sized against 8 hr/week founder
  bandwidth (Loom demo, hallucination benchmark page, X thread,
  arXiv preprint, Practical Cheminformatics guest post, cold-email
  templates, on-prem doc, ACS COMP submission, landing rewrite,
  OSS hygiene release), week-by-week channel strategy aligned to
  Phase A weeks 1–13, founder-fillable cold-email templates for
  PI + CADD variants, honest constraints (no fabricated traction,
  no paid ads, no spamming, on-prem mode is pharma prerequisite),
  KPI dashboard for the week-13 review.
- The doc identifies public-figure targeting **personas only**; no
  contact info or email addresses listed. Founder assembles cold
  lists from public surfaces.
- Tests: 868/868 unchanged (pure docs).

### v1.26 — commercial-validation plan (salt-mines findings) (2026-04-29)

- **`docs/COMMERCIAL_VALIDATION_PLAN.md`** — 180-day operational plan
  that sits below the strategic 18-month `docs/ADOPTION_PLAN.md`.
  Built directly on the salt-mines portfolio-evaluator verdict from
  `~/Projects/salt-mines/reports/run-2026-04-28.md` (4-expert panel:
  financial / risk / market / technical-feasibility). Captures:
  source verdict (E=1.99×, p10=0.085, p50=0.96×, p90=8.25× — best
  in the 7-project portfolio; modal outcome 45% stall on
  zero-pipeline + 8-hrs/week bandwidth); 6-month commercial gate
  (one signed LOI or paid pilot by 2026-10-29 or pivot to Phase
  2a/2b academic/OSS path); $5K spend cap tranched into three
  release gates; week-by-week Phase A (90-day commercial sprint —
  outreach, 20-paper hallucination benchmark, conditional local-LLM
  mode, GROMACS exporter scoping, pilot push); Phase B (90–180-day
  pilot-conversion-or-pivot, parallel tracks); three explicit kill
  criteria (no LOI, per-eval cost > $2, founder hours sustained
  >12/week); honest list of what the plan *doesn't* do (no
  fundraising, no hiring, no self-serve, no new IR features). The
  pivot-to-OSS path is treated as the modal-30% scenario, not a
  failure mode — the artifact remains citable regardless.
- Tests: 868/868 unchanged (pure docs).

### v1.25 — why-not-protobuf musing (2026-04-29)

- **`musings/why_not_protobuf.md`** — durable record of the
  protobuf-instead-of-JSON-Schema question. Conclusion: no for the
  IR. The single load-bearing axis is LLM-friendliness — Anthropic
  tool-use binds JSON Schema as `input_schema`, and no major LLM
  provider treats protobuf as a structured-output format. Other
  losses: human-readable templates (`cat`-able), JSONL transcripts
  (option-3 fine-tune flywheel runs on `jq`/`grep`), the sparse
  `provenance` map's natural JSON shape, and the hand-port
  advantage in both Python and Julia (codegen wouldn't replace
  the validation/lint/migration/template layers anyway). Specs are
  kb-scale, so wire-format compactness buys nothing the workload
  notices. Two narrower places protobuf could legitimately land:
  (1) the future RPC envelope if `crucible serve` ever fronts a
  typed daemon, with the IR body still JSON; (2) `quicktype` from
  `schema.json` covers the auto-generated-bindings case for
  languages without a hand port — no `.proto` required. Four
  triggers for revisiting documented (specs into MB range,
  RPC daemon becomes load-bearing, LLM tooling shifts away from
  JSON, protobuf-native scientific-computing community emerges).
- Tests: 868/868 (pure docs).

### v1.24 — Python bindings (Phase 2b Path 3) + architecture diagrams + power-user docs (2026-04-29)

- **`python/`** — pure-Python bindings. Phase 2b Path 3 from
  `musings/ecosystem_alternatives.md`. Pydantic-typed `MDSpec` plus a
  full port of validation gates 1+2, lint + provenance coverage,
  schema migrations (0.1.0 → 0.2.0 → 0.3.0), and all 13 templates.
  Heavy operations (render, run, serve, events, diff) shell out to
  the Julia CLI via `crucible.cli_bridge`, extending the
  subprocess-as-integration-boundary pattern from
  `musings/why_subprocess_over_pythoncall.md` symmetrically in both
  directions. Pure-Python users can build, mutate, validate, lint,
  and round-trip MDSpecs without Julia installed. The canonical
  `src/spec/schema.json` is loaded by both languages; cross-language
  consistency is the load-bearing invariant.
  - `python/pyproject.toml` — pydantic ≥ 2.5, jsonschema ≥ 4.20,
    Python ≥ 3.10. `crucible-py` console script for module-mode CLI.
  - `python/crucible/spec.py` — pydantic models with strict enums,
    discriminated `Stage` union, `extra="forbid"` on every model so
    unknown fields raise (mirrors Julia's reject-on-unknown).
  - `python/crucible/validate.py` — Gate 1 (`jsonschema`) +
    Gate 2 (17 semantic rules ported one-for-one).
  - `python/crucible/coverage.py` — `provenance_coverage`,
    `coverage_score`, `lint` with all 9 lint rules.
  - `python/crucible/migrate.py` — registry-based forward migrations
    matching Julia exactly.
  - `python/crucible/templates.py` — 13 templates (vanilla, smiles,
    protein_ligand_fep, remd, membrane, metadynamics + 3 cancer
    + 2 materials + 2 protein-engineering) with the same provenance
    enrichment as the Julia side.
  - `python/crucible/cli_bridge.py` — subprocess wrapper for
    render/run/health/events/diff/info/doctor; honors
    `CRUCIBLE_BIN`, `CRUCIBLE_SEED`, `CRUCIBLE_PRECISION`, etc.
  - `python/crucible/__init__.py` — top-level convenience API:
    `crucible.validate(spec)`, `crucible.render(spec, "openmm")`,
    `crucible.run(spec, workdir=…)`, `crucible.health(spec)`,
    `crucible.events(workdir)`, `crucible.lint(spec)`,
    `crucible.templates.init(name)`.
  - `python/crucible/__main__.py` — `python -m crucible` for
    pure-Python ops (validate / lint / templates / migrate).
  - `python/tests/` — 50 pytest tests covering spec round-trip,
    validate gates, lint, migrate, and the template registry. All 50
    pass against the canonical schema.
- **`docs/ARCHITECTURE.md`** — Mermaid systems diagrams (GitHub renders
  natively): pipeline-at-a-glance, five-gate validation, IR-as-contract
  cross-language layout, subprocess-boundary topology,
  adoption-plan-phase mapping, and a single-timestep sequence diagram.
  Visual companion to the existing musings + `docs/PLAN.md`.
- **`docs/POWER_USERS.md`** — onboarding handbook for contributors who
  need to extend Crucible: adding a stage type (9-step checklist
  spanning IR + schema + migrations + gates + coverage + renderers +
  Python port + templates + tests), adding a lint rule, adding a
  template, bumping the schema, adding a CLI subcommand, custom LLM
  providers, CI integration patterns (GitHub Actions / Woodpecker /
  pre-commit hook), Python-bindings usage, and "what does the IR
  look like?" — the question every new feature has to answer first.
- Schema, gates, lint, migrations, and templates are now defined
  identically in two languages with one canonical schema. A schema
  bump becomes a coordinated PR across both ports.
- Tests: Julia 868/868 unchanged; Python 50/50 pass on first run.

### v1.23 — ecosystem-alternatives musing (2026-04-29)

- **`musings/ecosystem_alternatives.md`** — broader version of the
  Mojo question (`why_not_mojo.md`): "is Julia the right ecosystem
  at all?" Evaluates Python, Rust, Go, TypeScript, C++, Mojo, Nim,
  and others against Crucible's actual workload. Conclusion:
  Python is the only ecosystem that's a real alternative;
  everything else is meaningfully worse on multiple axes. The
  greenfield Julia-vs-Python decision today would be closer than
  it was when the project started, but the right move forward is
  Python *bindings* (Phase 2b in `docs/ADOPTION_PLAN.md`), not a
  port. Three implementation paths for bindings analyzed in
  increasing cost order:
  1. **Subprocess-only client** (~2 weeks)
  2. **PythonCall.jl bridge** (~6 weeks)
  3. **Re-implement IR + validation in Python** (~8 weeks; recommended)
  Polyglot architecture (IR in Rust, CLI in Go, …) considered
  and rejected — multiplies contributor-onboarding cost without
  improving any underlying tradeoff.
- Tests: 868/868 (pure docs).

### v1.22 — why-not-mojo musing (2026-04-29)

- **`musings/why_not_mojo.md`** — analytical record of the
  Julia → Mojo migration question. Conclusion: don't migrate
  (performance argument doesn't apply since the hot path is the
  OpenMM/Molly subprocess; Python-interop argument is moot since
  the project deliberately uses subprocess per
  `why_subprocess_over_pythoncall.md`; ecosystem cost is
  substantial — Molly.jl, Pluto.jl, JSONSchema.jl, HTTP.jl, the
  test suite + 868 tests). Three explicit triggers under which
  the answer would change: a Mojo-native MD engine that beats
  OpenMM, Mojo wins AI/ML standardization, Modular licensing
  shift. The "partial adoption" question (could a Mojo backend
  consume Crucible's IR?) gets a clean answer: yes — that's the
  IR-as-contract bet working as designed; a Mojo-side renderer
  is a separate tool, not a core migration.
- Tests: 868/868 (pure docs).

### v1.21 — scaling musing + 18-month adoption plan (2026-04-29)

Strategy doc surface. Two complementary artifacts: an analysis
(durable, ADR-shaped) and a plan (operational, with milestones).

- **`musings/scaling_modes.md`** — analysis of how Crucible scales
  in three modes: academia (PhD-student-led, citation-moat-bound,
  Julia-friction-limited), private business (open-core + hosted
  runtime, pharma-enterprise, vertical SaaS, consulting — each
  with sketched ARR ceilings and named comparables), and open
  source (architecture-friendly, maintainer-bus-factor-bound,
  Julia-community-size-limited). Plus cross-mode dynamics
  (academia → OSS feeder, OSS → business open-core funnel, etc.)
  and the honest "the bottleneck is maintainer time, not
  architecture or market" conclusion.
- **`docs/ADOPTION_PLAN.md`** — operational 18-month plan with
  three phases:
  - **Phase 0 (0–3 months)**: stabilize. Tag v1.0.0, JuliaRegistry,
    onboarding QA, MAINTAINER_RUNBOOK.md, bus-factor mitigation.
  - **Phase 1 (3–9 months)**: citation moat. JOSS submission,
    end-to-end case study, conference presence, Zenodo DOI.
  - **Phase 2 (9–18 months)** branches based on what's working at
    the 9-month gate: 2a (academic), 2b (OSS-vibrant), 2c
    (business with co-founder + funding decision), or graceful
    step-down if all three signals are weak.
  Constraints: one full-time maintainer, no external funding
  committed. Phases 0 and 1 are sequential and unconditional;
  Phase 2 is decision-gate-driven.
- README + musings/README cross-link both.
- Tests: 868/868 (no code changes — pure documentation).

### v1.20 — glossary + interactive five-gate study notebook (2026-04-29)

Pedagogical surface filled in further. `HOW_TO_READ.md` (v1.18) +
`USE_CASES.md` (v1.17) + `VISUALIZATION.md` (v1.19) give cross-field
readers an entry point; this release adds the vocabulary lookup and
a hands-on validation-pipeline walkthrough.

- **`docs/GLOSSARY.md`** — cross-field vocabulary covering MD
  (ensemble/timestep/PME/Rg/RMSD/FEP/REMD/CV/MBAR/checkpoint),
  drug discovery (Kd/Ki/IC50/ΔG/ΔΔG/kinase/GPCR/RTK/PPI/paratope/
  ADMET), materials (polymer/electrolyte/SEI/D/EAM/ReaxFF/QM-MM),
  quantum (electronic structure/CCSD(T)/DFT/VQE/QPE/fault-tolerance/
  ML-potentials), LLM tooling (structured output/provenance/
  hallucination/JSON Schema/fine-tuning/few-shot), and
  Crucible-internal terms (MDSpec/Stage/SystemSource/five gates/
  flywheel/v2 IR scaffolding/the five hard rules).
- **`examples/study_validation_gates.jl`** — Pluto notebook walking
  through the five-gate validation pipeline interactively. Three
  guided mutations (bad FF name → Gate 1, NPT without barostat →
  Gate 2, ligand without topology → Gate 3) plus a "whole pipeline
  at once" section showing the fail-fast invariant. Ends with a
  "what you've learned" checklist.
- `HOW_TO_READ.md` cross-links both above. Examples README adds
  the study notebook to its index.
- Tests: 868/868 (no code changes — pure documentation +
  notebook).

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
