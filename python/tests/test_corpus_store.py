"""DuckDB CorpusStore tests — in-memory."""

from __future__ import annotations

import pytest

duckdb = pytest.importorskip("duckdb")

from crucible.corpus.openalex import Author, Work, WorkAuthor
from crucible.corpus.store import CorpusStore


def _author(aid: str = "A1", name: str = "John Chodera") -> Author:
    return Author(author_id=aid, display_name=name, h_index=56, works_count=200,
                  last_known_inst="MSKCC")


def _coauthor(aid: str, name: str) -> Author:
    return Author(author_id=aid, display_name=name)


def _work(wid: str, title: str, *, year: int = 2022,
          authors=None, refs=None, concepts=None) -> Work:
    return Work(
        work_id=wid, doi=f"10.1000/{wid.lower()}",
        title=title, abstract="abstract",
        publication_year=year, venue="JCTC",
        cited_by_count=10, is_oa=True, pdf_url=f"https://x/{wid}.pdf",
        authors=authors or [],
        referenced_work_ids=refs or [],
        concept_ids=concepts or [],
    )


def test_schema_creates_tables():
    with CorpusStore.in_memory() as s:
        rows = s._conn.execute(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'main'"
        ).fetchall()
    names = {r[0] for r in rows}
    expected = {"works", "authors", "work_authors", "work_references",
                "concepts", "work_concepts"}
    assert expected.issubset(names)


def test_upsert_author_idempotent():
    with CorpusStore.in_memory() as s:
        s.upsert_author(_author())
        s.upsert_author(_author())  # second time = update, not duplicate
        rows = s._conn.execute("SELECT * FROM authors").fetchall()
    assert len(rows) == 1


def test_upsert_work_creates_edges_and_implicit_authors():
    with CorpusStore.in_memory() as s:
        wa1 = WorkAuthor(author_id="A1", display_name="John Chodera",
                         position=1, is_corresponding=True)
        wa2 = WorkAuthor(author_id="A2", display_name="Andrea Rizzi",
                         position=2)
        w = _work("W1", "Alchemical FEP", authors=[wa1, wa2],
                  refs=["W999"], concepts=[("C1", 0.9)])
        s.upsert_work(w)
        # work + author edges + reference edge + concept edge
        n_works = s._conn.execute("SELECT COUNT(*) FROM works").fetchone()[0]
        n_auths = s._conn.execute("SELECT COUNT(*) FROM authors").fetchone()[0]
        n_wa    = s._conn.execute("SELECT COUNT(*) FROM work_authors").fetchone()[0]
        n_refs  = s._conn.execute("SELECT COUNT(*) FROM work_references").fetchone()[0]
        n_wc    = s._conn.execute("SELECT COUNT(*) FROM work_concepts").fetchone()[0]
    assert (n_works, n_auths, n_wa, n_refs, n_wc) == (1, 2, 2, 1, 1)


def test_papers_by_author_filters_since_and_orders_by_citations():
    with CorpusStore.in_memory() as s:
        wa = WorkAuthor(author_id="A1", display_name="John Chodera", position=1)
        s.upsert_author(_author())
        old = _work("W_old", "Older paper", year=2010, authors=[wa])
        new_high = Work(work_id="W_new_high", doi=None, title="Recent high-cite",
                        abstract=None, publication_year=2023, venue="JCTC",
                        cited_by_count=500, is_oa=False, pdf_url=None,
                        authors=[wa])
        new_low = Work(work_id="W_new_low", doi=None, title="Recent low-cite",
                       abstract=None, publication_year=2022, venue="JCTC",
                       cited_by_count=3, is_oa=False, pdf_url=None,
                       authors=[wa])
        for w in (old, new_high, new_low):
            s.upsert_work(w)
        papers = list(s.papers_by_author("A1", since=2020))
    titles = [p["title"] for p in papers]
    assert "Older paper" not in titles
    assert titles[0] == "Recent high-cite"   # highest cited first
    assert titles[1] == "Recent low-cite"


def test_coauthors_ranks_by_shared_work_count():
    with CorpusStore.in_memory() as s:
        a1 = WorkAuthor(author_id="A1", display_name="A One", position=1)
        a2 = WorkAuthor(author_id="A2", display_name="A Two", position=2)
        a3 = WorkAuthor(author_id="A3", display_name="A Three", position=3)
        # A1 + A2 share 2 works; A1 + A3 share 1 work
        s.upsert_work(_work("W1", "t1", authors=[a1, a2]))
        s.upsert_work(_work("W2", "t2", authors=[a1, a2]))
        s.upsert_work(_work("W3", "t3", authors=[a1, a3]))
        rows = list(s.coauthors("A1"))
    assert rows[0]["author_id"] == "A2"
    assert rows[0]["shared_works"] == 2
    assert rows[1]["author_id"] == "A3"
    assert rows[1]["shared_works"] == 1


def test_papers_citing_author_traces_citation_edge():
    with CorpusStore.in_memory() as s:
        a1 = WorkAuthor(author_id="A1", display_name="Author One", position=1)
        a2 = WorkAuthor(author_id="A2", display_name="Author Two", position=1)
        s.upsert_work(_work("W_A1", "A1's paper", authors=[a1]))
        s.upsert_work(_work("W_cites_A1", "Cites A1", authors=[a2],
                            refs=["W_A1"]))
        s.upsert_work(_work("W_unrelated", "Cites no one", authors=[a2]))
        rows = list(s.papers_citing_author("A1"))
    assert len(rows) == 1
    assert rows[0]["work_id"] == "W_cites_A1"


def test_concept_filter_in_papers_by_author():
    with CorpusStore.in_memory() as s:
        wa = WorkAuthor(author_id="A1", display_name="A1", position=1)
        s.upsert_concept("C_md", "molecular dynamics", level=1)
        s.upsert_concept("C_other", "graph theory", level=1)
        s.upsert_work(_work("W1", "MD paper", authors=[wa],
                            concepts=[("C_md", 0.9)]))
        s.upsert_work(_work("W2", "graph paper", authors=[wa],
                            concepts=[("C_other", 0.9)]))
        md_only = list(s.papers_by_author("A1", concept_id="C_md"))
    assert [p["title"] for p in md_only] == ["MD paper"]


def test_stats_counts_all_tables():
    with CorpusStore.in_memory() as s:
        wa = WorkAuthor(author_id="A1", display_name="A1", position=1)
        s.upsert_work(_work("W1", "t", authors=[wa], refs=["W2"],
                            concepts=[("C1", 1.0)]))
        stats = s.stats()
    assert stats["works"] == 1
    assert stats["authors"] == 1
    assert stats["work_authors"] == 1
    assert stats["work_references"] == 1
    assert stats["work_concepts"] == 1
