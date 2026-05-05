"""Tests for the hallucination benchmark.

Scorer + runner + reporter. The runner test uses an injected mock
transpile callable so CI doesn't pay for live LLM tokens.
"""

from __future__ import annotations

import json

import pytest

from crucible import templates
from crucible.benchmark import (
    BenchmarkEntry,
    ExpectedProtocol,
    RunOutcome,
    list_entries,
    load_seed_set,
    render_report,
    run,
    score,
)
from crucible.benchmark.scorer import ScoreAxis


# -----------------------------------------------------------------------------
# Seed set sanity

def test_seed_set_loadable():
    entries = list_entries()
    assert len(entries) >= 3
    assert all(e.doi for e in entries)
    assert all(e.paper_id for e in entries)


def test_seed_set_status_filter():
    all_entries = load_seed_set()
    verified = load_seed_set(verified_only=True)
    assert len(verified) <= len(all_entries)
    assert all(e.is_scoreable() for e in verified)


# -----------------------------------------------------------------------------
# Scorer

def _verified_entry() -> BenchmarkEntry:
    return BenchmarkEntry(
        paper_id="test_paper",
        doi="10.0000/test",
        title="Test paper",
        expected=ExpectedProtocol(
            protein_ff="amber14sb",
            water_model="TIP3P",
            ensemble="NPT",
            dt_fs=2.0,
            temperature_K=300.0,
            duration_ns=10.0,
            pressure_bar=1.0,
            fep_lambda_count=None,
        ),
        status="verified",
        verified_by="TEST 2026-05-04",
    )


def test_score_unverified_entry_raises():
    entry = _verified_entry()
    object.__setattr__(entry, "status", "needs_verification")
    spec = templates.init("vanilla")
    with pytest.raises(ValueError, match="needs_verification"):
        score(entry, spec)


def test_score_unverified_entry_allowed_with_flag():
    entry = _verified_entry()
    object.__setattr__(entry, "status", "needs_verification")
    spec = templates.init("vanilla")
    result = score(entry, spec, allow_unverified=True)
    assert result.paper_id == "test_paper"


def test_score_perfect_match_against_vanilla_template():
    """vanilla template uses amber14sb, TIP3P, NPT, dt=2 fs, T=300K,
       duration=10ns, P=1 bar — perfect match for the verified entry."""
    entry = _verified_entry()
    spec = templates.init("vanilla")
    result = score(entry, spec)
    # All 7 non-None axes should match (no FEP — that axis is None).
    assert result.total == result.max_score
    assert result.percent == 1.0
    assert result.per_axis[ScoreAxis.PROTEIN_FF] is True
    assert result.per_axis[ScoreAxis.FEP_LAMBDA_COUNT] is None  # not scored


def test_score_water_model_mismatch():
    entry = _verified_entry()
    spec = templates.init("vanilla")
    spec = spec.model_copy(update={
        "system": spec.system.model_copy(update={
            "solvent": spec.system.solvent.model_copy(update={
                "model": "TIP4P_EW",
            }),
        }),
    })
    result = score(entry, spec)
    assert result.per_axis[ScoreAxis.WATER_MODEL] is False
    assert result.total == result.max_score - 1


def test_score_fep_lambda_count():
    entry = BenchmarkEntry(
        paper_id="test_fep",
        doi="10.0000/fep",
        title="FEP test",
        expected=ExpectedProtocol(fep_lambda_count=11),
        status="verified",
    )
    spec = templates.init("kinase_inhibitor_fep")
    result = score(entry, spec)
    # kinase_inhibitor_fep template has 11 lambda windows (0.0..1.0 step 0.1).
    assert result.per_axis[ScoreAxis.FEP_LAMBDA_COUNT] is True


def test_score_missing_dynamics_stage_zeroes_production_axes():
    entry = _verified_entry()
    spec = templates.init("vanilla")
    # Drop all dynamics stages.
    spec = spec.model_copy(update={
        "protocol": [s for s in spec.protocol if s.kind != "dynamics"],
    })
    result = score(entry, spec)
    assert result.per_axis[ScoreAxis.ENSEMBLE] is False
    assert result.per_axis[ScoreAxis.DT_FS] is False
    assert any("DynamicsStage" in n for n in result.notes)


