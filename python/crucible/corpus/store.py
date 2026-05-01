"""DuckDB-backed corpus store.

Adjacency-tables design (see `docs/CORPUS_DESIGN.md`). Pure Python +
DuckDB; no graph DB.

Open with `CorpusStore.open(path)` for an on-disk store, or
`CorpusStore.in_memory()` for tests.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional

from .openalex import Author, Work


_SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"

# DuckDB's Python `execute` chokes on `--` line comments inside a
# multi-statement string. We mirror schema.sql here as a list of
# statement strings so the file remains the documented source while
# the runtime path is comment-free. Keep both in sync; the file is
# also useful for migration tooling later.
_SCHEMA_STATEMENTS = [
    """
    CREATE TABLE IF NOT EXISTS works (
        work_id          TEXT PRIMARY KEY,
        doi              TEXT,
        title            TEXT,
        abstract         TEXT,
        publication_year INTEGER,
        venue            TEXT,
        cited_by_count   INTEGER DEFAULT 0,
        is_oa            BOOLEAN DEFAULT FALSE,
        pdf_url          TEXT,
        fetched_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS authors (
        author_id        TEXT PRIMARY KEY,
        display_name     TEXT NOT NULL,
        orcid            TEXT,
        h_index          INTEGER,
        works_count      INTEGER,
        last_known_inst  TEXT,
        fetched_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS work_authors (
        work_id          TEXT,
        author_id        TEXT,
        position         INTEGER,
        is_corresponding BOOLEAN DEFAULT FALSE,
        PRIMARY KEY (work_id, author_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS work_references (
        citing_work_id   TEXT,
        cited_work_id    TEXT,
        PRIMARY KEY (citing_work_id, cited_work_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS concepts (
        concept_id       TEXT PRIMARY KEY,
        display_name     TEXT,
        level            INTEGER
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS work_concepts (
        work_id          TEXT,
        concept_id       TEXT,
        score            DOUBLE,
        PRIMARY KEY (work_id, concept_id)
    )
    """,
    "CREATE INDEX IF NOT EXISTS works_year_idx       ON works (publication_year)",
    "CREATE INDEX IF NOT EXISTS work_authors_aid_idx ON work_authors (author_id)",
    "CREATE INDEX IF NOT EXISTS work_concepts_cid_idx ON work_concepts (concept_id)",
    "CREATE INDEX IF NOT EXISTS work_refs_citing_idx ON work_references (citing_work_id)",
    "CREATE INDEX IF NOT EXISTS work_refs_cited_idx  ON work_references (cited_work_id)",
]


class CorpusStore:
    """Thin wrapper around a DuckDB connection.

    DuckDB is imported lazily so the rest of `crucible` doesn't pay
    for it; users opt into the corpus via
    `pip install crucible[corpus]`.
    """

    def __init__(self, conn: Any) -> None:
        self._conn = conn
        self._init_schema()

    # ------------------------------------------------------------------
    # Constructors

    @classmethod
    def open(cls, path: str | Path) -> "CorpusStore":
        try:
            import duckdb
        except ImportError as exc:
            raise ImportError(
                "the corpus module requires duckdb. Install with "
                "`pip install crucible[corpus]`."
            ) from exc
        path = Path(path).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        conn = duckdb.connect(str(path))
        return cls(conn)

    @classmethod
    def in_memory(cls) -> "CorpusStore":
        try:
            import duckdb
        except ImportError as exc:
            raise ImportError(
                "the corpus module requires duckdb. Install with "
                "`pip install crucible[corpus]`."
            ) from exc
        return cls(duckdb.connect(":memory:"))

    def close(self) -> None:
        self._conn.close()

    def __enter__(self) -> "CorpusStore":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # ------------------------------------------------------------------
    # Schema

    def _init_schema(self) -> None:
        for stmt in _SCHEMA_STATEMENTS:
            self._conn.execute(stmt)

    # ------------------------------------------------------------------
    # Upserts

    def upsert_author(self, author: Author) -> None:
        self._conn.execute(
            """
            INSERT INTO authors (author_id, display_name, orcid, h_index,
                                 works_count, last_known_inst)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (author_id) DO UPDATE SET
                display_name    = excluded.display_name,
                orcid           = excluded.orcid,
                h_index         = excluded.h_index,
                works_count     = excluded.works_count,
                last_known_inst = excluded.last_known_inst
            """,
            [
                author.author_id, author.display_name, author.orcid,
                author.h_index, author.works_count, author.last_known_inst,
            ],
        )

    def upsert_work(self, work: Work) -> None:
        self._conn.execute(
            """
            INSERT INTO works (work_id, doi, title, abstract,
                               publication_year, venue, cited_by_count,
                               is_oa, pdf_url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (work_id) DO UPDATE SET
                doi              = excluded.doi,
                title            = excluded.title,
                abstract         = excluded.abstract,
                publication_year = excluded.publication_year,
                venue            = excluded.venue,
                cited_by_count   = excluded.cited_by_count,
                is_oa            = excluded.is_oa,
                pdf_url          = excluded.pdf_url
            """,
            [
                work.work_id, work.doi, work.title, work.abstract,
                work.publication_year, work.venue, work.cited_by_count,
                work.is_oa, work.pdf_url,
            ],
        )
        # Edges
        for wa in work.authors:
            self._conn.execute(
                """
                INSERT INTO authors (author_id, display_name)
                VALUES (?, ?)
                ON CONFLICT (author_id) DO NOTHING
                """,
                [wa.author_id, wa.display_name],
            )
            self._conn.execute(
                """
                INSERT INTO work_authors (work_id, author_id, position,
                                          is_corresponding)
                VALUES (?, ?, ?, ?)
                ON CONFLICT (work_id, author_id) DO UPDATE SET
                    position         = excluded.position,
                    is_corresponding = excluded.is_corresponding
                """,
                [work.work_id, wa.author_id, wa.position, wa.is_corresponding],
            )
        for cited in work.referenced_work_ids:
            self._conn.execute(
                """
                INSERT INTO work_references (citing_work_id, cited_work_id)
                VALUES (?, ?)
                ON CONFLICT DO NOTHING
                """,
                [work.work_id, cited],
            )
        for cid, score in work.concept_ids:
            self._conn.execute(
                """
                INSERT INTO work_concepts (work_id, concept_id, score)
                VALUES (?, ?, ?)
                ON CONFLICT (work_id, concept_id) DO UPDATE SET score = excluded.score
                """,
                [work.work_id, cid, score],
            )

    def upsert_concept(self, concept_id: str, display_name: str,
                       level: Optional[int] = None) -> None:
        self._conn.execute(
            """
            INSERT INTO concepts (concept_id, display_name, level)
            VALUES (?, ?, ?)
            ON CONFLICT (concept_id) DO UPDATE SET
                display_name = excluded.display_name,
                level        = COALESCE(excluded.level, concepts.level)
            """,
            [concept_id, display_name, level],
        )

    # ------------------------------------------------------------------
    # Queries

    def papers_by_author(
        self,
        author_id: str,
        *,
        since: Optional[int] = None,
        concept_id: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> Iterator[dict]:
        sql = """
            SELECT w.work_id, w.doi, w.title, w.abstract, w.publication_year,
                   w.venue, w.cited_by_count, w.is_oa, w.pdf_url
            FROM works w
            JOIN work_authors wa ON wa.work_id = w.work_id
            WHERE wa.author_id = ?
        """
        params: list = [author_id]
        if since is not None:
            sql += " AND w.publication_year >= ?"
            params.append(since)
        if concept_id is not None:
            sql += """
                AND w.work_id IN (
                    SELECT work_id FROM work_concepts WHERE concept_id = ?
                )
            """
            params.append(concept_id)
        sql += " ORDER BY w.cited_by_count DESC, w.publication_year DESC"
        if limit is not None:
            sql += " LIMIT ?"
            params.append(limit)
        cur = self._conn.execute(sql, params)
        cols = [d[0] for d in cur.description]
        for row in cur.fetchall():
            yield dict(zip(cols, row))

    def coauthors(self, author_id: str, *, limit: Optional[int] = None) -> Iterator[dict]:
        """Authors who have coauthored ≥1 work with `author_id`,
        ranked by shared-work count.
        """
        sql = """
            SELECT a.author_id, a.display_name, a.last_known_inst,
                   COUNT(*) AS shared_works
            FROM work_authors wa1
            JOIN work_authors wa2 ON wa1.work_id = wa2.work_id
            JOIN authors a ON a.author_id = wa2.author_id
            WHERE wa1.author_id = ? AND wa2.author_id <> ?
            GROUP BY a.author_id, a.display_name, a.last_known_inst
            ORDER BY shared_works DESC, a.display_name
        """
        params: list = [author_id, author_id]
        if limit is not None:
            sql += " LIMIT ?"
            params.append(limit)
        cur = self._conn.execute(sql, params)
        cols = [d[0] for d in cur.description]
        for row in cur.fetchall():
            yield dict(zip(cols, row))

    def papers_citing_author(self, author_id: str, *,
                             limit: Optional[int] = None) -> Iterator[dict]:
        """Works that cite ≥1 paper authored by `author_id`."""
        sql = """
            SELECT DISTINCT w.work_id, w.doi, w.title, w.publication_year,
                            w.cited_by_count
            FROM work_references wr
            JOIN work_authors wa ON wa.work_id = wr.cited_work_id
            JOIN works w ON w.work_id = wr.citing_work_id
            WHERE wa.author_id = ?
            ORDER BY w.cited_by_count DESC
        """
        params: list = [author_id]
        if limit is not None:
            sql += " LIMIT ?"
            params.append(limit)
        cur = self._conn.execute(sql, params)
        cols = [d[0] for d in cur.description]
        for row in cur.fetchall():
            yield dict(zip(cols, row))

    def stats(self) -> dict:
        out: dict[str, int] = {}
        for table in ("works", "authors", "work_authors", "work_references",
                      "concepts", "work_concepts"):
            (n,) = self._conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
            out[table] = n
        return out
