"""Tests for the corpus CLI dispatcher (no live network)."""

from __future__ import annotations

from unittest.mock import patch

import pytest

duckdb = pytest.importorskip("duckdb")

from crucible.corpus.cli import build_parser, main


def test_build_parser_has_all_subcommands():
    p = build_parser()
    sub_actions = [a for a in p._actions if hasattr(a, "choices") and a.choices]
    assert sub_actions, "expected subparsers"
    cmds = set(sub_actions[0].choices.keys())
    assert {"fetch", "papers", "coauthors", "stats", "ui"}.issubset(cmds)


def test_stats_runs_against_in_memory_store(tmp_path, capsys):
    db = tmp_path / "corpus.duckdb"
    rc = main(["--db", str(db), "stats"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "works" in captured.out
    assert "authors" in captured.out


def test_papers_returns_empty_when_no_match(tmp_path, capsys):
    db = tmp_path / "corpus.duckdb"
    rc = main(["--db", str(db), "papers", "--author", "nobody"])
    # No author in DB → exit 1, with helpful stderr
    assert rc == 1


def test_fetch_short_circuits_when_openalex_returns_no_author(tmp_path):
    db = tmp_path / "corpus.duckdb"
    with patch("crucible.corpus.cli.OpenAlexClient") as m:
        m.return_value.find_author.return_value = None
        rc = main(["--db", str(db), "fetch", "no-such-person"])
    assert rc == 1
