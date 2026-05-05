"""Corpus ↔ benchmark integration tests.

Covers the new `find_by_doi` / `paper_text_for_doi` accessors and the
benchmark CLI's `--corpus-db` flag.
"""

from __future__ import annotations

import pytest

duckdb = pytest.importorskip("duckdb")

from crucible.benchmark import load_seed_set
from crucible.corpus.openalex import Author, Work, WorkAuthor
from crucible.corpus.store import CorpusStore


def _seed_work(store: CorpusStore, *, doi: str, title: str,
               abstract: str | None = "an abstract") -> None:
    store.upsert_author(Author(author_id="A1", display_name="Test Author"))
    store.upsert_work(Work(
        work_id="W_TEST",
        doi=doi,
        title=title,
        abstract=abstract,
        publication_year=2024,
        venue="JCTC",
        cited_by_count=42,
        is_oa=True,
        pdf_url="https://example.com/x.pdf",
        authors=[WorkAuthor(author_id="A1", display_name="Test Author",
                            position=1, is_corresponding=True)],
    ))


def test_find_by_doi_handles_url_form():
    with CorpusStore.in_memory() as s:
        _seed_work(s, doi="https://doi.org/10.1126/science.1187409",
                   title="Sample paper")
        # Both forms resolve to the same row.
        bare = s.find_by_doi("10.1126/science.1187409")
        url  = s.find_by_doi("https://doi.org/10.1126/science.1187409")
        assert bare is not None and url is not None
        assert bare["work_id"] == url["work_id"] == "W_TEST"


def test_find_by_doi_case_insensitive():
    with CorpusStore.in_memory() as s:
        _seed_work(s, doi="10.1126/Science.1187409", title="x")
        assert s.find_by_doi("10.1126/SCIENCE.1187409") is not None


def test_find_by_doi_returns_none_when_missing():
    with CorpusStore.in_memory() as s:
        assert s.find_by_doi("10.0000/nonexistent") is None


def test_paper_text_for_doi_combines_title_and_abstract():
    with CorpusStore.in_memory() as s:
        _seed_work(s, doi="10.0000/x", title="Paper Title",
                   abstract="A meaningful abstract.")
        text = s.paper_text_for_doi("10.0000/x")
        assert text is not None
        assert "Paper Title" in text
        assert "A meaningful abstract" in text


def test_paper_text_for_doi_works_with_only_title():
    with CorpusStore.in_memory() as s:
        _seed_work(s, doi="10.0000/y", title="Just a title", abstract=None)
        text = s.paper_text_for_doi("10.0000/y")
        assert text == "Just a title"


def test_paper_text_for_doi_returns_none_when_unknown_doi():
    with CorpusStore.in_memory() as s:
        assert s.paper_text_for_doi("10.0000/missing") is None


def test_seed_set_doi_format_compatible_with_find_by_doi():
    """The benchmark seed set lists bare DOIs; ensure they round-trip
    through find_by_doi after a corpus upsert."""
    with CorpusStore.in_memory() as s:
        for entry in load_seed_set():
            _seed_work(s, doi=entry.doi, title=entry.title)
            row = s.find_by_doi(entry.doi)
            assert row is not None, f"find_by_doi failed for {entry.doi!r}"
            # Reset for the next iteration (avoid PK conflict on W_TEST).
            s._conn.execute("DELETE FROM works")
            s._conn.execute("DELETE FROM work_authors")
            s._conn.execute("DELETE FROM authors")


def test_paper_text_for_doi_full_text_cache_hit(tmp_path):
    """When a cached .txt exists for the work_id, return it without
    network or pdftotext calls."""
    with CorpusStore.in_memory() as s:
        _seed_work(s, doi="10.0000/cached", title="A title",
                   abstract="An abstract.")
        # Pre-populate the cache.
        cached = tmp_path / "W_TEST.txt"
        cached.write_text("FULL METHODS SECTION FROM CACHE")
        text = s.paper_text_for_doi(
            "10.0000/cached",
            prefer_full_text=True,
            cache_dir=tmp_path,
        )
        assert text == "FULL METHODS SECTION FROM CACHE"


