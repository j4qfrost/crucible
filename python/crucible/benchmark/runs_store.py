"""DuckDB-backed longitudinal store for benchmark results.

Every `crucible benchmark run` invocation writes one row per
`(paper_id, llm_provider)` to the same DuckDB the corpus uses. Lets us
track accuracy drift over time as schemas bump, providers change, and
the hallucination-benchmark seed set grows.

Schema:

    benchmark_runs (
        run_id        TEXT,        -- UUID per run
        paper_id      TEXT,
        run_at        TIMESTAMP,
        llm_provider  TEXT,        -- "anthropic" | "local" | "mock" | "claude_cli"
        llm_model     TEXT,        -- e.g. "claude-opus-4-7" or "qwen2.5-coder-7b"
        ok            BOOLEAN,
        elapsed_s     DOUBLE,
        total         INTEGER,     -- score numerator (0-9)
        max_score     INTEGER,     -- score denominator (0-9)
        per_axis      JSON,        -- {axis_name: True | False | null}
        error         TEXT,        -- nullable runner error message
        schema_version TEXT,       -- the IR schema version when the run happened
        crucible_version TEXT,     -- best-effort version stamp
        UNIQUE(run_id, paper_id)
    )

Companion of `corpus.store.CorpusStore` — uses the same DuckDB file
when the user passes `--corpus-db`. Lives in its own module so the
corpus tier doesn't need to know about benchmarking and vice versa.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

from .runner import RunOutcome


_SCHEMA_STATEMENTS = [
    """
    CREATE TABLE IF NOT EXISTS benchmark_runs (
        run_id           TEXT NOT NULL,
        paper_id         TEXT NOT NULL,
        run_at           TIMESTAMP NOT NULL,
        llm_provider     TEXT NOT NULL,
        llm_model        TEXT,
        ok               BOOLEAN NOT NULL,
        elapsed_s        DOUBLE,
        total            INTEGER,
        max_score        INTEGER,
        per_axis         JSON,
        error            TEXT,
        schema_version   TEXT NOT NULL,
        crucible_version TEXT,
        PRIMARY KEY (run_id, paper_id)
    )
    """,
    "CREATE INDEX IF NOT EXISTS bench_runs_paper_idx ON benchmark_runs (paper_id)",
    "CREATE INDEX IF NOT EXISTS bench_runs_at_idx ON benchmark_runs (run_at)",
    "CREATE INDEX IF NOT EXISTS bench_runs_provider_idx ON benchmark_runs (llm_provider)",
]


def open_runs_store(path: str | Path) -> Any:
    """Open (and lazy-create) a DuckDB connection at `path` and ensure
    the benchmark_runs table exists. Returns the raw connection so the
    caller controls its lifetime."""
    try:
        import duckdb
    except ImportError as exc:
        raise ImportError(
            "the benchmark runs store requires duckdb. Install with "
            "`pip install crucible[corpus]` (corpus + runs share the dep)."
        ) from exc
    path = Path(path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = duckdb.connect(str(path))
    for stmt in _SCHEMA_STATEMENTS:
        conn.execute(stmt)
    return conn


def new_run_id() -> str:
    """UUIDv4. One per `crucible benchmark run` invocation."""
    return str(uuid.uuid4())


def insert_outcome(conn: Any, *,
                   run_id: str,
                   outcome: RunOutcome,
                   llm_provider: str,
                   llm_model: Optional[str],
                   schema_version: str,
                   crucible_version: Optional[str] = None) -> None:
    """Append one row for one `RunOutcome`."""
    sr = outcome.score_result
    per_axis_json = None
    total = max_score = None
    if sr is not None:
        per_axis_json = json.dumps({k.value: v for k, v in sr.per_axis.items()})
        total = sr.total
        max_score = sr.max_score
    conn.execute(
        """
        INSERT INTO benchmark_runs (
            run_id, paper_id, run_at, llm_provider, llm_model, ok,
            elapsed_s, total, max_score, per_axis, error, schema_version,
            crucible_version
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (run_id, paper_id) DO NOTHING
        """,
        [
            run_id,
            outcome.paper_id,
            datetime.now(timezone.utc),
            llm_provider,
            llm_model,
            bool(outcome.ok),
            float(outcome.elapsed_s),
            total,
            max_score,
            per_axis_json,
            outcome.error,
            schema_version,
            crucible_version,
        ],
    )


@dataclass
class TrendRow:
    paper_id: str
    n_runs: int
    avg_pct: float
    last_run_at: str
    providers: list[str]


def trends(conn: Any, *,
           paper_id: Optional[str] = None,
           since: Optional[datetime] = None) -> Iterator[TrendRow]:
    """Per-paper rollup: how has each entry's accuracy trended?

    With `paper_id`, restricts to one entry; with `since`, restricts to
    runs after that timestamp. Returns rows ordered by `last_run_at`
    descending so the most-recently-touched papers come first.
    """
    sql = """
        SELECT
            paper_id,
            COUNT(*) AS n_runs,
            AVG(CAST(total AS DOUBLE) / NULLIF(max_score, 0)) AS avg_pct,
            MAX(run_at) AS last_run_at,
            list_distinct(list(llm_provider)) AS providers
        FROM benchmark_runs
        WHERE total IS NOT NULL
    """
    params: list = []
    if paper_id is not None:
        sql += " AND paper_id = ?"
        params.append(paper_id)
    if since is not None:
        sql += " AND run_at >= ?"
        params.append(since)
    sql += " GROUP BY paper_id ORDER BY last_run_at DESC"
    cur = conn.execute(sql, params)
    for row in cur.fetchall():
        yield TrendRow(
            paper_id=row[0],
            n_runs=int(row[1]),
            avg_pct=float(row[2]) if row[2] is not None else 0.0,
            last_run_at=str(row[3]),
            providers=list(row[4]) if row[4] is not None else [],
        )


def runs_for_paper(conn: Any, paper_id: str, *,
                   limit: Optional[int] = None) -> Iterator[dict]:
    """All raw rows for a paper, newest first."""
    sql = """
        SELECT run_id, paper_id, run_at, llm_provider, llm_model, ok, elapsed_s,
               total, max_score, per_axis, error, schema_version,
               crucible_version
        FROM benchmark_runs
        WHERE paper_id = ?
        ORDER BY run_at DESC
    """
    params: list = [paper_id]
    if limit is not None:
        sql += " LIMIT ?"
        params.append(limit)
    cur = conn.execute(sql, params)
    cols = [d[0] for d in cur.description]
    for row in cur.fetchall():
        record = dict(zip(cols, row))
        if record.get("per_axis"):
            try:
                record["per_axis"] = json.loads(record["per_axis"])
            except (TypeError, json.JSONDecodeError):
                pass
        yield record


def stats(conn: Any) -> dict[str, int]:
    cur = conn.execute(
        "SELECT COUNT(*), COUNT(DISTINCT run_id), COUNT(DISTINCT paper_id) "
        "FROM benchmark_runs"
    )
    row = cur.fetchone()
    return {
        "rows": int(row[0]),
        "runs": int(row[1]),
        "papers_touched": int(row[2]),
    }
