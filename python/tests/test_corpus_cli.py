"""Tests for the corpus CLI dispatcher (no live network)."""

from __future__ import annotations

import json
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


def test_fetch_batch_skips_comments_and_blanks(tmp_path, capsys, monkeypatch):
    """fetch-batch reads a names file, skips `#` + blank lines, and
    accumulates per-author results into a JSON summary."""
    duckdb = pytest.importorskip("duckdb")
    from crucible.corpus.openalex import Author
    db = tmp_path / "corp.duckdb"
    names_file = tmp_path / "names.txt"
    names_file.write_text(
        "# Tier-1 personas\n"
        "John Chodera\n"
        "\n"                          # blank — skipped
        "  # blank line above        \n"
        "David Mobley\n"
    )

    # Mock the OpenAlex client: find_author returns a synthetic Author;
    # list_works returns an empty list (zero works upserted).
    from crucible.corpus.cli import _fetch_author
    from unittest.mock import patch

    fake_author_calls: list[str] = []
    def fake_fetch(client, store, name, **kwargs):
        fake_author_calls.append(name)
        return (3, None) if name == "John Chodera" else (0, None)

    with patch("crucible.corpus.cli._fetch_author", side_effect=fake_fetch):
        from crucible.corpus.cli import main
        rc = main(["--db", str(db), "fetch-batch", str(names_file)])

    assert rc == 0   # no failures
    assert fake_author_calls == ["John Chodera", "David Mobley"]
    captured = capsys.readouterr()
    parsed = json.loads(captured.out)
    assert parsed["n_total"] == 2
    assert parsed["n_failed"] == 0
    assert parsed["results"][0]["n_works"] == 3


def test_fetch_batch_empty_file_exits_1(tmp_path, capsys):
    """fetch-batch with no usable lines exits 1 with a clean message."""
    duckdb = pytest.importorskip("duckdb")
    db = tmp_path / "corp.duckdb"
    names_file = tmp_path / "names.txt"
    names_file.write_text("# all comments\n\n   \n")
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "fetch-batch", str(names_file)])
    assert rc == 1
    assert "no author names" in capsys.readouterr().err


def test_fetch_batch_returns_n_failed_as_exit_code(tmp_path, monkeypatch):
    """When some authors fail (no match, OpenAlex error), exit code
    reflects the failure count."""
    duckdb = pytest.importorskip("duckdb")
    db = tmp_path / "corp.duckdb"
    names_file = tmp_path / "names.txt"
    names_file.write_text("Real Person\nFake Person\nAlso Real\n")

    from unittest.mock import patch
    def mixed_fetch(client, store, name, **kwargs):
        if "Fake" in name:
            return (0, "no author found")
        return (5, None)

    with patch("crucible.corpus.cli._fetch_author", side_effect=mixed_fetch):
        from crucible.corpus.cli import main
        rc = main(["--db", str(db), "fetch-batch", str(names_file)])

    assert rc == 1   # one failure


def test_query_select_returns_jsonl(tmp_path, capsys):
    duckdb = pytest.importorskip("duckdb")
    from crucible.corpus.openalex import Author
    from crucible.corpus.store import CorpusStore
    db = tmp_path / "corp.duckdb"
    with CorpusStore.open(db) as s:
        s.upsert_author(Author(author_id="A1", display_name="A One"))
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "query", "SELECT display_name FROM authors"])
    assert rc == 0
    captured = capsys.readouterr()
    parsed = [json.loads(line) for line in captured.out.splitlines() if line]
    assert parsed == [{"display_name": "A One"}]


def test_query_table_format(tmp_path, capsys):
    duckdb = pytest.importorskip("duckdb")
    from crucible.corpus.openalex import Author
    from crucible.corpus.store import CorpusStore
    db = tmp_path / "corp.duckdb"
    with CorpusStore.open(db) as s:
        s.upsert_author(Author(author_id="A1", display_name="A One"))
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "query",
               "SELECT author_id, display_name FROM authors",
               "--format", "table"])
    assert rc == 0
    out = capsys.readouterr().out
    lines = out.strip().splitlines()
    assert lines[0] == "author_id\tdisplay_name"
    assert lines[1] == "A1\tA One"


@pytest.mark.parametrize("write_sql", [
    "DELETE FROM authors",
    "delete from authors",       # case-insensitive
    "  DROP TABLE works",        # leading whitespace
    "INSERT INTO authors VALUES ('A2', 'X')",
    "UPDATE authors SET display_name = 'evil'",
    "ALTER TABLE works ADD COLUMN x TEXT",
    "TRUNCATE benchmark_runs",
    "ATTACH 'evil.duckdb' AS evil",
    "PRAGMA enable_external_access = true",
])
def test_query_refuses_write_keywords(tmp_path, capsys, write_sql):
    duckdb = pytest.importorskip("duckdb")
    db = tmp_path / "corp.duckdb"
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "query", write_sql])
    assert rc == 2
    assert "refused" in capsys.readouterr().err


def test_query_allows_select_after_sql_comment(tmp_path, capsys):
    """Leading -- comments don't trip the keyword check."""
    duckdb = pytest.importorskip("duckdb")
    db = tmp_path / "corp.duckdb"
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "query",
               "-- safety comment\nSELECT 1 AS x"])
    assert rc == 0
    out = capsys.readouterr().out
    assert json.loads(out.strip()) == {"x": 1}


def test_query_empty_sql_exits_2(tmp_path, capsys):
    duckdb = pytest.importorskip("duckdb")
    db = tmp_path / "corp.duckdb"
    from crucible.corpus.cli import main
    rc = main(["--db", str(db), "query", "   "])
    assert rc == 2


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
