"""Markdown report generator for the hallucination benchmark.

Output is the source of `docs/HALLUCINATION_BENCHMARK.md`. Designed
for direct paste into a blog post or arXiv preprint (campaign asset
#2 + #4 in `docs/CAMPAIGN_2026Q2.md`).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from .papers import BenchmarkEntry
from .runner import RunOutcome
from .scorer import ScoreAxis


def render_report(
    pairs: Iterable[tuple[BenchmarkEntry, RunOutcome]],
    *,
    title: str = "Hallucination benchmark",
    intro: str | None = None,
    timestamp: datetime | None = None,
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

    # Per-paper detail
    lines.append("## Per-paper detail")
    lines.append("")
    for entry, outcome in pairs:
        verified_tag = "✅ verified" if entry.is_scoreable() else \
                       f"⚠ {entry.status}"
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
