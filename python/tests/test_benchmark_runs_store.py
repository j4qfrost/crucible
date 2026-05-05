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


def test_per_axis_accuracy_counts_True_only(tmp_path):
    from crucible.benchmark.runs_store import per_axis_accuracy
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a", total=5),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    out = per_axis_accuracy(conn)
    # The mock outcome scores 5 axes True, 2 False, 1 None.
    # protein_ff=True, water_model=True, ensemble=True, dt_fs=True,
    # temperature_K=True, duration_ns=False, pressure_bar=True (7th True),
    # fep_lambda_count=None (skipped), solvent_padding_nm=False
    assert out["protein_ff"]["pct"] == 1.0
    assert out["duration_ns"]["pct"] == 0.0
    assert "fep_lambda_count" not in out
    conn.close()


def test_per_axis_accuracy_filter_by_provider(tmp_path):
    from crucible.benchmark.runs_store import per_axis_accuracy
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a"),
                   llm_provider="anthropic", llm_model="x",
                   schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("b"),
                   llm_provider="local", llm_model="y",
                   schema_version="0.4.0")
    only_anthropic = per_axis_accuracy(conn, llm_provider="anthropic")
    assert only_anthropic["protein_ff"]["n_scored"] == 1
    only_missing = per_axis_accuracy(conn, llm_provider="nonexistent")
    assert only_missing == {}
    conn.close()


def test_per_provider_summary(tmp_path):
    from crucible.benchmark.runs_store import per_provider_summary
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a", total=4),
                   llm_provider="x", llm_model="m", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("b", total=8, max_score=8),
                   llm_provider="x", llm_model="m", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("c", total=2),
                   llm_provider="y", llm_model="n", schema_version="0.4.0")
    rows = per_provider_summary(conn)
    by_provider = {r["llm_provider"]: r for r in rows}
    assert by_provider["x"]["n_outcomes"] == 2
    # avg(4/8, 8/8) = 0.75
    assert abs(by_provider["x"]["avg_pct"] - 0.75) < 1e-6
    conn.close()


def test_schema_version_distribution(tmp_path):
    from crucible.benchmark.runs_store import schema_version_distribution
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a"),
                   llm_provider="x", llm_model="m", schema_version="0.3.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("b"),
                   llm_provider="x", llm_model="m", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("c"),
                   llm_provider="x", llm_model="m", schema_version="0.4.0")
    dist = schema_version_distribution(conn)
    assert dist == {"0.3.0": 1, "0.4.0": 2}
    conn.close()


def test_export_jsonl_include_paper_text_joins_corpus(tmp_path, capsys):
    """`--include-paper-text` joins each runs row with the corpus's
    `paper_text_for_doi` result. Self-contained training records for
    the option-3 flywheel."""
    duckdb = pytest.importorskip("duckdb")
    from crucible.benchmark.cli import main
    from crucible.corpus.openalex import Author, Work, WorkAuthor
    from crucible.corpus.store import CorpusStore

    db = tmp_path / "shared.duckdb"

    # Step 1: seed the corpus with one DOI from the benchmark seed set.
    with CorpusStore.open(db) as s:
        wa = WorkAuthor(author_id="A1", display_name="K Lindorff-Larsen",
                        position=1)
        s.upsert_work(Work(
            work_id="W_SHAW", doi="10.1126/science.1187409",
            title="Atomic-Level Characterization …",
            abstract="Long-MD characterization at 1 ms.",
            publication_year=2010, venue="Science",
            cited_by_count=3000, is_oa=False, pdf_url=None,
            authors=[wa],
        ))

    # Step 2: run the benchmark to populate benchmark_runs.
    rc = main([
        "run", "--mock", "--allow-unverified",
        "--corpus-db", str(db),
        "--llm-model", "vanilla-mock",
        "--out", str(tmp_path / "out.jsonl"),
    ])
    assert rc == 0

    # Step 3: export with --include-paper-text. The shaw_2010_bpti row
    # should have its `paper_text` populated; rows whose DOI isn't in
    # the corpus get `paper_text=None`.
    out = tmp_path / "export.jsonl"
    rc = main([
        "export-jsonl", str(db), "--out", str(out),
        "--include-paper-text",
    ])
    assert rc == 0

    import json as _json
    rows = [_json.loads(line) for line in out.read_text().splitlines() if line]
    by_paper = {r["paper_id"]: r for r in rows}
    shaw_row = by_paper["shaw_2010_bpti"]
    assert "paper_text" in shaw_row
    assert shaw_row["paper_text"] is not None
    assert "Atomic-Level Characterization" in shaw_row["paper_text"]
    # Other entries didn't get seeded; their paper_text is None.
    other_id = next(pid for pid in by_paper if pid != "shaw_2010_bpti")
    assert by_paper[other_id]["paper_text"] is None


def test_rows_since_filters_strictly_newer(tmp_path):
    """v1.74 `rows_since` filters strictly > since_run_at."""
    from datetime import datetime, timedelta, timezone
    from crucible.benchmark.runs_store import rows_since
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    future = datetime.now(timezone.utc) + timedelta(seconds=60)
    assert list(rows_since(conn, since_run_at=future)) == []
    past = datetime.now(timezone.utc) - timedelta(seconds=60)
    rows = list(rows_since(conn, since_run_at=past))
    assert len(rows) == 1
    assert rows[0]["paper_id"] == "a"
    conn.close()


