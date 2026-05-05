"""End-to-end benchmark-pipeline integration tests.

Per-module unit tests cover the building blocks
(`test_benchmark*.py`, `test_corpus*.py`). This file covers the
full chain — run → write to runs DB → render markdown with trends
→ export JSONL — that landed across v1.45–v1.55. When a unit test
passes but the chain breaks (because of an interface drift or a
config-name mismatch), this is where the failure surfaces first.

Designed to run without a network or a real LLM: the mock provider
shipped in v1.53 covers the transpile path.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

duckdb = pytest.importorskip("duckdb")

from crucible.benchmark.cli import main as benchmark_main


def _run_pipeline(tmp_path: Path, *, brief: bool = False) -> dict:
    """Drive run → publish → trends → runs-stats → export end-to-end.
    Returns artifact paths + per-step exit codes for the caller to assert on.
    """
    db = tmp_path / "shared.duckdb"
    runs_jsonl = tmp_path / "runs.jsonl"
    report_md = tmp_path / "report.md"
    export_jsonl = tmp_path / "export.jsonl"

    # 1. Run with mock + corpus-db (which doubles as runs-db).
    rc_run = benchmark_main([
        "run", "--mock", "--allow-unverified",
        "--corpus-db", str(db),
        "--llm-model", "vanilla-mock",
        "--out", str(runs_jsonl),
    ])

    # 2. Publish (renders the report; pulls trends from the same DB).
    pub_args = [
        "publish", "--mock", "--allow-unverified",
        "--corpus-db", str(db),
        "--llm-model", "vanilla-mock-2",
        "--out", str(report_md),
    ]
    if brief:
        pub_args.append("--brief")
    rc_pub = benchmark_main(pub_args)

    # 3. Trends + runs-stats — both read the DB.
    rc_trends = benchmark_main(["trends", str(db)])
    rc_stats = benchmark_main(["runs-stats", str(db)])
    rc_stats_md = benchmark_main(["runs-stats-md", str(db)])

    # 4. Export JSONL — option-3 flywheel feeder.
    rc_export = benchmark_main([
        "export-jsonl", str(db), "--out", str(export_jsonl),
    ])

    return {
        "db": db,
        "runs_jsonl": runs_jsonl,
        "report_md": report_md,
        "export_jsonl": export_jsonl,
        "rc": {
            "run": rc_run,
            "publish": rc_pub,
            "trends": rc_trends,
            "runs_stats": rc_stats,
            "runs_stats_md": rc_stats_md,
            "export": rc_export,
        },
    }


def test_full_pipeline_all_subcommands_exit_zero(tmp_path):
    """Every CLI subcommand in the chain exits 0 on the smoke pipeline."""
    out = _run_pipeline(tmp_path)
    assert all(rc == 0 for rc in out["rc"].values()), \
        f"non-zero exit somewhere: {out['rc']}"


def test_full_pipeline_produces_all_expected_artifacts(tmp_path):
    """Every artifact gets written and is non-empty."""
    out = _run_pipeline(tmp_path)
    assert out["db"].is_file()
    assert out["db"].stat().st_size > 0
    assert out["runs_jsonl"].is_file()
    assert out["runs_jsonl"].stat().st_size > 0
    assert out["report_md"].is_file()
    assert out["report_md"].stat().st_size > 0
    assert out["export_jsonl"].is_file()
    assert out["export_jsonl"].stat().st_size > 0


def test_full_pipeline_runs_db_has_two_runs(tmp_path):
    """The pipeline executes `run` then `publish` — both write to the
    same runs DB (publish reuses --corpus-db as --runs-db). Should
    leave two distinct run_ids."""
    out = _run_pipeline(tmp_path)
    conn = duckdb.connect(str(out["db"]))
    n_runs = conn.execute(
        "SELECT COUNT(DISTINCT run_id) FROM benchmark_runs"
    ).fetchone()[0]
    assert n_runs == 2, f"expected 2 runs (one per `run` + one per `publish`), got {n_runs}"
    conn.close()


def test_full_pipeline_records_distinct_models_per_run(tmp_path):
    """We pass --llm-model 'vanilla-mock' to run and 'vanilla-mock-2'
    to publish; both should appear in benchmark_runs.llm_model."""
    out = _run_pipeline(tmp_path)
    conn = duckdb.connect(str(out["db"]))
    models = {r[0] for r in conn.execute(
        "SELECT DISTINCT llm_model FROM benchmark_runs"
    ).fetchall()}
    assert models == {"vanilla-mock", "vanilla-mock-2"}
    conn.close()


def test_full_pipeline_corpus_benchmark_scores_populated(tmp_path):
    """v1.48 wired `run` to upsert per-paper accuracy back into the
    corpus's `benchmark_scores` table. Both `run` and `publish` should
    have produced rows there."""
    out = _run_pipeline(tmp_path)
    conn = duckdb.connect(str(out["db"]))
    n_scores = conn.execute(
        "SELECT COUNT(*) FROM benchmark_scores"
    ).fetchone()[0]
    # 5 seed entries × 1 row each (the upsert keeps one row per
    # (doi, paper_id) pair, incrementing n_runs).
    assert n_scores == 5
    # Each row's n_runs should be 2 (one from `run`, one from `publish`).
    n_runs_2 = conn.execute(
        "SELECT COUNT(*) FROM benchmark_scores WHERE n_runs = 2"
    ).fetchone()[0]
    assert n_runs_2 == 5
    conn.close()


def test_full_pipeline_report_includes_trend_section(tmp_path):
    """The report from `publish` should include the trends section
    because the same DB doubles as the runs DB."""
    out = _run_pipeline(tmp_path)
    text = out["report_md"].read_text()
    assert "Hallucination benchmark" in text
    assert "Per-paper detail" in text
    assert "Longitudinal trends" in text


def test_full_pipeline_brief_mode_uses_summary_section(tmp_path):
    """`publish --brief` swaps the per-paper detail for the summary
    table."""
    out = _run_pipeline(tmp_path, brief=True)
    text = out["report_md"].read_text()
    assert "Per-paper summary" in text
    assert "Per-paper detail" not in text
    # Trends section still in (orthogonal to brief).
    assert "Longitudinal trends" in text


def test_full_pipeline_export_jsonl_round_trips(tmp_path):
    """Each line in the JSONL export is valid JSON with the expected
    shape — the option-3 flywheel feeder contract."""
    out = _run_pipeline(tmp_path)
    lines = [
        json.loads(line)
        for line in out["export_jsonl"].read_text().splitlines()
        if line.strip()
    ]
    # 5 entries × 2 runs = 10 outcome rows.
    assert len(lines) == 10
    # Spot-check the per-axis rehydration.
    one = lines[0]
    assert "paper_id" in one
    assert "schema_version" in one
    assert "per_axis" in one
    if one["per_axis"] is not None:
        assert isinstance(one["per_axis"], dict)
        # Should have all 10 axes (with True/False/None values).
        assert len(one["per_axis"]) == 10


def test_full_pipeline_schema_version_recorded_correctly(tmp_path):
    """Each row's schema_version should match the live SCHEMA_VERSION
    constant — the data-layer captures the IR version at run time."""
    from crucible import SCHEMA_VERSION
    out = _run_pipeline(tmp_path)
    conn = duckdb.connect(str(out["db"]))
    versions = {r[0] for r in conn.execute(
        "SELECT DISTINCT schema_version FROM benchmark_runs"
    ).fetchall()}
    assert versions == {SCHEMA_VERSION}
    conn.close()


def test_full_pipeline_cli_passthrough_dispatches_correctly(tmp_path):
    """v1.49 fixed argparse REMAINDER for `python -m crucible
    {corpus,benchmark}` passthrough. A real `python -m crucible
    benchmark run …` invocation must reach the inner CLI without
    being claimed by the outer argparse."""
    import subprocess
    import sys
    db = tmp_path / "passthrough.duckdb"
    # Use sys.executable so the subprocess uses the same interpreter
    # (and venv) pytest is running in — not the system python.
    proc = subprocess.run(
        [sys.executable, "-m", "crucible", "benchmark", "run",
         "--mock", "--allow-unverified",
         "--corpus-db", str(db),
         "--out", str(tmp_path / "out.jsonl")],
        capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        pytest.fail(
            f"passthrough invocation failed (exit {proc.returncode})\n"
            f"stderr:\n{proc.stderr}"
        )
    assert db.is_file()
