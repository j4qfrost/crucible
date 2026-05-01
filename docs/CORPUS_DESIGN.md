# Corpus design — fetch + index whitepapers by author

Design + evaluation for a feature that lets Crucible fetch the
papers authored or coauthored by a named researcher, store them in
a graph-shaped local DB, and feed them into the LLM-transpile
pipeline. The motivating use cases are concrete:

- The **hallucination benchmark** (`docs/COMMERCIAL_VALIDATION_PLAN.md`
  Phase A weeks 2–3) needs ~20 published MD papers with known
  ground-truth protocols, drawn from named researchers' bibliographies.
- The **option-3 fine-tune flywheel** (`docs/ADOPTION_PLAN.md` Phase
  4) wants ~1,000 `(paper, MDSpec)` pairs; the corpus is the
  natural feeder.
- The **Q2 advertising campaign** (`docs/CAMPAIGN_2026Q2.md`) needs
  per-persona paper lists for cold-email personalization.

This document answers four questions:

1. Which paper/author database should we integrate with?
2. How do we represent the data — graph DB or relational + adjacency
   tables?
3. Should this live inside Crucible or as a standalone app?
4. What's the minimum viable version that unblocks the benchmark?

## Question 1 — Which database to integrate with

| Source | Coverage | API auth | Rate limits | Graph-shaped natively | Verdict |
|---|---|---|---|---|---|
| **OpenAlex** | ~250 M works; authors, institutions, concepts, citations | None (free) | 10 req/s polite pool with `mailto=…` | Yes (author-IDs, work-IDs, concept-IDs are first-class graph nodes) | **Primary backend** |
| **Semantic Scholar** | ~200 M works; influential-citation count, abstracts, TLDRs, embeddings | API key (free) | 1 req/s without key, 100/s with key | Yes (paper + author graph) | **Secondary** — useful for influential-citation enrichment + TLDR fallback |
| **arXiv** | ~2.4 M preprints; full PDFs | None | 1 req per 3s | No (flat metadata) | Tertiary — for direct-PDF fetch when DOI resolves to arXiv |
| **bioRxiv / medRxiv** | ~250 K bio preprints; full PDFs | None (already wired via the user's bioRxiv MCP) | Modest | No (flat) | Tertiary — same role for biology preprints |
| **Europe PMC** | Open subset of PubMed Central | None | 10 req/s | Partial | Optional — useful for full-text in biology |
| **CrossRef** | DOI metadata | None | 50 req/s polite | No | Optional — DOI canonicalization |
| **PubMed E-utilities** | Biomedical literature | None | 3 req/s, 10 with key | No | Optional |
| **Google Scholar** | — | — | — | — | **Not viable**: no public API |
| **Lens.org** | Patents + scholarly | API key | Tiered | Partial | Defer — paid tiers eventually |

**Recommendation: OpenAlex as primary, Semantic Scholar as
secondary.** OpenAlex's data model is graph-shaped natively
(author-ID + work-ID + concept-ID + institution-ID are all canonical),
its license is permissive (CC-Zero on metadata), it's the open
replacement for Microsoft Academic Graph, and it has no auth
friction. Semantic Scholar adds influential-citation count and TLDRs
that OpenAlex lacks.

The arXiv / bioRxiv / Europe PMC sources are **tertiary** —
called only when we need the actual PDF or full text after
OpenAlex tells us where it is.

## Question 2 — Graph DB or relational + adjacency tables

The data is graph-shaped: works, authors, citations, concepts,
institutions are nodes; author-of, cites, has-concept,
affiliated-with are edges. The temptation is to reach for Neo4j or
Memgraph.

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Neo4j** | Mature, Cypher is expressive | Heavyweight (JVM), licensing complexity, separate process to manage | Overkill |
| **Memgraph** | Cypher-compatible, lighter than Neo4j | Still a separate process | Overkill |
| **Apache AGE** (Postgres ext.) | Cypher-on-Postgres | Adds a Postgres dep | Overkill given the next option |
| **Kuzu** | Embedded, columnar, Cypher | New, smaller community | Promising — defer |
| **NetworkX** in-memory | Simplest possible | No persistence; size cap ~100 K nodes | Insufficient |
| **DuckDB + adjacency tables** | Already in Crucible's stack; embedded; fast SQL with recursive CTEs; no daemon | Cypher fans grumble | **Recommended** |

**Recommendation: DuckDB with adjacency tables.** Three reasons:

1. **It's already in the project.** Crucible's transcript store is
   DuckDB (`docs/PLAN.md`, `~/.local/share/crucible/transcripts.duckdb`).
   The user's `dart_duckdb` choice in sidequest is the same
   substrate. Adding a separate graph DB is the wrong direction.
2. **Scale fits.** Realistic corpus size is < 1 M works (~10
   researchers × ~50 anchor papers each × 10× citation expansion).
   DuckDB executes 8-hop CTE walks at this size in < 1 s.
3. **The queries are SQL-shaped.** "Papers by author X since 2020,"
   "papers coauthored by X and Y," "papers citing both X's and Y's
   work" — these are joins on adjacency tables, not graph-traversal
   problems. Recursive CTEs cover the rare actual-graph queries.

Schema (DuckDB):

```sql
CREATE TABLE works (
    work_id          TEXT PRIMARY KEY,         -- OpenAlex W… ID
    doi              TEXT,
    title            TEXT,
    abstract         TEXT,
    publication_year INTEGER,
    venue            TEXT,
    cited_by_count   INTEGER,
    is_oa            BOOLEAN,
    pdf_url          TEXT,
    fetched_at       TIMESTAMP
);

CREATE TABLE authors (
    author_id        TEXT PRIMARY KEY,         -- OpenAlex A… ID
    display_name     TEXT,
    orcid            TEXT,
    h_index          INTEGER,
    works_count      INTEGER,
    last_known_inst  TEXT,
    fetched_at       TIMESTAMP
);

CREATE TABLE work_authors (
    work_id          TEXT,
    author_id        TEXT,
    position         INTEGER,
    is_corresponding BOOLEAN,
    PRIMARY KEY (work_id, author_id),
    FOREIGN KEY (work_id)   REFERENCES works(work_id),
    FOREIGN KEY (author_id) REFERENCES authors(author_id)
);

CREATE TABLE work_references (
    citing_work_id   TEXT,
    cited_work_id    TEXT,
    PRIMARY KEY (citing_work_id, cited_work_id)
);

CREATE TABLE concepts (
    concept_id       TEXT PRIMARY KEY,         -- OpenAlex C… ID
    display_name     TEXT,
    level            INTEGER
);

CREATE TABLE work_concepts (
    work_id          TEXT,
    concept_id       TEXT,
    score            DOUBLE,
    PRIMARY KEY (work_id, concept_id)
);

CREATE TABLE institutions (
    institution_id   TEXT PRIMARY KEY,
    display_name     TEXT,
    country_code     TEXT,
    type             TEXT
);

CREATE TABLE work_institutions (
    work_id          TEXT,
    institution_id   TEXT,
    PRIMARY KEY (work_id, institution_id)
);

CREATE INDEX works_year_idx       ON works (publication_year);
CREATE INDEX work_authors_aid_idx ON work_authors (author_id);
CREATE INDEX work_concepts_cid_idx ON work_concepts (concept_id);
```

If a future user wants Cypher, exporting the same tables to Kuzu is
a one-shot script — no architectural commitment lost.

## Question 3 — Standalone app or in-Crucible feature

The honest two-axis evaluation:

| Axis | In-Crucible | Standalone (e.g., `corpusquest`) |
|---|---|---|
| Time-to-first-benchmark | ~1 week | ~3–4 weeks (separate repo, packaging, CI, release cadence) |
| Reuse across the user's portfolio | None | Possible (augury, blizzard-2026 conceivable consumers) |
| Maintenance overhead | Low (extends existing CI) | Medium (separate Project.toml / pyproject, separate releases) |
| Architectural fit | Aligns with `why_subprocess_over_pythoncall.md` if shelled out | Same, with extra hop |
| Onboarding cost for a Crucible user | Zero (already installed) | One more `pip install` or repo to clone |
| OpenAlex relevance to non-Crucible projects | Low — corpora are mostly comp-chem in this lifetime | n/a |

**Recommendation: in-Crucible Phase 1; standalone Phase 2 if it
earns it.** The 8 hr/week founder-bandwidth constraint
(`docs/COMMERCIAL_VALIDATION_PLAN.md`) makes the choice clear:
ship the corpus in Crucible's tree first so the hallucination
benchmark unblocks on schedule. If a second consumer shows up
later (most likely candidate: a Crucible-adjacent academic-NPC
project, or augury picking up scholar-graph features), lift the
module into a sibling repo at that point.

The lift will be cheap because **the corpus module is designed to
be standalone-shaped from day 1**:

- **No imports from `crucible.spec`, `crucible.validate`,
  `crucible.templates`, etc.** The corpus module is self-contained.
- **OpenAlex / DuckDB only.** No Crucible-specific dependencies.
- **Wire format is JSONL** (lists of papers). Easy to consume from
  any language.
- **CLI entry point** (`python -m crucible.corpus fetch …`). When
  lifted, it becomes its own console script.

Concretely the future lift is:

```bash
# Phase 2 (when triggered) — copy the module out, no rewrite
git mv python/crucible/corpus ../corpusquest/corpusquest
# Update import paths; add pyproject.toml; ship.
```

Trigger conditions:

1. A second project (augury / blizzard-2026 / new) wants the
   corpus and the dep is Crucible-only.
2. A third party shows interest in the corpus DB independent of
   Crucible.
3. The corpus grows past ~10 M rows and Crucible's CI doesn't want
   to depend on a database that big.

Until one of these triggers, the corpus stays inside Crucible.

## Question 4 — MVP scope (the phase-1-in-Crucible cut)

The smallest version that unblocks the benchmark + the campaign:

| Capability | In MVP | Notes |
|---|---|---|
| OpenAlex client (search authors, fetch works) | ✅ | Polite-pool with `mailto=` |
| Semantic Scholar fallback for TLDR/abstract | ❌ | Defer |
| arXiv / bioRxiv direct PDF fetch | ❌ | Defer; OpenAlex tells us URLs |
| DuckDB store (works, authors, work_authors, work_references) | ✅ | Skip institutions for MVP |
| `concepts` + `work_concepts` filter | ✅ | Lets us prune to MD papers |
| CLI: `fetch --author NAME` | ✅ | Stores into local DB |
| CLI: `papers --author NAME --since YEAR` | ✅ | Emits JSONL |
| CLI: `coauthors --author NAME` | ✅ | One-hop traversal |
| Graph queries beyond two-hop | ❌ | Recursive CTEs deferred |
| Full-text retrieval | ❌ | Deferred to PDFAdapter integration |
| Embedding-based similarity | ❌ | Deferred |
| GUI for browsing the local DB | ✅ | Streamlit, single file at `python/crucible/corpus/ui.py`, opt-in via `pip install crucible[corpus,ui]` |

Concrete file layout (Phase 1, Python-side):

```
python/crucible/corpus/
  __init__.py            # public API
  openalex.py            # OpenAlexClient (urllib-based, polite pool)
  store.py               # CorpusStore (DuckDB-backed)
  cli.py                 # subcommand dispatch
  ui.py                  # Streamlit GUI (opt-in via [corpus,ui] extra)
  schema.sql             # DuckDB schema (mirrored as Python list in store.py)
python/tests/
  test_corpus_openalex.py   # mocked HTTP
  test_corpus_store.py      # in-memory DuckDB
  test_corpus_cli.py        # CLI dispatcher
```

Launch the GUI:

```bash
pip install crucible[corpus,ui]
python -m crucible corpus ui
# or:  streamlit run python/crucible/corpus/ui.py
```

The GUI is a single-page Streamlit app with three tabs (Papers,
Coauthors, Citation neighborhood), an inline "fetch new author" form
in the sidebar, and a JSONL export button. Read-only against the
local DB except for the fetch form.

The Julia side is a thin wrapper that subprocesses to the Python
CLI for the MVP. A native-Julia OpenAlex client is a follow-up if
the Python path proves friction-rich; the integration boundary
stays at the process layer per
`musings/why_subprocess_over_pythoncall.md`.

## Anti-goals (do not build these in Phase 1)

- Author disambiguation beyond what OpenAlex provides (e.g., two
  "John Smiths" in the same field — OpenAlex's `display_name_alternatives`
  is enough for now).
- Citation-network embedding / centrality scores. Defer until a
  research need surfaces.
- Real-time fetch on every query. Phase 1 fetches once, queries
  the local DB.
- A web UI. The CLI is the surface for Phase 1.
- Cross-source deduplication. OpenAlex already does this; trust it
  for the MVP.

## Implementation contract (for the follow-up PR)

- **Optional dependency.** `duckdb` lives under `[project.optional-dependencies] corpus = [...]` so users who don't need the corpus don't pay for it.
- **Polite-pool email.** `CRUCIBLE_OPENALEX_EMAIL` env var is read
  and added to every request as `mailto=…`.
- **Cache awareness.** Re-fetching an already-cached author is a
  no-op unless `--refresh` is passed.
- **Tests don't hit the network.** All HTTP is mocked in tests; a
  separate live-API smoke is gated behind an env var.
- **JSONL the wire format.** All output is JSONL (one JSON object
  per line) so `jq` / `grep` / fine-tune corpora work without
  bespoke parsers.
- **No fabricated metadata.** If OpenAlex returns nothing, Crucible
  returns nothing; we never invent a paper.

## See also

- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  — Phase A weeks 2–3 are blocked on the corpus shipping.
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) — Tier-1 / Tier-2
  persona paper lists are corpus consumers.
- [`musings/why_subprocess_over_pythoncall.md`](../musings/why_subprocess_over_pythoncall.md)
  — the integration-boundary rule that keeps the Phase-1 / Phase-2
  lift cheap.
- [OpenAlex API docs](https://docs.openalex.org/) — the primary
  data source.