def test_score_none_expected_drops_axis_from_denominator():
    entry = BenchmarkEntry(
        paper_id="t",
        doi="10.0/x",
        title="t",
        expected=ExpectedProtocol(protein_ff="amber14sb"),  # only 1 axis set
        status="verified",
    )
    spec = templates.init("vanilla")
    result = score(entry, spec)
    assert result.max_score == 1
    assert result.total == 1


# -----------------------------------------------------------------------------
# Runner

def test_runner_yields_outcome_per_entry():
    entries = [_verified_entry(), _verified_entry()]
    object.__setattr__(entries[1], "paper_id", "second")
    paper_text_fn = lambda e: f"text for {e.paper_id}"
    transpile_fn = lambda _t: templates.init("vanilla")
    outcomes = list(run(entries, paper_text_fn, transpile_fn))
    assert len(outcomes) == 2
    assert all(o.ok for o in outcomes)
    assert {o.paper_id for o in outcomes} == {"test_paper", "second"}


def test_runner_no_paper_text_marks_outcome_failed():
    entries = [_verified_entry()]
    paper_text_fn = lambda e: None
    transpile_fn = lambda _t: templates.init("vanilla")
    outcomes = list(run(entries, paper_text_fn, transpile_fn))
    assert len(outcomes) == 1
    assert outcomes[0].ok is False
    assert "no paper text" in outcomes[0].error


def test_runner_captures_transpile_exceptions():
    entries = [_verified_entry()]
    paper_text_fn = lambda e: "text"
    def transpile_fn(_t):
        raise RuntimeError("boom")
    outcomes = list(run(entries, paper_text_fn, transpile_fn))
    assert outcomes[0].ok is False
    assert "RuntimeError: boom" in outcomes[0].error


# -----------------------------------------------------------------------------
# Reporter

def test_render_report_handles_empty():
    md = render_report([])
    assert "Hallucination benchmark" in md
    assert "0 of 0 papers" in md


def test_render_report_includes_per_axis_table():
    entry = _verified_entry()
    spec = templates.init("vanilla")
    sr = score(entry, spec)
    outcome = RunOutcome(paper_id=entry.paper_id, ok=True,
                         elapsed_s=0.5, score_result=sr)
    md = render_report([(entry, outcome)])
    assert "Per-axis accuracy" in md
    assert "`protein_ff`" in md
    assert "`water_model`" in md


def test_render_report_marks_unverified_entries():
    entry = BenchmarkEntry(
        paper_id="x", doi="10.0/x", title="X",
        expected=ExpectedProtocol(),
        status="needs_verification",
    )
    outcome = RunOutcome(paper_id="x", ok=False, elapsed_s=0.0,
                         error="no paper text")
    md = render_report([(entry, outcome)])
    assert "needs_verification" in md
    assert "no paper text" in md


def test_render_report_includes_trend_section_when_runs_db_passed(tmp_path):
    """Optional `trends_db=` parameter pulls in the longitudinal table."""
    duckdb = pytest.importorskip("duckdb")
    from crucible.benchmark.runs_store import (
        open_runs_store, insert_outcome, new_run_id,
    )
    from crucible.benchmark.scorer import ScoreAxis, ScoreResult
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    rid = new_run_id()
    sr = ScoreResult(paper_id="x",
                     per_axis={ax: True for ax in ScoreAxis},
                     total=9, max_score=9, notes=[])
    insert_outcome(conn, run_id=rid,
                   outcome=RunOutcome(paper_id="x", ok=True,
                                      elapsed_s=1.0, score_result=sr),
                   llm_provider="anthropic", llm_model="claude-opus-4-7",
                   schema_version="0.4.0")
    md = render_report([], trends_db=conn)
    assert "Longitudinal trends" in md
    assert "anthropic" in md
    assert "100%" in md
    conn.close()


def test_render_report_omits_trend_section_when_runs_db_empty(tmp_path):
    duckdb = pytest.importorskip("duckdb")
    from crucible.benchmark.runs_store import open_runs_store
    db = tmp_path / "runs.duckdb"
    conn = open_runs_store(db)
    md = render_report([], trends_db=conn)
    assert "Longitudinal trends" not in md
    conn.close()
