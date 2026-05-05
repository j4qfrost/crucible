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


def per_axis_accuracy(conn: Any, *, llm_provider: Optional[str] = None) -> dict[str, dict]:
    """Per-axis accuracy across the runs table.

    Returns `{axis_name: {n_correct, n_scored, pct}}`. Optionally
    filtered to one provider. The per-axis JSON is parsed in Python
    rather than SQL because DuckDB's JSON ops differ across versions
    and the volume here is small (rows × ~10 axes).
    """
    sql = "SELECT per_axis FROM benchmark_runs WHERE per_axis IS NOT NULL"
    params: list = []
    if llm_provider is not None:
        sql += " AND llm_provider = ?"
        params.append(llm_provider)
    cur = conn.execute(sql, params)
    counts: dict[str, dict[str, int]] = {}
    for (per_axis_json,) in cur.fetchall():
        try:
            per_axis = json.loads(per_axis_json)
        except (TypeError, json.JSONDecodeError):
            continue
        for axis, value in per_axis.items():
            if value is None:
                continue            # axis not scored for this paper
            slot = counts.setdefault(axis, {"n_correct": 0, "n_scored": 0})
            slot["n_scored"] += 1
            if value is True:
                slot["n_correct"] += 1
    out: dict[str, dict] = {}
    for axis, slot in counts.items():
        n_scored = slot["n_scored"]
        out[axis] = {
            "n_correct": slot["n_correct"],
            "n_scored": n_scored,
            "pct": (slot["n_correct"] / n_scored) if n_scored else 0.0,
        }
    return out


def per_provider_summary(conn: Any) -> list[dict]:
    """One row per provider: counts + average accuracy across all runs."""
    cur = conn.execute(
        """
        SELECT llm_provider,
               COUNT(*) AS n_outcomes,
               COUNT(DISTINCT run_id) AS n_runs,
               AVG(CAST(total AS DOUBLE) / NULLIF(max_score, 0)) AS avg_pct
        FROM benchmark_runs
        WHERE total IS NOT NULL
        GROUP BY llm_provider
        ORDER BY n_outcomes DESC
        """
    )
    rows = []
    for row in cur.fetchall():
        rows.append({
            "llm_provider": row[0],
            "n_outcomes": int(row[1]),
            "n_runs": int(row[2]),
            "avg_pct": float(row[3]) if row[3] is not None else 0.0,
        })
    return rows


def schema_version_distribution(conn: Any) -> dict[str, int]:
    cur = conn.execute(
        "SELECT schema_version, COUNT(*) FROM benchmark_runs "
        "GROUP BY schema_version ORDER BY schema_version"
    )
    return {row[0]: int(row[1]) for row in cur.fetchall()}


def rows_since(conn: Any, *, since_run_at: Optional[datetime] = None,
               since_run_id: Optional[str] = None) -> Iterator[dict]:
    """Yield benchmark_runs rows newer than the given timestamp / run_id.

    Either filter is optional; both can be combined. `run_at` is the
    primary filter for `watch`-style polling; `run_id` exists as a
    secondary filter for resuming an interrupted tail (e.g. after a
    machine reboot).
    """
    sql = """
        SELECT run_id, paper_id, run_at, llm_provider, llm_model, ok,
               elapsed_s, total, max_score, error
        FROM benchmark_runs
        WHERE 1=1
    """
    params: list = []
    if since_run_at is not None:
        sql += " AND run_at > ?"
        params.append(since_run_at)
    if since_run_id is not None:
        sql += " AND run_id != ?"
        params.append(since_run_id)
    sql += " ORDER BY run_at"
    cur = conn.execute(sql, params)
    cols = [d[0] for d in cur.description]
    for row in cur.fetchall():
        rec = dict(zip(cols, row))
        run_at = rec.get("run_at")
        if run_at is not None and hasattr(run_at, "isoformat"):
            rec["run_at"] = run_at.isoformat()
        yield rec


def export_jsonl(conn: Any, *,
                 since: Optional[datetime] = None,
                 paper_id: Optional[str] = None,
                 llm_provider: Optional[str] = None) -> Iterator[str]:
    """Yield one JSON line per benchmark_runs row.

    Designed for the option-3 fine-tune flywheel
    (`docs/ADOPTION_PLAN.md` Phase 4) — the JSONL is what the training
    corpus consumes. Each line carries enough context (paper_id, model,
    provider, schema_version, per_axis breakdown) to filter the corpus
    to "high-quality runs only" downstream.
    """
    sql = """
        SELECT run_id, paper_id, run_at, llm_provider, llm_model, ok,
               elapsed_s, total, max_score, per_axis, error,
               schema_version, crucible_version
        FROM benchmark_runs
        WHERE 1=1
    """
    params: list = []
    if since is not None:
        sql += " AND run_at >= ?"
        params.append(since)
    if paper_id is not None:
        sql += " AND paper_id = ?"
        params.append(paper_id)
    if llm_provider is not None:
        sql += " AND llm_provider = ?"
        params.append(llm_provider)
    sql += " ORDER BY run_at"
    cur = conn.execute(sql, params)
    cols = [d[0] for d in cur.description]
    for row in cur.fetchall():
        record = dict(zip(cols, row))
        # per_axis is stored as a JSON string; rehydrate for downstream parsers.
        if record.get("per_axis"):
            try:
                record["per_axis"] = json.loads(record["per_axis"])
            except (TypeError, json.JSONDecodeError):
                pass
        # Datetime → ISO string for JSON-friendliness.
        run_at = record.get("run_at")
        if run_at is not None:
            record["run_at"] = run_at.isoformat() if hasattr(run_at, "isoformat") else str(run_at)
        yield json.dumps(record, default=str)