def test_benchmark_cli_watch_polls_and_exits(tmp_path, capsys):
    """`watch --max-iterations 1` polls once and exits cleanly."""
    from crucible.benchmark.cli import main
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("seed_a"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    conn.close()
    rc = main(["watch", str(db),
               "--interval", "0.01",
               "--max-iterations", "1",
               "--since", "2020-01-01"])
    assert rc == 0
    out = capsys.readouterr().out
    import json as _json
    rows = [_json.loads(line) for line in out.splitlines() if line.strip()]
    assert len(rows) == 1
    assert rows[0]["paper_id"] == "seed_a"


def test_benchmark_cli_watch_rejects_bad_since(tmp_path, capsys):
    from crucible.benchmark.cli import main
    db = tmp_path / "runs.duckdb"
    open_runs_store(db).close()
    rc = main(["watch", str(db), "--since", "not-a-date",
               "--max-iterations", "1"])
    assert rc == 2
    assert "ISO format" in capsys.readouterr().err


def test_export_jsonl_filters_by_since(tmp_path):
    """The export_jsonl `since=` filter is exposed via CLI in v1.64."""
    from datetime import datetime, timedelta, timezone
    from crucible.benchmark.runs_store import export_jsonl
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a"),
                   llm_provider="x", llm_model="x", schema_version="0.4.0")
    # Future cutoff drops everything.
    future = datetime.now(timezone.utc) + timedelta(days=7)
    rows = list(export_jsonl(conn, since=future))
    assert rows == []
    # Past cutoff keeps everything.
    past = datetime.now(timezone.utc) - timedelta(days=7)
    rows = list(export_jsonl(conn, since=past))
    assert len(rows) == 1
    conn.close()


def test_export_jsonl_streams_rows(tmp_path):
    from crucible.benchmark.runs_store import export_jsonl
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a"),
                   llm_provider="anthropic", llm_model="opus",
                   schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("b"),
                   llm_provider="local", llm_model="qwen",
                   schema_version="0.4.0")
    import json as _json
    rows = [_json.loads(line) for line in export_jsonl(conn)]
    assert {r["paper_id"] for r in rows} == {"a", "b"}
    assert all("per_axis" in r for r in rows)
    # per_axis was hydrated back into a dict, not left as a JSON string.
    assert isinstance(rows[0]["per_axis"], dict)
    conn.close()


def test_export_jsonl_filters_by_paper_id_and_provider(tmp_path):
    from crucible.benchmark.runs_store import export_jsonl
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    insert_outcome(conn, run_id=rid, outcome=_outcome("a"),
                   llm_provider="x", llm_model="m", schema_version="0.4.0")
    insert_outcome(conn, run_id=rid, outcome=_outcome("b"),
                   llm_provider="y", llm_model="m", schema_version="0.4.0")
    only_a = list(export_jsonl(conn, paper_id="a"))
    only_y = list(export_jsonl(conn, llm_provider="y"))
    assert len(only_a) == 1 and len(only_y) == 1
    conn.close()


def test_benchmark_compare_diffs_two_runs_dbs(tmp_path, capsys):
    """`benchmark compare A B` shows per-paper delta + only-in-A /
    only-in-B sets."""
    from crucible.benchmark.cli import main
    db_a = tmp_path / "a.duckdb"
    db_b = tmp_path / "b.duckdb"

    # Seed A: paper_x scores 4/8.
    conn_a = open_runs_store(db_a)
    rid = new_run_id()
    insert_outcome(conn_a, run_id=rid,
                   outcome=_outcome("paper_x", total=4),
                   llm_provider="anthropic", llm_model="opus",
                   schema_version="0.4.0")
    insert_outcome(conn_a, run_id=rid,
                   outcome=_outcome("only_in_a"),
                   llm_provider="anthropic", llm_model="opus",
                   schema_version="0.4.0")
    conn_a.close()

    # Seed B: paper_x scores 8/8 (improvement); only_in_b is new.
    conn_b = open_runs_store(db_b)
    rid_b = new_run_id()
    insert_outcome(conn_b, run_id=rid_b,
                   outcome=_outcome("paper_x", total=8, max_score=8),
                   llm_provider="local", llm_model="qwen",
                   schema_version="0.4.0")
    insert_outcome(conn_b, run_id=rid_b,
                   outcome=_outcome("only_in_b"),
                   llm_provider="local", llm_model="qwen",
                   schema_version="0.4.0")
    conn_b.close()

    rc = main(["compare", str(db_a), str(db_b)])
    assert rc == 0
    out = capsys.readouterr().out
    import json as _json
    parsed = _json.loads(out)
    assert "only_in_a" in parsed["only_in_left"]
    assert "only_in_b" in parsed["only_in_right"]
    assert parsed["common_papers"] == 1
    delta = parsed["deltas"][0]
    assert delta["paper_id"] == "paper_x"
    assert delta["delta_pp"] > 0   # B improved over A


def test_benchmark_cli_publish_writes_markdown(tmp_path):
    from crucible.benchmark.cli import main
    out = tmp_path / "report.md"
    rc = main(["publish", "--mock", "--allow-unverified",
               "--corpus-db", str(tmp_path / "shared.duckdb"),
               "--llm-model", "vanilla-mock",
               "--out", str(out)])
    assert rc == 0
    text = out.read_text()
    assert "Hallucination benchmark" in text
    assert "Per-paper detail" in text
    # Trends section auto-included because --corpus-db doubles as --runs-db.
    assert "Longitudinal trends" in text


def test_benchmark_cli_publish_brief_uses_summary_table(tmp_path):
    from crucible.benchmark.cli import main
    out = tmp_path / "report.md"
    rc = main(["publish", "--mock", "--allow-unverified",
               "--corpus-db", str(tmp_path / "shared.duckdb"),
               "--llm-model", "vanilla-mock",
               "--out", str(out), "--brief"])
    assert rc == 0
    text = out.read_text()
    assert "Per-paper summary" in text
    assert "Per-paper detail" not in text


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
