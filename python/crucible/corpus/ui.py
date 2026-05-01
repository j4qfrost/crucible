"""Streamlit GUI for the corpus.

Run with:

    pip install crucible[corpus,ui]
    python -m crucible corpus ui

Or directly:

    streamlit run python/crucible/corpus/ui.py

Read-only data explorer + an inline "fetch author" form. Backed by the
local DuckDB store. The corpus module is otherwise framework-free; the
GUI is opt-in via the `[corpus,ui]` extra so headless users don't
pull Streamlit.

Sections:
    1. DB picker + stats sidebar
    2. Fetch new author (subprocesses to OpenAlex)
    3. Browse authors / papers (filters: year, concept, citations)
    4. Coauthor table for a focal author
    5. Citation in/out neighborhood (1 hop)
    6. JSONL export of the current paper view
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Optional

try:
    import streamlit as st
except ImportError as exc:  # pragma: no cover — UI dep is optional
    raise ImportError(
        "the corpus GUI requires streamlit. Install with "
        "`pip install crucible[corpus,ui]`."
    ) from exc

from .openalex import OpenAlexClient, OpenAlexError
from .store import CorpusStore


# -----------------------------------------------------------------------------
# Helpers

def _default_db_path() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return Path(base) / "crucible" / "corpus.duckdb"


@st.cache_resource
def _open_store(db_path: str) -> CorpusStore:
    return CorpusStore.open(db_path)


def _list_authors(store: CorpusStore) -> list[dict]:
    cur = store._conn.execute(
        """
        SELECT a.author_id, a.display_name, a.last_known_inst, a.h_index,
               COUNT(wa.work_id) AS local_works
        FROM authors a
        LEFT JOIN work_authors wa ON wa.author_id = a.author_id
        GROUP BY a.author_id, a.display_name, a.last_known_inst, a.h_index
        ORDER BY local_works DESC, a.display_name
        """
    )
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def _list_concepts(store: CorpusStore) -> list[dict]:
    cur = store._conn.execute(
        "SELECT concept_id, display_name, level FROM concepts ORDER BY display_name"
    )
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


# -----------------------------------------------------------------------------
# Page

def main() -> None:
    st.set_page_config(page_title="Crucible Corpus", page_icon="📚", layout="wide")
    st.title("📚 Crucible — Corpus")
    st.caption(
        "Whitepapers indexed from OpenAlex, stored in a local DuckDB graph. "
        "Read-only browser + an inline fetch form. "
        "See `docs/CORPUS_DESIGN.md` for the architecture."
    )

    # ---- Sidebar: DB picker + stats ----------------------------------------
    with st.sidebar:
        st.subheader("Database")
        db_path = st.text_input("DuckDB path", value=str(_default_db_path()))
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        store = _open_store(db_path)
        stats = store.stats()
        st.metric("Works",          stats["works"])
        st.metric("Authors",        stats["authors"])
        st.metric("Citations",      stats["work_references"])
        st.metric("Concepts",       stats["concepts"])
        with st.expander("Raw counts"):
            st.json(stats)

        st.divider()
        st.subheader("Fetch new author")
        st.caption(
            "Calls OpenAlex (free, no auth). Set "
            "`CRUCIBLE_OPENALEX_EMAIL` to use the polite pool."
        )
        with st.form("fetch_form"):
            new_name = st.text_input("Display name", placeholder="John Chodera")
            new_concept = st.text_input(
                "Concept filter (optional)", placeholder="molecular dynamics"
            )
            new_since = st.number_input(
                "Since year", min_value=1900, max_value=2100, value=2018
            )
            new_limit = st.number_input(
                "Max works", min_value=1, max_value=10_000, value=200
            )
            submitted = st.form_submit_button("Fetch")
        if submitted and new_name:
            _fetch(store, new_name, new_concept or None,
                   int(new_since), int(new_limit))

    # ---- Tabs --------------------------------------------------------------
    tab_papers, tab_coauthors, tab_neighbor = st.tabs(
        ["Papers", "Coauthors", "Citation neighborhood"]
    )

    authors = _list_authors(store)
    if not authors:
        with tab_papers:
            st.info(
                "No authors in the local DB yet. Use **Fetch new author** in "
                "the sidebar to start."
            )
        return

    author_options = {f"{a['display_name']} — {a['author_id']}": a["author_id"]
                      for a in authors}
    selected_label = st.selectbox(
        "Focal author", list(author_options.keys()), index=0
    )
    aid = author_options[selected_label]

    # ---- Papers tab --------------------------------------------------------
    with tab_papers:
        col1, col2, col3 = st.columns(3)
        with col1:
            since = st.number_input("Since year", min_value=1900, max_value=2100,
                                    value=2018, key="since_papers")
        with col2:
            concepts = _list_concepts(store)
            concept_label = st.selectbox(
                "Concept", ["(any)"] + [c["display_name"] for c in concepts],
                key="concept_papers",
            )
            cid: Optional[str] = None
            if concept_label != "(any)":
                cid = next(c["concept_id"] for c in concepts
                           if c["display_name"] == concept_label)
        with col3:
            limit = st.number_input("Limit", min_value=1, max_value=10_000,
                                    value=100, key="limit_papers")
        rows = list(store.papers_by_author(aid, since=int(since),
                                           concept_id=cid, limit=int(limit)))
        st.write(f"**{len(rows)} papers**")
        if rows:
            st.dataframe(rows, use_container_width=True, hide_index=True)
            st.download_button(
                "Download as JSONL",
                data="\n".join(json.dumps(r, default=str) for r in rows),
                file_name=f"{aid}_papers.jsonl",
                mime="application/x-ndjson",
            )

    # ---- Coauthors tab -----------------------------------------------------
    with tab_coauthors:
        coauthors = list(store.coauthors(aid, limit=200))
        st.write(f"**{len(coauthors)} coauthors** (ranked by shared-work count)")
        if coauthors:
            st.dataframe(coauthors, use_container_width=True, hide_index=True)

    # ---- Citation-neighborhood tab ----------------------------------------
    with tab_neighbor:
        st.caption(
            "1-hop view: papers that cite the focal author's works (incoming) and "
            "papers cited by the focal author's works (outgoing). Uses local data "
            "only — gaps are normal until you fetch the cited / citing authors."
        )
        c1, c2 = st.columns(2)
        with c1:
            st.subheader("Incoming citations")
            incoming = list(store.papers_citing_author(aid, limit=50))
            st.write(f"{len(incoming)} papers")
            if incoming:
                st.dataframe(incoming, use_container_width=True, hide_index=True)
        with c2:
            st.subheader("Outgoing citations (cited works)")
            cur = store._conn.execute(
                """
                SELECT DISTINCT wr.cited_work_id AS work_id,
                                w.title, w.publication_year, w.cited_by_count
                FROM work_references wr
                JOIN work_authors wa ON wa.work_id = wr.citing_work_id
                LEFT JOIN works w ON w.work_id = wr.cited_work_id
                WHERE wa.author_id = ?
                ORDER BY w.cited_by_count DESC NULLS LAST
                LIMIT 50
                """,
                [aid],
            )
            cols = [d[0] for d in cur.description]
            outgoing = [dict(zip(cols, row)) for row in cur.fetchall()]
            st.write(f"{len(outgoing)} cited works")
            if outgoing:
                st.dataframe(outgoing, use_container_width=True, hide_index=True)


# -----------------------------------------------------------------------------
# Fetch action — wraps the OpenAlex client with a Streamlit progress bar

def _fetch(store: CorpusStore, name: str, concept_name: Optional[str],
           since: int, limit: int) -> None:
    client = OpenAlexClient(mailto=os.environ.get("CRUCIBLE_OPENALEX_EMAIL"))
    try:
        with st.spinner(f"Searching OpenAlex for {name!r}…"):
            author = client.find_author(name)
        if author is None:
            st.error(f"No author found matching {name!r}.")
            return
        st.success(f"Found {author.display_name} ({author.author_id})")
        store.upsert_author(author)
        concept_id: Optional[str] = None
        if concept_name:
            with st.spinner(f"Resolving concept {concept_name!r}…"):
                c = client.find_concept(concept_name)
            if c is None:
                st.warning(f"Concept {concept_name!r} not found; ignoring filter.")
            else:
                concept_id = c["concept_id"]
                store.upsert_concept(concept_id, c["display_name"], c.get("level"))

        progress = st.progress(0.0, text="Fetching works…")
        n = 0
        for w in client.list_works(author.author_id, since=since,
                                   concept_id=concept_id):
            store.upsert_work(w)
            n += 1
            progress.progress(min(n / limit, 1.0),
                              text=f"Fetched {n} / ~{limit}")
            if n >= limit:
                break
        progress.empty()
        st.success(f"Upserted {n} works for {author.display_name}.")
    except OpenAlexError as exc:
        st.error(f"OpenAlex error: {exc}")


if __name__ == "__main__":
    main()
