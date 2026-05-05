# User profile — data engineer / MLOps

> **You leave with:** a JSONL data layer of `(paper_text, MDSpec,
> validation_outcome, score)` tuples plus the schema-versioned
> migration story to keep them loadable across schema bumps. Designed
> for the option-3 fine-tune flywheel
> ([`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 4) — the data
> layer that lets a future fine-tuned chemistry-MD model drop in.

This profile is for someone whose job description is closer to
"data infrastructure" than "molecular dynamics." Could be:

- An MLOps engineer at a pharma whose CADD team is using Crucible
  and wants the transcript store integrated with their existing
  data pipeline (Snowflake, BigQuery, Postgres, etc.).
- A research-software engineer at an academic lab building a
  curation pipeline for a paper-MD-protocol training corpus.
- An infrastructure lead at a startup planning to fine-tune an
  open-weights model on Crucible's transcript data.
- A maintainer of a BlazingMQ-style streaming layer who wants to
  feed Crucible's event stream into Kafka / Pulsar / similar.

The wedge: every layer of Crucible's data flow is JSON-serializable,
schema-versioned, and migration-safe. You can build on top without
touching MD-domain code.

## Pre-flight (1 hour)

What you need:

- DuckDB CLI (`brew install duckdb` or
  `pip install duckdb`). All Crucible data lives in DuckDB files.
- Working install of Crucible
  ([`docs/USER_PROFILE_GRAD_STUDENT.md`](USER_PROFILE_GRAD_STUDENT.md)
  pre-flight). You don't need to run any MD; you're plumbing the
  data layer.
- Familiarity with JSON Schema, JSONL, schema migrations. Crucible
  uses these as first-class concepts, not afterthoughts.

Useful background reads (skim, don't deep-read):

- [`docs/CORPUS_DESIGN.md`](CORPUS_DESIGN.md) — the corpus + runs
  data layer design.
- [`musings/why_ir_as_contract.md`](../musings/why_ir_as_contract.md)
  — why everything is JSON.
- [`musings/why_not_protobuf.md`](../musings/why_not_protobuf.md)
  — why it stays JSON.

## The 30-minute path — surveying the data layer

Crucible has three persistent data stores. Walk through each:

### 1. Transcript store (the LLM call log)

```bash
ls ~/.local/share/crucible/transcripts.duckdb 2>/dev/null \
    || crucible transpile --paper /tmp/some-methods.txt --provider local

duckdb ~/.local/share/crucible/transcripts.duckdb \
    "SELECT name FROM sqlite_master WHERE type='table';"
duckdb ~/.local/share/crucible/transcripts.duckdb \
    "SELECT * FROM transcripts LIMIT 1;"
```

What's there: every `crucible transpile` call writes one row with
`(paper_text, spec_json, raw_response, provider, model,
schema_version, timestamp)`. This is the raw input for the
option-3 flywheel.

### 2. Corpus store (paper / author / citation graph)

```bash
duckdb ~/.local/share/crucible/corpus.duckdb \
    "SELECT name FROM sqlite_master WHERE type='table';"
# Returns: works, authors, work_authors, work_references,
#          concepts, work_concepts, benchmark_scores
```

Schema: see
[`python/crucible/corpus/schema.sql`](../python/crucible/corpus/schema.sql)
and the runtime mirror in
[`python/crucible/corpus/store.py`](../python/crucible/corpus/store.py).
Adjacency-tables-as-graph design — see
[`docs/CORPUS_DESIGN.md`](CORPUS_DESIGN.md) for why we picked DuckDB
over Neo4j/Memgraph at this size.

### 3. Benchmark runs store

```bash
# Same DuckDB file by default; benchmark_runs is a separate table.
duckdb ~/.local/share/crucible/corpus.duckdb \
    "SELECT * FROM benchmark_runs LIMIT 5;"
```

Schema: see
[`python/crucible/benchmark/runs_store.py:_SCHEMA_STATEMENTS`](../python/crucible/benchmark/runs_store.py).
Per `(run_id, paper_id)` pair: the LLM provider, the per-axis
breakdown JSON, the schema_version the run happened under.

## The first-week path — building the pipeline

### Day 1-2: export to your warehouse

The runs store has a JSONL exporter:

```bash
python -m crucible benchmark export-jsonl ~/.local/share/crucible/corpus.duckdb \
    --out ~/exports/runs-2026-Q2.jsonl
```

The JSONL is the wire format. Snowflake / BigQuery / Postgres / Spark
all consume it natively. For the corpus tables (works, authors,
etc.), use DuckDB's COPY:

```bash
duckdb ~/.local/share/crucible/corpus.duckdb \
    "COPY (SELECT * FROM works) TO '~/exports/works.parquet' (FORMAT 'parquet');"
```

Parquet keeps the column types intact across the warehouse boundary;
JSONL erases them.

### Day 3-4: schema migration on incoming records

The migration framework
([`python/crucible/migrate.py`](../python/crucible/migrate.py)) is
the answer to "how do we keep historical transcripts loadable when
the IR bumps?":

```python
from crucible import migrate_json

# Old transcript, captured under v0.1.0 — still loadable post-v0.4.0.
old_json = open("~/old-transcript.json").read()
current_json = migrate_json(old_json)   # walks the chain to current
```

The chain is in `python/crucible/migrate.py` (Python) +
`src/spec/Migrations.jl` (Julia, identical semantics). Both sides
add their migrations together; the cross-language consistency test
([`python/tests/test_cross_language_consistency.py`](../python/tests/test_cross_language_consistency.py))
catches drift.

For your warehouse: keep historical JSONL exports; on schema bump,
re-export by walking through `migrate_json` first. This is what
preserves the "every transcript ever captured is still trainable"
invariant.

### Day 5-6: build a fine-tune corpus

For the option-3 flywheel, the canonical input format is JSONL with
one row per `(paper_text, expected_mdspec_json)` pair. The runs
store has the raw materials:

```bash
# All scored runs at the current schema version, qwen-only.
python -m crucible benchmark export-jsonl ~/.local/share/crucible/corpus.duckdb \
    --provider qwen --out ~/exports/qwen-runs.jsonl

# Pair each row with the canonical paper text via the corpus DB.
# The exact joiner is your training-pipeline-specific code; the
# building blocks are paper_id (in benchmark_runs) and DOI (in works).
```

The full curation pipeline (filtering by score, dedup by paper, etc.)
is your team's domain — Crucible's job is to ship clean inputs.

### Day 7: streaming hooks

For real-time integration (Kafka / Pulsar / NATS):

- `crucible run` writes events to `<workdir>/events.jsonl` as they
  happen. Tail this file and forward to your bus.
- `crucible transpile` writes one transcript row per call. Tail
  the transcripts table with DuckDB's CDC or wrap the call to
  also publish to your bus.
- The atproto integration
  ([`src/atproto/`](../src/atproto/)) is an example of "publish to
  an external system on success" — read its `cmd_run` hook for the
  pattern.

## Failure modes specific to this profile

- **"DuckDB doesn't fit our distributed-SQL architecture."**
  DuckDB is the *embedded* store; your warehouse is the
  *aggregating* store. Export periodically; don't put DuckDB on
  the hot path of a 1k-QPS API.
- **"The schema_version field forces us to handle old shapes."**
  Yes — that's by design. The migration framework makes "old
  shapes" loadable, not deprecated. If you don't need the old
  data, drop rows where `schema_version != current` before
  ingestion. If you do need them, run `migrate_json` first.
- **"The per_axis JSON column doesn't fit our schema'd
  warehouse."** Two options: (a) UNNEST the JSON into separate
  columns at export time (`SELECT … json_extract(per_axis,
  '$.protein_ff') AS protein_ff_correct …`); (b) store the JSON
  as-is in a VARIANT/SUPER column. (a) is cleaner for analytics;
  (b) preserves future-axis additions without re-export.
- **"The transcript store has prompt content I can't ship to a
  third party."** Transcripts include the paper text. If your
  paper text is internal IP, your transcript store must stay
  on-prem. Fine-tuning on third-party-managed infrastructure
  requires either: (a) hosting the fine-tune yourself, or (b)
  contracting with a vendor under an explicit MNDA. The on-prem
  story in [`docs/ON_PREM.md`](ON_PREM.md) is meant for the
  upstream LLM call; it doesn't extend to fine-tune compute.
- **"Crucible's benchmark scoring uses No partial credit; we want
  finer-grained signal."** Forks of the scorer are encouraged. The
  10-axis scorer is in
  [`python/crucible/benchmark/scorer.py`](../python/crucible/benchmark/scorer.py);
  override `score()` with your own grading rule, keep the rest of
  the framework. The runs-store schema is rule-agnostic.

## What the option-3 flywheel needs

The Adoption Plan Phase 4 calls for a fine-tuned chemistry-MD
model. As a data engineer, your job is to make the corpus that
trains it. A useful corpus has:

| Property | How Crucible enables it |
|---|---|
| Sample diversity | OpenAlex backend in `corpus/` covers ~250M works; `fetch --topic` filters by concept |
| Ground-truth accuracy | The verified seed entries in `benchmark/papers.py` + the verification CLI |
| Per-row confidence | The `provenance` field on every spec; coverage_score gives a single 0-1 number |
| Schema stability | Migration framework keeps historical rows loadable |
| Reproducibility | Every transcript carries `(provider, model, schema_version, timestamp)` |
| Negative samples | Failed runs are stored; `ok=false` rows are valid training input |

If you build a fine-tune corpus from this, please open an issue
tagged `corpus-export` describing your filter / dedup strategy.
Crucible benefits from learning what you found useful.

## When to read X next

- *I want a complete pipeline diagram* →
  [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — Mermaid diagrams of the
  full data flow.
- *I want to add a new exporter format* →
  [`python/crucible/benchmark/runs_store.py`](../python/crucible/benchmark/runs_store.py)
  is the smallest patch surface (export_jsonl is the model).
- *I want to integrate with a specific warehouse* — start by writing
  a one-off COPY-to-Parquet script; promote to a Crucible
  contribution once the pattern proves out.

## See also

- [`docs/CORPUS_DESIGN.md`](CORPUS_DESIGN.md) — the design eval that
  picked DuckDB over Neo4j and explains the standalone-vs-integrated
  scoping.
- [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — system-level diagrams.
- [`musings/python_for_app_layer.md`](../musings/python_for_app_layer.md)
  — why the data tier drifts toward Python (your tier).
- [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 4 — the
  fine-tune flywheel as the strategic destination.
