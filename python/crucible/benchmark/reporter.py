"""Markdown report generator for the hallucination benchmark.

Output is the source of `docs/HALLUCINATION_BENCHMARK.md`. Designed
for direct paste into a blog post or arXiv preprint (campaign asset
#2 + #4 in `docs/CAMPAIGN_2026Q2.md`).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from typing import Any, Optional

from .papers import BenchmarkEntry
from .runner import RunOutcome
from .scorer import ScoreAxis


def render_runs_stats_md(runs_db: Any) -> str:
    """Markdown summary of the runs DB — embeddable variant of the
    `benchmark runs-stats` JSON output.

    Three sections: per-provider rollup, per-axis accuracy, schema
    distribution. Returns empty string on empty DB.
    """
    from .runs_store import (
        per_axis_accuracy, per_provider_summary,
        schema_version_distribution, stats,
    )

    s = stats(runs_db)
    if s["rows"] == 0:
        return ""
    lines: list[str] = ["## Runs-DB statistics", ""]
    lines.append(
        f"_{s['rows']} outcome row(s) across {s['runs']} run(s) "
        f"on {s['papers_touched']} distinct paper(s)._"
    )
    lines.append("")

    providers = per_provider_summary(runs_db)
    if providers:
        lines.append("### Per-provider")
        lines.append("")
        lines.append("| Provider | Outcomes | Runs | Avg accuracy |")
        lines.append("|---|---:|---:|---:|")
        for p in providers:
            lines.append(
                f"| `{p['llm_provider']}` | {p['n_outcomes']} | "
                f"{p['n_runs']} | {p['avg_pct']:.0%} |"
            )
        lines.append("")

    axis_acc = per_axis_accuracy(runs_db)
    if axis_acc:
        lines.append("### Per-axis accuracy")
        lines.append("")
        lines.append("| Axis | Correct | Scored | Pct |")
        lines.append("|---|---:|---:|---:|")
        for axis, slot in sorted(axis_acc.items()):
            lines.append(
                f"| `{axis}` | {slot['n_correct']} | {slot['n_scored']} | "
                f"{slot['pct']:.0%} |"
            )
        lines.append("")

    dist = schema_version_distribution(runs_db)
    if dist:
        lines.append("### Schema-version distribution")
        lines.append("")
        for ver, n in dist.items():
            lines.append(f"- `{ver}`: {n}")
        lines.append("")
    return "\n".join(lines)


def render_trend_section(runs_db: Any) -> str:
    """Markdown section showing per-paper accuracy trends from the runs DB.

    `runs_db` is a DuckDB connection produced by
    `runs_store.open_runs_store(path)`. Returns an empty string when the
    table is empty, so the caller can unconditionally interpolate it.
    """
    from .runs_store import stats, trends

    rows = list(trends(runs_db))
    if not rows:
        return ""
    s = stats(runs_db)
    lines: list[str] = ["## Longitudinal trends", ""]
    lines.append(
        f"_{s['rows']} outcome row(s) across {s['runs']} run(s) on "
        f"{s['papers_touched']} distinct paper(s)._"
    )
    lines.append("")
    lines.append("| Paper | Runs | Avg accuracy | Last run | Providers |")
    lines.append("|---|---:|---:|---|---|")
    for r in rows:
        providers = ", ".join(sorted(r.providers))
        lines.append(
            f"| `{r.paper_id}` | {r.n_runs} | {r.avg_pct:.0%} | "
            f"{r.last_run_at} | {providers} |"
        )
    lines.append("")
    return "\n".join(lines)


def render_report(
    pairs: Iterable[tuple[BenchmarkEntry, RunOutcome]],
    *,
    title: str = "Hallucination benchmark",
    intro: str | None = None,
    timestamp: datetime | None = None,
    trends_db: Any = None,
    brief: bool = False,
) -> str:
    pairs = list(pairs)
    ts = (timestamp or datetime.now(timezone.utc)).strftime("%Y-%m-%d %H:%M UTC")

    lines: list[str] = []
    lines.append(f"# {title}")
    lines.append("")
    lines.append(f"_Generated {ts}._")
    lines.append("")
    if intro:
        lines.append(intro)
        lines.append("")

    n_total = len(pairs)
    n_ok = sum(1 for _, r in pairs if r.ok)
    n_verified = sum(1 for e, _ in pairs if e.is_scoreable())

    scored_pairs = [(e, r) for e, r in pairs if r.ok and r.score_result is not None]
    aggregate_total = sum(r.score_result.total for _, r in scored_pairs)
    aggregate_max = sum(r.score_result.max_score for _, r in scored_pairs)
    overall_pct = (aggregate_total / aggregate_max) if aggregate_max else 0.0

    lines.append("## Headline")
    lines.append("")
    lines.append(f"- **{n_ok} of {n_total} papers ran cleanly** "
                 f"({n_total - n_ok} runner errors).")
    lines.append(f"- **{n_verified} of {n_total} entries are human-verified** against "
                 f"the source Methods section.")
    if scored_pairs:
        lines.append(f"- **Aggregate accuracy: {aggregate_total}/{aggregate_max} axes "
                     f"correct ({overall_pct:.0%})** across the scored runs.")
    else:
        lines.append("- **No runs scored yet** — populate the seed set with "
                     "verified entries and rerun.")
    lines.append("")

    # Per-axis breakdown
    if scored_pairs:
        lines.append("## Per-axis accuracy")
        lines.append("")
        lines.append("| Axis | Correct | Scored | Pct |")
        lines.append("|---|---:|---:|---:|")
        for axis in ScoreAxis:
            n_correct = sum(
                1 for _, r in scored_pairs
                if r.score_result.per_axis.get(axis) is True
            )
            n_scored = sum(
                1 for _, r in scored_pairs
                if r.score_result.per_axis.get(axis) is not None
            )
            pct = f"{n_correct/n_scored:.0%}" if n_scored else "—"
            lines.append(f"| `{axis.value}` | {n_correct} | {n_scored} | {pct} |")
        lines.append("")

    # Per-paper section — `--brief` uses a one-row-per-paper table; the
    # default mode emits the verbose per-axis breakdown.
    if brief:
        lines.extend(_per_paper_brief(pairs))
    else:
        lines.extend(_per_paper_verbose(pairs))

    # Optional trends section (from the longitudinal runs DB).
    if trends_db is not None:
        trend_md = render_trend_section(trends_db)
        if trend_md:
            lines.append("---")
            lines.append("")
            lines.append(trend_md)

    # Methodology footer
    lines.append("---")
    lines.append("")
    lines.append("## Methodology")
    lines.append("")
    lines.append("Each paper is scored on 8 binary axes pulled from the LLM-emitted "
                 "`MDSpec`: protein force field, water model, production-stage "
                 "ensemble, integration timestep, temperature, production duration, "
                 "barostat pressure, and FEP λ-window count. `None` ground truth "
                 "(when the paper deliberately doesn't specify a knob) drops out of "
                 "both the numerator and denominator. No partial credit. The full "
                 "scoring code is at "
                 "[`python/crucible/benchmark/scorer.py`]"
                 "(../python/crucible/benchmark/scorer.py).")
    lines.append("")
    lines.append("Entries marked `needs_verification` are stubs — their ground truth "
                 "has not been hand-checked against the original paper yet, and they "
                 "are excluded from the aggregate by default. See "
                 "[`python/crucible/benchmark/papers.py`]"
                 "(../python/crucible/benchmark/papers.py) for the verification "
                 "checklist.")
    lines.append("")
    return "\n".join(lines)


# -----------------------------------------------------------------------------
# Per-paper section helpers — extracted so render_report's body stays flat
# and the brief/verbose split is one line.

def _per_paper_brief(pairs: list[tuple[BenchmarkEntry, RunOutcome]]) -> list[str]:
    if not pairs:
        return ["## Per-paper summary", "", "_(no outcomes)_", ""]
    lines = ["## Per-paper summary", ""]
    lines.append("| Paper | Status | Score | Elapsed |")
    lines.append("|---|---|---:|---:|")
    for entry, outcome in pairs:
        verified = "✅" if entry.is_scoreable() else "⚠"
        if outcome.ok and outcome.score_result is not None:
            sr = outcome.score_result
            score_cell = f"{sr.total}/{sr.max_score} ({sr.percent:.0%})"
        else:
            score_cell = f"_{outcome.error or 'failed'}_"
        lines.append(
            f"| `{entry.paper_id}` | {verified} {entry.status} | "
            f"{score_cell} | {outcome.elapsed_s:.2f}s |"
        )
    lines.append("")
    return lines


def _per_paper_verbose(pairs: list[tuple[BenchmarkEntry, RunOutcome]]) -> list[str]:
    lines = ["## Per-paper detail", ""]
    for entry, outcome in pairs:
        verified_tag = "✅ verified" if entry.is_scoreable() else f"⚠ {entry.status}"
        lines.append(f"### `{entry.paper_id}` — {verified_tag}")
        lines.append("")
        lines.append(f"- **Title:** {entry.title}")
        lines.append(f"- **DOI:** [{entry.doi}](https://doi.org/{entry.doi})")
        lines.append(f"- **Elapsed:** {outcome.elapsed_s:.2f}s")
        if outcome.ok and outcome.score_result is not None:
            sr = outcome.score_result
            lines.append(f"- **Score:** {sr.total} / {sr.max_score} "
                         f"({sr.percent:.0%})")
            lines.append("")
            lines.append("| Axis | Expected | LLM | Match |")
            lines.append("|---|---|---|---|")
            for axis, match in sr.per_axis.items():
                expected = getattr(entry.expected, axis.value)
                if match is None:
                    mark = "—"
                elif match is True:
                    mark = "✓"
                else:
                    mark = "✗"
                lines.append(
                    f"| `{axis.value}` | {expected!r} | "
                    f"{'(see spec)' if match is not None else '—'} | {mark} |"
                )
            for note in sr.notes:
                lines.append(f"- _Note:_ {note}")
        else:
            lines.append(f"- **Error:** `{outcome.error}`")
        if entry.notes:
            lines.append("")
            lines.append(f"> {entry.notes}")
        lines.append("")
    return lines
