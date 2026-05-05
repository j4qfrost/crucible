"""Streamlit dashboard for the benchmark runs DB.

Companion to v1.29's corpus GUI. Shows the longitudinal data
captured by v1.45+ (`benchmark_runs` table) in a browsable form:
overall stats, per-provider, per-axis accuracy, per-paper trends,
and a raw-rows tab with filters.

Run with:

    pip install crucible[corpus,ui]      # streamlit + duckdb
    python -m crucible benchmark ui --runs-db ~/.local/share/crucible/corpus.duckdb

Or via the inner CLI:

    python -m crucible.benchmark.ui

Read-only. The dashboard never mutates the DB; mutations go through
`benchmark run` / `benchmark publish` from the CLI.
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
        "the benchmark dashboard requires streamlit. Install with "
        "`pip install crucible[corpus,ui]`."
    ) from exc

from .runs_store import (
    open_runs_store,
    per_axis_accuracy,
    per_provider_summary,
    runs_for_paper,
    schema_version_distribution,
    stats,
    trends,
)


def _default_db_path() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return Path(base) / "crucible" / "corpus.duckdb"


@st.cache_resource
def _open(db_path: str):
    return open_runs_store(db_path)


def main() -> None:
    st.set_page_config(page_title="Crucible benchmark", page_icon="📊",
                       layout="wide")
    st.title("📊 Crucible — benchmark runs")
    st.caption(
        "Longitudinal data layer for the hallucination benchmark. "
        "Read-only browser; mutations go through `benchmark run` + "
        "`benchmark publish` from the CLI."
    )

    # ---- Sidebar: DB picker + headline stats -------------------------------
    with st.sidebar:
        st.subheader("Database")
        db_path = st.text_input(
            "Runs DuckDB path",
            value=os.environ.get("CRUCIBLE_RUNS_DB", str(_default_db_path())),
        )
        try:
            conn = _open(db_path)
        except Exception as exc:
            st.error(f"could not open DB: {exc}")
            return

        s = stats(conn)
        st.metric("Outcome rows", s["rows"])
        st.metric("Distinct runs", s["runs"])
        st.metric("Papers touched", s["papers_touched"])

        st.divider()
        st.subheader("Schema versions")
        for ver, n in schema_version_distribution(conn).items():
            st.write(f"`{ver}`: {n} rows")

    if s["rows"] == 0:
        st.info(
            "No outcomes recorded yet. Run "
            "`python -m crucible benchmark run --corpus-db <path> …` "
            "to populate the table."
        )
        return

    # ---- Tabs --------------------------------------------------------------
    tab_overview, tab_papers, tab_axes, tab_raw = st.tabs(
        ["Overview", "Per-paper trends", "Per-axis accuracy", "Raw rows"]
    )

    with tab_overview:
        st.subheader("Per-provider rollup")
        providers = per_provider_summary(conn)
        if providers:
            rows = [
                {
                    "Provider": p["llm_provider"],
                    "Outcomes": p["n_outcomes"],
                    "Runs": p["n_runs"],
                    "Avg accuracy": f"{p['avg_pct']:.0%}",
                }
                for p in providers
            ]
            st.dataframe(rows, use_container_width=True, hide_index=True)

    with tab_papers:
        st.subheader("Per-paper trends")
        rows = list(trends(conn))
        if rows:
            data = [
                {
                    "Paper": r.paper_id,
                    "Runs": r.n_runs,
                    "Avg accuracy": f"{r.avg_pct:.0%}",
                    "Last run": r.last_run_at,
                    "Providers": ", ".join(sorted(r.providers)),
                }
                for r in rows
            ]
            st.dataframe(data, use_container_width=True, hide_index=True)

            st.divider()
            st.subheader("Drill-in: one paper's history")
            choices = [r.paper_id for r in rows]
            selected = st.selectbox("Paper", choices, index=0)
            history = list(runs_for_paper(conn, selected, limit=200))
            if history:
                # Compute pct per row for the chart.
                for h in history:
                    if h.get("max_score"):
                        h["pct"] = h["total"] / h["max_score"]
                    else:
                        h["pct"] = None
                # Basic line chart by run_at; Streamlit handles None.
                chart_data = [
                    {"run_at": h["run_at"], "pct": h["pct"]}
                    for h in history if h["pct"] is not None
                ]
                if chart_data:
                    st.line_chart(chart_data, x="run_at", y="pct")
                st.dataframe(history, use_container_width=True, hide_index=True)

    with tab_axes:
        st.subheader("Per-axis accuracy (overall)")
        axes = per_axis_accuracy(conn)
        if axes:
            data = [
                {
                    "Axis": axis,
                    "Correct": slot["n_correct"],
                    "Scored": slot["n_scored"],
                    "Pct": f"{slot['pct']:.0%}",
                }
                for axis, slot in sorted(axes.items())
            ]
            st.dataframe(data, use_container_width=True, hide_index=True)

        st.divider()
        st.subheader("Per-axis accuracy by provider")
        providers = [p["llm_provider"] for p in per_provider_summary(conn)]
        if providers:
            chosen = st.selectbox("Provider", providers, index=0)
            slice_axes = per_axis_accuracy(conn, llm_provider=chosen)
            if slice_axes:
                data = [
                    {
                        "Axis": axis,
                        "Correct": slot["n_correct"],
                        "Scored": slot["n_scored"],
                        "Pct": f"{slot['pct']:.0%}",
                    }
                    for axis, slot in sorted(slice_axes.items())
                ]
                st.dataframe(data, use_container_width=True, hide_index=True)

    with tab_raw:
        st.subheader("Raw rows")
        # Provide a basic SQL textarea for power users (read-only;
        # `crucible benchmark runs-stats` is a safer surface for
        # canonical queries).
        cur = conn.execute("""
            SELECT run_id, paper_id, run_at, llm_provider, llm_model,
                   ok, total, max_score, schema_version
            FROM benchmark_runs
            ORDER BY run_at DESC
            LIMIT 500
        """)
        cols = [d[0] for d in cur.description]
        rows = [dict(zip(cols, r)) for r in cur.fetchall()]
        st.dataframe(rows, use_container_width=True, hide_index=True)


if __name__ == "__main__":
    main()
