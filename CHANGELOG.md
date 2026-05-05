# Changelog

## Unreleased

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
