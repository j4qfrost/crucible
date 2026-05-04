"""Hallucination benchmark — measure LLM protocol-extraction accuracy.

Phase A weeks 2-3 deliverable from `docs/COMMERCIAL_VALIDATION_PLAN.md`.
Direct input to campaign asset #2 (`docs/CAMPAIGN_2026Q2.md`) and to
the option-3 fine-tune flywheel (`docs/ADOPTION_PLAN.md` Phase 4).

Public API:

    from crucible.benchmark import (
        BenchmarkEntry, score, run, render_report, load_seed_set,
    )

    # Seed set of (paper, ground-truth-protocol) pairs.
    entries = load_seed_set()

    # Score a single LLM-emitted MDSpec against an entry's ground truth.
    result = score(entries[0], llm_emitted_mdspec)
    # → ScoreResult(per_axis={protein_ff: True, water: True, ...}, total=6)

    # Render a markdown report from an iterable of (entry, result) pairs.
    md = render_report(results)

The benchmark deliberately does NOT ship a curated 20-paper ground
truth. Each entry must be hand-verified against the original Methods
section before it counts. The seed set under `papers.py` is marked
``status="needs_verification"`` until a human has read the paper and
flipped the field — this prevents the benchmark from being silently
wrong (the worst possible outcome, per the technical-feasibility
panelist in the salt-mines verdict).
"""

from __future__ import annotations

from .papers import (
    BenchmarkEntry,
    ExpectedProtocol,
    list_entries,
    load_seed_set,
)
from .scorer import ScoreAxis, ScoreResult, score
from .reporter import render_report
from .runner import RunOutcome, run

__all__ = [
    "BenchmarkEntry",
    "ExpectedProtocol",
    "ScoreAxis",
    "ScoreResult",
    "RunOutcome",
    "list_entries",
    "load_seed_set",
    "render_report",
    "run",
    "score",
]
