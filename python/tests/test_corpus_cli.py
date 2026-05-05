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
    assert {"fetch", "papers", "coauthors", "authors", "stats", "ui"}.issubset(cmds)


def test_corpus_authors_lists_local_authors(tmp_path, capsys):
    """Seed two authors via direct upsert, then `authors` lists them."""
    duckdb = pytest.importorskip("duckdb")
    from crucible.corpus.openalex import Author, Work, WorkAuthor
    from crucible.corpus.store import CorpusStore
    db = tmp_path / "corp.duckdb"
    with CorpusStore.open(db) as s:
        wa1 = WorkAuthor(author_id="A1", display_name="Alice One", position=1)
        wa2 = WorkAuthor(author_id="A2", display_name="Bob Two", position=2)
        s.upsert_work(Work(
            work_id="W1", doi="10.0/x", title="t", abstract=None,
            publication_year=2024, venue="X", cited_by_count=0, is_oa=False,
            pdf_url=None, authors=[wa1, wa2],
        ))
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "authors"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "Alice One" in captured.out
    assert "Bob Two" in captured.out


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
