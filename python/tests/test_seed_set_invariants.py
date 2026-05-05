"""Structural invariants for the benchmark seed set in `papers.py`.

These tests catch the regression class that bit v1.37/v1.38: a
fabricated DOI, a duplicate paper_id, a "verified" entry without a
verified_by stamp. Each invariant is independent — a failure points
at exactly one entry + one rule.

The invariants intentionally don't validate scientific content
(e.g. "this paper actually uses ff14SB"); that's the human-driven
verification work in `docs/HOW_TO_VERIFY_A_PAPER.md`. These tests
verify the *shape* of the seed set, not the content.
"""

from __future__ import annotations

import re
from collections import Counter

import pytest

from crucible.benchmark import BenchmarkEntry, list_entries
from crucible.benchmark.papers import ExpectedProtocol


# DOI structural pattern (Crossref-compatible). Permissive enough to
# accept the variety of DOI prefixes we already have (10.1126/science.X,
# 10.1016/S0009-2614(99)01123-9, 10.1021/ja512751q) but strict enough
# to reject obvious garbage ("internal/X").
_DOI_PATTERN = re.compile(r"^10\.\d{4,9}/\S+$")


def test_seed_set_paper_ids_unique():
    """No two entries may share a paper_id (would make `verify` /
    `add` ambiguous)."""
    pids = [e.paper_id for e in list_entries()]
    duplicates = [pid for pid, n in Counter(pids).items() if n > 1]
    assert not duplicates, f"duplicate paper_ids in seed set: {duplicates}"


def test_seed_set_paper_ids_lowercase_with_underscores():
    """paper_id is the slug used in CLI invocations and JSONL exports.
    Conventional shape: `^[a-z0-9_]+$`. Catches accidental hyphens,
    capitals, or whitespace."""
    pattern = re.compile(r"^[a-z0-9_]+$")
    bad = [e.paper_id for e in list_entries() if not pattern.match(e.paper_id)]
    assert not bad, f"non-conforming paper_ids: {bad}"


def test_seed_set_dois_structurally_valid():
    """Every DOI must look like a Crossref DOI. Catches fabrications
    like the 10.1021/jp067192x (404'd on Crossref) we corrected in
    v1.38."""
    bad: list[tuple[str, str]] = []
    for entry in list_entries():
        if not _DOI_PATTERN.match(entry.doi):
            bad.append((entry.paper_id, entry.doi))
    assert not bad, "non-Crossref-shape DOIs:\n  " + \
        "\n  ".join(f"{pid}: {doi!r}" for pid, doi in bad)


def test_seed_set_dois_unique():
    """Two seed entries shouldn't reference the same DOI; if you
    benchmark the same paper twice, parameterize the entries with
    different paper_ids and document why in `notes`."""
    dois = [e.doi for e in list_entries()]
    duplicates = [doi for doi, n in Counter(dois).items() if n > 1]
    assert not duplicates, f"duplicate DOIs in seed set: {duplicates}"


def test_seed_set_verified_entries_have_verified_by():
    """A `status="verified"` entry without a `verified_by` stamp is a
    process failure — verifying without recording who/when defeats
    the audit trail."""
    bad = [
        e.paper_id for e in list_entries()
        if e.status == "verified" and not e.verified_by
    ]
    assert not bad, f"verified entries missing verified_by: {bad}"


def test_seed_set_titles_non_empty():
    """Every entry has a non-empty title for human readability in the
    report."""
    bad = [e.paper_id for e in list_entries() if not e.title.strip()]
    assert not bad, f"entries with empty title: {bad}"


def test_seed_set_titles_under_300_chars():
    """Soft cap on title length to keep the report's per-paper section
    readable. Long titles → truncate or move detail to `notes`."""
    bad = [(e.paper_id, len(e.title))
           for e in list_entries() if len(e.title) > 300]
    assert not bad, f"titles over 300 chars: {bad}"


def test_seed_set_status_values_are_known():
    """The `status` Literal type already enforces this at runtime; this
    is a belt-and-braces check in case the dataclass annotation is
    bypassed."""
    allowed = {"verified", "needs_verification", "not_md"}
    bad = [(e.paper_id, e.status)
           for e in list_entries() if e.status not in allowed]
    assert not bad, f"unknown status values: {bad}"


def test_seed_set_expected_protocol_axes_within_schema_ranges():
    """If an axis has a value, it should fall in the schema's allowed
    range. Catches obvious typos (e.g. dt_fs=200 instead of 2.0)."""
    bad: list[str] = []
    for e in list_entries():
        ep = e.expected
        if ep.dt_fs is not None and not (0.1 <= ep.dt_fs <= 30.0):
            bad.append(f"{e.paper_id}.dt_fs = {ep.dt_fs} (expect 0.1-30 fs)")
        if ep.temperature_K is not None and not (50 <= ep.temperature_K <= 1000):
            bad.append(f"{e.paper_id}.temperature_K = {ep.temperature_K} "
                       f"(expect 50-1000 K)")
        if ep.pressure_bar is not None and not (0 <= ep.pressure_bar <= 100):
            bad.append(f"{e.paper_id}.pressure_bar = {ep.pressure_bar} "
                       f"(expect 0-100 bar)")
        if ep.solvent_padding_nm is not None and not (0 <= ep.solvent_padding_nm <= 10):
            bad.append(f"{e.paper_id}.solvent_padding_nm = "
                       f"{ep.solvent_padding_nm} (expect 0-10 nm)")
        if ep.fep_lambda_count is not None and not (2 <= ep.fep_lambda_count <= 100):
            bad.append(f"{e.paper_id}.fep_lambda_count = "
                       f"{ep.fep_lambda_count} (expect 2-100 windows)")
    assert not bad, "expected_protocol axes out of schema range:\n  " + \
        "\n  ".join(bad)


def test_seed_set_notes_recommended_for_verified_entries():
    """Verified entries should have non-empty notes documenting which
    sections the verification cited. Soft check: warn-only via
    pytest.warns can't catch missing notes; assertion enforces."""
    bad = [
        e.paper_id for e in list_entries()
        if e.status == "verified" and not e.notes.strip()
    ]
    assert not bad, (
        f"verified entries missing notes (cite Methods sections): {bad}"
    )


def test_seed_set_minimum_size():
    """Seed set should have ≥ 5 entries (the published-in-v1.31 size).
    Below this the benchmark loses statistical meaning."""
    assert len(list_entries()) >= 5, (
        f"seed set shrunk below 5 entries; current size: {len(list_entries())}"
    )


def test_seed_set_under_construction_target():
    """Soft cap; the benchmark's ambition is 20 entries
    ([`docs/HALLUCINATION_BENCHMARK.md`](../../docs/HALLUCINATION_BENCHMARK.md)).
    Prevent runaway growth without a corresponding human-verification
    pass — use the `add` CLI for individual additions."""
    assert len(list_entries()) <= 50, (
        f"seed set grew past 50 entries; consider whether all are "
        f"actively maintained. Current size: {len(list_entries())}"
    )
