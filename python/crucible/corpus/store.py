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

    def find_by_doi(self, doi: str) -> Optional[dict]:
        """Look up a single work by DOI. Accepts either the bare DOI
        (`10.1000/foo`) or the canonical URL form (`https://doi.org/10.1000/foo`).
        Returns the row dict or None.
        """
        normalized = doi.strip().lower()
        # Strip the URL prefix if present.
        for prefix in ("https://doi.org/", "http://doi.org/", "doi:"):
            if normalized.startswith(prefix):
                normalized = normalized[len(prefix):]
                break
        # OpenAlex stores DOIs as the URL form; query both shapes.
        candidates = [normalized, f"https://doi.org/{normalized}"]
        cur = self._conn.execute(
            """
            SELECT work_id, doi, title, abstract, publication_year, venue,
                   cited_by_count, is_oa, pdf_url
            FROM works
            WHERE LOWER(doi) IN ({})
            LIMIT 1
            """.format(",".join("?" * len(candidates))),
            candidates,
        )
        row = cur.fetchone()
        if row is None:
            return None
        return dict(zip([d[0] for d in cur.description], row))

    def paper_text_for_doi(self, doi: str, *,
                           prefer_full_text: bool = False,
                           cache_dir: Optional[Path] = None) -> Optional[str]:
        """Return text for benchmarking, in preference order.

        With `prefer_full_text=True` (default off because it does network
        I/O and requires `pdftotext`):
          1. cached `<cache_dir>/<work_id>.txt` if present
          2. download `pdf_url` → run pdftotext → cache → return

        Without `prefer_full_text` (or if full-text fetch fails):
          3. `title + abstract` from the local DB row

        Returns `None` only when the DOI isn't in the corpus at all.
        Network errors during full-text fetch silently fall back to
        title+abstract — the test suite doesn't pay for outbound HTTP.
        """
        row = self.find_by_doi(doi)
        if row is None:
            return None

        if prefer_full_text:
            full = _fetch_full_text(
                work_id=str(row.get("work_id") or ""),
                pdf_url=row.get("pdf_url"),
                cache_dir=cache_dir,
            )
            if full:
                return full

        parts: list[str] = []
        if row.get("title"):
            parts.append(str(row["title"]))
        if row.get("abstract"):
            parts.append(str(row["abstract"]))
        if not parts:
            return None
        return "\n\n".join(parts)

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


# -----------------------------------------------------------------------------
# Full-text fetch — opt-in helper. Uses stdlib urllib + the system pdftotext
# binary. No new runtime deps. Network failures, pdftotext failures, and
# missing-binary failures all fall through to None so the caller can fall
# back to title+abstract.

def _default_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "crucible" / "corpus_full_text"


def _fetch_full_text(*, work_id: str, pdf_url: Optional[str],
                     cache_dir: Optional[Path]) -> Optional[str]:
    """Best-effort PDF → text. Returns None on any failure.

    Caches by `work_id` so repeated runs of the benchmark don't redownload.
    pdftotext's output is post-processed lightly: collapse 3+ blank lines,
    strip trailing whitespace, drop pages of pure whitespace.
    """
    if not work_id:
        return None
    cdir = cache_dir or _default_cache_dir()
    cdir = cdir.expanduser()
    cdir.mkdir(parents=True, exist_ok=True)
    cached_txt = cdir / f"{work_id}.txt"
    if cached_txt.is_file():
        try:
            text = cached_txt.read_text()
            if text.strip():
                return text
        except OSError:
            pass

    if not pdf_url:
        return None

    if shutil.which("pdftotext") is None:
        return None

    pdf_path = cdir / f"{work_id}.pdf"
    try:
        # Stream-download with a short timeout. Anything weirder than a clean
        # 200 + application/pdf response gets dropped.
        req = urllib.request.Request(
            pdf_url,
            headers={"User-Agent": "crucible-corpus/0.3.0",
                     "Accept": "application/pdf"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            ct = (resp.headers.get("content-type") or "").lower()
            if "pdf" not in ct and not pdf_url.lower().endswith(".pdf"):
                return None
            with pdf_path.open("wb") as fh:
                while True:
                    chunk = resp.read(64 * 1024)
                    if not chunk:
                        break
                    fh.write(chunk)
    except Exception:
        if pdf_path.exists():
            pdf_path.unlink(missing_ok=True)
        return None

    try:
        proc = subprocess.run(
            ["pdftotext", "-layout", str(pdf_path), "-"],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if proc.returncode != 0:
            return None
        text = _post_process_pdftotext(proc.stdout)
        if text.strip():
            cached_txt.write_text(text)
            return text
    except Exception:
        return None
    finally:
        # Keep the cached .txt; drop the .pdf to save disk.
        pdf_path.unlink(missing_ok=True)

    return None


def _post_process_pdftotext(raw: str) -> str:
    import re
    # Collapse 3+ blank lines to 2 (paragraph separator).
    text = re.sub(r"\n{3,}", "\n\n", raw)
    # Strip trailing whitespace per line.
    text = "\n".join(line.rstrip() for line in text.splitlines())
    return text


# Imports used only by the full-text helper. Kept at the bottom so the
# main DuckDB path doesn't pay for them on first import.
import os
import shutil
import subprocess
import urllib.request
