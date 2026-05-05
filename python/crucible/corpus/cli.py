"""Subcommand dispatch for `python -m crucible corpus …`."""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path

from .openalex import OpenAlexClient, OpenAlexError
from .store import CorpusStore


def _default_db_path() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return Path(base) / "crucible" / "corpus.duckdb"


def _open_store(args: argparse.Namespace) -> CorpusStore:
    return CorpusStore.open(args.db or _default_db_path())


def _emit_jsonl(rows) -> None:
    for r in rows:
        print(json.dumps(r, default=str))


def cmd_fetch(args: argparse.Namespace) -> int:
    """Fetch all works for an author into the local DB."""
    client = OpenAlexClient(mailto=args.mailto)
    author = client.find_author(args.author)
    if author is None:
        print(f"no author found matching {args.author!r}", file=sys.stderr)
        return 1
    print(f"found: {author.display_name} ({author.author_id})", file=sys.stderr)
    concept_id = None
    if args.concept:
        c = client.find_concept(args.concept)
        if c is None:
            print(f"no concept found for {args.concept!r}", file=sys.stderr)
            return 1
        concept_id = c["concept_id"]
        print(f"filter concept: {c['display_name']} ({concept_id})",
              file=sys.stderr)
    n = 0
    with _open_store(args) as store:
        store.upsert_author(author)
        if concept_id:
            store.upsert_concept(concept_id, c["display_name"], c.get("level"))
        for w in client.list_works(author.author_id, since=args.since,
                                   concept_id=concept_id):
            store.upsert_work(w)
            n += 1
            if args.limit and n >= args.limit:
                break
    print(f"upserted {n} works.", file=sys.stderr)
    return 0


def cmd_papers(args: argparse.Namespace) -> int:
    """List papers by an author from the local DB."""
    with _open_store(args) as store:
        if args.author_id:
            aid = args.author_id
        else:
            # Resolve display_name → author_id via the local DB
            cur = store._conn.execute(
                "SELECT author_id FROM authors WHERE LOWER(display_name) LIKE ?",
                [f"%{args.author.lower()}%"],
            )
            row = cur.fetchone()
            if row is None:
                print(f"no author in local DB matching {args.author!r}; "
                      f"run `corpus fetch` first.", file=sys.stderr)
                return 1
            aid = row[0]
        rows = store.papers_by_author(aid, since=args.since,
                                      concept_id=args.concept_id,
                                      limit=args.limit)
        _emit_jsonl(rows)
    return 0


def cmd_coauthors(args: argparse.Namespace) -> int:
    """List coauthors of an author by shared-work count."""
    with _open_store(args) as store:
        rows = store.coauthors(args.author_id, limit=args.limit)
        _emit_jsonl(rows)
    return 0


def cmd_authors(args: argparse.Namespace) -> int:
    """List authors in the local DB, ordered by local works count desc."""
    with _open_store(args) as store:
        sql = """
            SELECT a.author_id, a.display_name, a.last_known_inst, a.h_index,
                   COUNT(wa.work_id) AS local_works
            FROM authors a
            LEFT JOIN work_authors wa ON wa.author_id = a.author_id
            GROUP BY a.author_id, a.display_name, a.last_known_inst, a.h_index
            ORDER BY local_works DESC, a.display_name
        """
        params: list = []
        if args.limit:
            sql += " LIMIT ?"
            params.append(args.limit)
        cur = store._conn.execute(sql, params)
        cols = [d[0] for d in cur.description]
        for row in cur.fetchall():
            print(json.dumps(dict(zip(cols, row))))
    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    """Print row counts per table."""
    with _open_store(args) as store:
        s = store.stats()
    print(json.dumps(s, indent=2))
    return 0


def cmd_ui(args: argparse.Namespace) -> int:
    """Launch the Streamlit GUI."""
    import shutil, subprocess
    if shutil.which("streamlit") is None:
        print(
            "streamlit not found on PATH. Install with "
            "`pip install crucible[corpus,ui]`.",
            file=sys.stderr,
        )
        return 2
    ui_path = Path(__file__).resolve().parent / "ui.py"
    cmd = ["streamlit", "run", str(ui_path)]
    if args.port:
        cmd.extend(["--server.port", str(args.port)])
    if args.headless:
        cmd.extend(["--server.headless", "true"])
    return subprocess.call(cmd)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="crucible-corpus",
        description="Fetch + index whitepapers by author (OpenAlex backend).",
    )
    p.add_argument("--db", type=Path, default=None,
                   help="path to DuckDB store (default: ~/.local/share/crucible/corpus.duckdb)")
    sub = p.add_subparsers(dest="cmd", required=True)

    pf = sub.add_parser("fetch", help="fetch works for an author from OpenAlex")
    pf.add_argument("author", help="display name to search OpenAlex (e.g. 'John Chodera')")
    pf.add_argument("--since", type=int, default=None,
                    help="earliest publication year to include")
    pf.add_argument("--concept", default=None,
                    help="concept name to filter on (e.g. 'molecular dynamics')")
    pf.add_argument("--limit", type=int, default=None,
                    help="cap the number of works upserted")
    pf.add_argument("--mailto", default=os.environ.get("CRUCIBLE_OPENALEX_EMAIL"),
                    help="polite-pool email (or set CRUCIBLE_OPENALEX_EMAIL)")
    pf.set_defaults(func=cmd_fetch)

    pp = sub.add_parser("papers", help="list papers for an author from the local DB")
    g = pp.add_mutually_exclusive_group(required=True)
    g.add_argument("--author", help="display-name substring (case-insensitive)")
    g.add_argument("--author-id", help="OpenAlex A… id")
    pp.add_argument("--since", type=int, default=None)
    pp.add_argument("--concept-id", default=None)
    pp.add_argument("--limit", type=int, default=None)
    pp.set_defaults(func=cmd_papers)

    pc = sub.add_parser("coauthors", help="list coauthors of an author")
    pc.add_argument("author_id", help="OpenAlex A… id of the focal author")
    pc.add_argument("--limit", type=int, default=None)
    pc.set_defaults(func=cmd_coauthors)

    pa = sub.add_parser("authors", help="list authors in the local DB")
    pa.add_argument("--limit", type=int, default=None,
                    help="cap the number of authors emitted")
    pa.set_defaults(func=cmd_authors)

    ps = sub.add_parser("stats", help="row counts per table")
    ps.set_defaults(func=cmd_stats)

    pu = sub.add_parser("ui", help="launch the Streamlit GUI")
    pu.add_argument("--port", type=int, default=None)
    pu.add_argument("--headless", action="store_true",
                    help="run without auto-opening a browser tab")
    pu.set_defaults(func=cmd_ui)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except OpenAlexError as exc:
        print(f"openalex error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
