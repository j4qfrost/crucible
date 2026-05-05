"""Tests for the longitudinal benchmark-runs store."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

duckdb = pytest.importorskip("duckdb")

from crucible.benchmark.runner import RunOutcome
from crucible.benchmark.runs_store import (
    insert_outcome,
    new_run_id,
    open_runs_store,
    runs_for_paper,
    stats,
    trends,
)
from crucible.benchmark.scorer import ScoreAxis, ScoreResult


def _outcome(paper_id: str, *, total: int = 6, max_score: int = 8,
             elapsed_s: float = 1.5,
             ok: bool = True, error=None) -> RunOutcome:
    if ok:
        sr = ScoreResult(
            paper_id=paper_id,
            per_axis={
                ScoreAxis.PROTEIN_FF: True,
                ScoreAxis.WATER_MODEL: True,
                ScoreAxis.ENSEMBLE: True,
                ScoreAxis.DT_FS: True,
                ScoreAxis.TEMPERATURE_K: True,
                ScoreAxis.DURATION_NS: False,
                ScoreAxis.PRESSURE_BAR: True,
                ScoreAxis.FEP_LAMBDA_COUNT: None,
                ScoreAxis.SOLVENT_PADDING_NM: False,
            },
            total=total, max_score=max_score, notes=[],
        )
        return RunOutcome(paper_id=paper_id, ok=True, elapsed_s=elapsed_s,
                          score_result=sr)
    return RunOutcome(paper_id=paper_id, ok=False, elapsed_s=elapsed_s,
                      score_result=None, error=error)


def test_open_runs_store_creates_table(tmp_path):
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rows = conn.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'"
    ).fetchall()
    assert ("benchmark_runs",) in rows
    conn.close()


def test_insert_outcome_round_trips(tmp_path):
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("paper_a"),
                   llm_provider="anthropic", llm_model="claude-opus-4-7",
                   schema_version="0.4.0")
    rows = list(runs_for_paper(conn, "paper_a"))
    assert len(rows) == 1
    row = rows[0]
    assert row["paper_id"] == "paper_a"
    assert row["llm_provider"] == "anthropic"
    assert row["total"] == 6
    assert row["max_score"] == 8
    assert row["per_axis"]["protein_ff"] is True
    conn.close()


def test_insert_outcome_records_runner_failure(tmp_path):
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid,
                   outcome=_outcome("p", ok=False, error="HTTP 500"),
                   llm_provider="local", llm_model="qwen",
                   schema_version="0.4.0")
    row = list(runs_for_paper(conn, "p"))[0]
    assert row["ok"] is False
    assert row["error"] == "HTTP 500"
    assert row["per_axis"] is None
    conn.close()


def test_trends_computes_avg_pct_per_paper(tmp_path):
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid_1, rid_2 = new_run_id(), new_run_id()
    insert_outcome(conn, run_id=rid_1, outcome=_outcome("paper_a", total=4),
                   llm_provider="anthropic", llm_model="x",
                   schema_version="0.4.0")
    insert_outcome(conn, run_id=rid_2, outcome=_outcome("paper_a", total=8, max_score=8),
                   llm_provider="local", llm_model="y",
                   schema_version="0.4.0")
    insert_outcome(conn, run_id=rid_2, outcome=_outcome("paper_b", total=2),
                   llm_provider="local", llm_model="y",
                   schema_version="0.4.0")
    rows = list(trends(conn))
    by_id = {r.paper_id: r for r in rows}
    # paper_a: (4/8 + 8/8) / 2 = 0.75
    assert abs(by_id["paper_a"].avg_pct - 0.75) < 1e-6
    assert by_id["paper_a"].n_runs == 2
    assert set(by_id["paper_a"].providers) == {"anthropic", "local"}
    # paper_b: 2/8 = 0.25
    assert abs(by_id["paper_b"].avg_pct - 0.25) < 1e-6
    conn.close()


def test_trends_filter_by_paper_id(tmp_path):
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("paper_a"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("paper_b"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    rows = list(trends(conn, paper_id="paper_a"))
    assert {r.paper_id for r in rows} == {"paper_a"}
    conn.close()


def test_stats_counts(tmp_path):
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid_1, rid_2 = new_run_id(), new_run_id()
    insert_outcome(conn, run_id=rid_1, outcome=_outcome("a"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid_1, outcome=_outcome("b"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid_2, outcome=_outcome("a"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    s = stats(conn)
    assert s == {"rows": 3, "runs": 2, "papers_touched": 2}
    conn.close()


def test_insert_outcome_idempotent_on_run_id_paper_id(tmp_path):
    """Re-inserting the same (run_id, paper_id) is a no-op (PK conflict)."""
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a", total=3),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("a", total=7),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    rows = list(runs_for_paper(conn, "a"))
    assert len(rows) == 1
    # The first insert wins (no overwrite).
    assert rows[0]["total"] == 3
    conn.close()


def test_benchmark_cli_run_writes_runs_db_when_corpus_db_passed(tmp_path):
    """End-to-end: `benchmark run --mock --corpus-db <path>` writes a row
    per outcome into the corpus DB's benchmark_runs table without an
    explicit --runs-db."""
    from crucible.benchmark.cli import main
    db = tmp_path / "shared.duckdb"
    rc = main([
        "run", "--mock", "--allow-unverified", "--corpus-db", str(db),
        "--llm-model", "vanilla-mock",
    ])
    assert rc == 0
    import duckdb
    conn = duckdb.connect(str(db))
    n = conn.execute("SELECT COUNT(*) FROM benchmark_runs").fetchone()[0]
    assert n >= 1
    providers = {r[0] for r in conn.execute(
        "SELECT DISTINCT llm_provider FROM benchmark_runs"
    ).fetchall()}
    assert providers == {"mock"}
    conn.close()
