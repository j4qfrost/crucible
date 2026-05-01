"""Corpus — fetch + index whitepapers by author.

Phase-1 in-Crucible feature; designed to be standalone-shaped so a
future lift to a sibling repo (`corpusquest`) is a `git mv` away. See
[`docs/CORPUS_DESIGN.md`](../../../docs/CORPUS_DESIGN.md) for the full
evaluation.

Public API:

    from crucible.corpus import CorpusStore, OpenAlexClient

    store = CorpusStore.open("~/.local/share/crucible/corpus.duckdb")
    client = OpenAlexClient(mailto="you@example.com")

    author = client.find_author("John Chodera")
    works  = client.list_works(author.author_id, since=2020)
    store.upsert_author(author)
    for w in works:
        store.upsert_work(w)

    # Query
    papers = list(store.papers_by_author(author.author_id, since=2020))
    coauthors = list(store.coauthors(author.author_id))

`crucible-py corpus …` is the CLI entry point; see
`python/crucible/corpus/cli.py`.
"""

from __future__ import annotations

from .openalex import (
    Author,
    OpenAlexClient,
    OpenAlexError,
    Work,
    WorkAuthor,
)
from .store import CorpusStore

__all__ = [
    "Author",
    "CorpusStore",
    "OpenAlexClient",
    "OpenAlexError",
    "Work",
    "WorkAuthor",
]
