"""Curated benchmark entries — `(paper, ground-truth-protocol)` pairs.

The seed set is **stubs marked `needs_verification`**. Each entry must
be cross-checked against the original Methods section by a human before
it can count toward the published benchmark — this is enforced by
`scorer.score()` raising on unverified entries unless `allow_unverified=True`.

Trade-off (documented in `docs/CORPUS_DESIGN.md` and reinforced by the
salt-mines verdict): a benchmark with fabricated ground truth is worse
than no benchmark. The framework prefers honest empty over confident
wrong.

How to verify an entry:

1. Open the DOI; read the Methods section.
2. Compare each `ExpectedProtocol` field against what the paper states
   (or omits — `None` is a valid ground-truth value when the paper
   doesn't specify a knob).
3. Set `status="verified"` and add your initials + date to `verified_by`.
4. If the paper covers something the schema doesn't (free-energy
   methods variant, custom integrator, etc.), record that in `notes`
   so the benchmark report calls it out.

Adding entries: append to `_SEED_ENTRIES` and rerun the benchmark.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, Optional


@dataclass(frozen=True)
class ExpectedProtocol:
    """The 8 binary axes the LLM is graded on.

    Set a field to `None` when the paper deliberately doesn't specify
    that knob (rare for the major axes; common for `pressure_bar` in
    NVT-only protocols). `None` matches `None` in the LLM output;
    a value matches by exact equality (numerics) or string equality
    (FF / model / ensemble names).
    """
    protein_ff: Optional[str] = None         # e.g. "amber14sb"
    water_model: Optional[str] = None        # e.g. "TIP3P"
    ensemble: Optional[str] = None           # NVE / NVT / NPT (production stage)
    dt_fs: Optional[float] = None
    temperature_K: Optional[float] = None
    duration_ns: Optional[float] = None      # production stage; ladder/window for FEP/REMD
    pressure_bar: Optional[float] = None     # required if ensemble == NPT
    fep_lambda_count: Optional[int] = None   # 0/None for non-FEP papers


@dataclass
class BenchmarkEntry:
    """One paper in the benchmark."""
    paper_id: str                            # short slug, e.g. "shaw_2010_bpti"
    doi: str                                 # canonical DOI
    title: str
    expected: ExpectedProtocol
    status: Literal["verified", "needs_verification", "not_md"] = "needs_verification"
    verified_by: Optional[str] = None        # "AQN 2026-05-04" once human-verified
    notes: str = ""

    def is_scoreable(self) -> bool:
        return self.status == "verified"


# -----------------------------------------------------------------------------
# Seed set — STUBS. Every entry is `needs_verification` until a human reads
# the paper. Expand toward 20 by following the methodology in this file's
# docstring + `docs/CORPUS_DESIGN.md`.

_SEED_ENTRIES: list[BenchmarkEntry] = [
    BenchmarkEntry(
        paper_id="shaw_2010_bpti",
        doi="10.1126/science.1187409",
        title="Atomic-Level Characterization of the Structural Dynamics of Proteins "
              "(Shaw et al., 2010)",
        expected=ExpectedProtocol(
            # The Anton BPTI 1ms run. Only `duration_ns` is verified from the
            # abstract (PubMed PMID 20947758): "a 1-millisecond simulation".
            # The remaining fields below are commonly-cited in secondary
            # literature but the SI is paywalled and has not been read by a
            # human. Status stays `needs_verification` until SI confirms.
            protein_ff="amber99sb_ildn",     # widely cited; SI verification required
            water_model="TIP3P",             # widely cited; SI verification required
            ensemble="NPT",                  # widely cited; SI verification required
            dt_fs=2.5,                       # Anton typical; SI verification required
            temperature_K=300.0,             # widely cited; SI verification required
            duration_ns=1_000_000.0,         # ✓ verified from abstract (1 ms)
            pressure_bar=1.0,                # widely cited; SI verification required
            fep_lambda_count=None,
        ),
        notes="Anton BPTI 1ms benchmark. DOI corrected from a previous "
              "title-mismatch (slug formerly cited as 'lindorff_2010_bpti'; "
              "Lindorff-Larsen is co-author #3, not first). Only "
              "`duration_ns=1_000_000` is evidence-backed (PubMed abstract); "
              "the FF/water/ensemble/dt/T/pressure values shown are the "
              "values commonly cited in subsequent MD literature, but the "
              "Science SI is paywalled and has not been confirmed by a "
              "human. Mark verified only after SI inspection.",
    ),
    BenchmarkEntry(
        paper_id="mobley_2007_alchemical_binding",
        doi="10.1021/jp067192x",
        title="Predicting absolute ligand binding free energies to a simple model site "
              "(Mobley, Chodera, Dill, 2007)",
        expected=ExpectedProtocol(
            protein_ff="amber99sb_ildn",
            water_model="TIP3P",
            ensemble="NPT",
            dt_fs=2.0,
            temperature_K=300.0,
            duration_ns=None,
            pressure_bar=1.0,
            fep_lambda_count=None,           # paper uses ~12-22 windows; verify exact count
        ),
        notes="Reference FEP paper. Lambda window count varies by system; pick one "
              "system from the paper and lock the count for scoring.",
    ),
    BenchmarkEntry(
        paper_id="sugita_okamoto_1999_remd",
        doi="10.1016/S0009-2614(99)01123-9",
        title="Replica-exchange molecular dynamics method for protein folding "
              "(Sugita & Okamoto, 1999)",
        expected=ExpectedProtocol(
            protein_ff=None,                 # paper uses CHARMM; verify exact version
            water_model=None,                # implicit / vacuum in some sections
            ensemble="NVT",
            dt_fs=None,
            temperature_K=None,              # ladder, not single value; benchmark scores rung-0
            duration_ns=None,
            pressure_bar=None,
            fep_lambda_count=None,
        ),
        notes="Foundational REMD paper. Protocol details vary across the worked examples; "
              "before verification, decide which example (alanine dipeptide / Met-enkephalin) "
              "is the canonical reference for benchmarking.",
    ),
    BenchmarkEntry(
        paper_id="wang_2015_fep_plus",
        doi="10.1021/ja512751q",
        title="Accurate and reliable prediction of relative ligand binding potency in "
              "prospective drug discovery by way of a modern free-energy calculation "
              "protocol and force field (Wang et al., 2015)",
        expected=ExpectedProtocol(
            protein_ff=None,                 # OPLS3 in this paper; not in our allowlist; verify
            water_model="TIP3P",             # commonly TIP3P; verify
            ensemble="NPT",
            dt_fs=None,
            temperature_K=300.0,
            duration_ns=None,
            pressure_bar=1.0,
            fep_lambda_count=12,             # FEP+ commonly 12 windows; verify
        ),
        notes="FEP+ landmark. The protein FF (OPLS3) is outside Crucible's allowlist; "
              "score the LLM extraction by what it WOULD pick (e.g. 'amber14sb' as the "
              "closest-allowed) and document the FF-coverage gap.",
    ),
    BenchmarkEntry(
        paper_id="salomon_ferrer_2013_amber_gpu",
        doi="10.1021/ct400314y",
        title="Routine microsecond molecular dynamics simulations with AMBER on GPUs "
              "(Salomon-Ferrer et al., 2013)",
        expected=ExpectedProtocol(
            protein_ff="amber14sb",          # commonly ff14SB or close; verify per system
            water_model="TIP3P",
            ensemble="NPT",
            dt_fs=2.0,
            temperature_K=300.0,
            duration_ns=None,
            pressure_bar=1.0,
            fep_lambda_count=None,
        ),
        notes="Tooling paper. Protocols are documented per worked example; pick one "
              "(e.g. dihydrofolate reductase) and verify before scoring.",
    ),
]


def list_entries() -> list[BenchmarkEntry]:
    """Return the seed set (verified + unverified)."""
    return list(_SEED_ENTRIES)


def load_seed_set(*, verified_only: bool = False) -> list[BenchmarkEntry]:
    """Load the seed set. With `verified_only=True`, drops `needs_verification` entries."""
    if verified_only:
        return [e for e in _SEED_ENTRIES if e.is_scoreable()]
    return list(_SEED_ENTRIES)