def test_paper_text_for_doi_full_text_falls_back_to_abstract(tmp_path):
    """When cache miss + no pdf_url + no pdftotext path, fall back to
    title+abstract gracefully."""
    with CorpusStore.in_memory() as s:
        # Note: Work has pdf_url=None for this test; the cache dir is
        # empty. _fetch_full_text returns None; outer falls back.
        from crucible.corpus.openalex import Author, Work, WorkAuthor
        s.upsert_work(Work(
            work_id="W_NOPDF", doi="10.0000/nopdf",
            title="Title only",
            abstract="The abstract.",
            publication_year=2024, venue="X", cited_by_count=0,
            is_oa=False, pdf_url=None,
            authors=[WorkAuthor(author_id="A1", display_name="A",
                                position=1)],
        ))
        text = s.paper_text_for_doi(
            "10.0000/nopdf",
            prefer_full_text=True,
            cache_dir=tmp_path,
        )
        assert text is not None
        assert "Title only" in text
        assert "The abstract." in text


def test_paper_text_for_doi_full_text_off_by_default(tmp_path):
    """`prefer_full_text=False` (default) skips the network/pdftotext path
    even when the work has a pdf_url."""
    with CorpusStore.in_memory() as s:
        _seed_work(s, doi="10.0000/x", title="X", abstract="abs")
        # cache dir is empty; without prefer_full_text=True we should NOT
        # hit the cached_dir lookup at all (purely returns title+abstract).
        text = s.paper_text_for_doi("10.0000/x")
        assert "X" in text and "abs" in text


def test_post_process_pdftotext_collapses_blanks():
    from crucible.corpus.store import _post_process_pdftotext
    raw = "First paragraph.\n\n\n\n\nSecond paragraph.   \n   \nThird."
    out = _post_process_pdftotext(raw)
    assert "\n\n\n" not in out          # 3+ blank lines collapsed
    assert "paragraph.   " not in out   # trailing whitespace stripped


def test_benchmark_cli_corpus_db_flag_in_parser():
    from crucible.benchmark.cli import build_parser
    p = build_parser()
    # Argparse subparser introspection: find the run subcommand and check args
    sub_action = next(a for a in p._actions if hasattr(a, "choices") and a.choices)
    run_parser = sub_action.choices["run"]
    arg_names = {action.dest for action in run_parser._actions}
    assert "corpus_db" in arg_names
    assert "papers_dir" in arg_names


def test_benchmark_cli_add_subcommand_exists():
    from crucible.benchmark.cli import build_parser
    p = build_parser()
    sub_action = next(a for a in p._actions if hasattr(a, "choices") and a.choices)
    assert "add" in sub_action.choices
    add_parser = sub_action.choices["add"]
    arg_names = {action.dest for action in add_parser._actions}
    assert {"paper_id", "doi", "title"}.issubset(arg_names)


def test_benchmark_cli_add_rejects_duplicate_paper_id(capsys):
    """Trying to add an existing paper_id should fail cleanly without
    mutating papers.py."""
    from crucible.benchmark.cli import main
    rc = main(["add", "--paper-id", "shaw_2010_bpti",
               "--doi", "10.0000/dup", "--title", "duplicate"])
    assert rc == 1
    captured = capsys.readouterr()
    assert "already in seed set" in captured.err


def test_benchmark_cli_verify_subcommand_exists():
    from crucible.benchmark.cli import build_parser
    p = build_parser()
    sub_action = next(a for a in p._actions if hasattr(a, "choices") and a.choices)
    assert "verify" in sub_action.choices
    verify_parser = sub_action.choices["verify"]
    arg_names = {action.dest for action in verify_parser._actions}
    assert {"paper_id", "initials", "force"}.issubset(arg_names)


def test_benchmark_cli_verify_unknown_paper_fails(capsys):
    from crucible.benchmark.cli import main
    rc = main(["verify", "--paper-id", "nonexistent_2099"])
    assert rc == 1
    captured = capsys.readouterr()
    assert "unknown paper_id" in captured.err


def test_patch_entry_replaces_expected_block_and_stamps_verified_by():
    """Unit test for the patcher; doesn't require interactive input."""
    from crucible.benchmark.cli import _patch_entry
    text = '''
    BenchmarkEntry(
        paper_id="test_x",
        doi="10.0/x",
        title="X",
        expected=ExpectedProtocol(
            protein_ff=None,
        ),
        status="needs_verification",
        notes="original notes",
    ),
'''
    new_values = {"protein_ff": "amber14sb", "water_model": "TIP3P"}
    out = _patch_entry(text, paper_id="test_x", new_values=new_values,
                       verified_by="ABC 2026-05-04",
                       notes_extra=["dt: paper does not specify"])
    assert 'status="verified"' in out
    assert "verified_by='ABC 2026-05-04'" in out or 'verified_by="ABC 2026-05-04"' in out
    assert "amber14sb" in out
    assert "TIP3P" in out
    assert "[verify ABC 2026-05-04]" in out
    assert "dt: paper does not specify" in out
