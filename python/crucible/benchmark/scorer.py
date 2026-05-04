"""8-axis benchmark scorer.

Compares an LLM-emitted `MDSpec` against an `ExpectedProtocol`. Each
of the 8 axes contributes 0 or 1 point. Total ranges 0-8. The scorer
deliberately does NOT do partial credit — the wedge of the benchmark
is "did the LLM get the protocol right or not?" and partial credit
makes that signal noisy.

Conventions:

* `None` in `ExpectedProtocol` means "the paper doesn't specify; don't
  score this axis." It contributes neither to the total nor to the
  denominator.
* For numeric axes, exact equality (within `rel_tol=1e-6`).
* For string axes, case-insensitive equality after lowercasing.
* For `ensemble`, we look at the LAST `DynamicsStage` in the protocol
  (the production stage). If there is no DynamicsStage, that axis
  scores 0.
* For `fep_lambda_count`, we look at the FIRST `FEPStage` in the
  protocol. If there is no FEPStage and the expected count is `None`,
  we don't score this axis. If there's no FEPStage but expected
  count > 0, we score 0.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from ..spec import DynamicsStage, FEPStage, MDSpec
from .papers import BenchmarkEntry, ExpectedProtocol


class ScoreAxis(str, Enum):
    PROTEIN_FF = "protein_ff"
    WATER_MODEL = "water_model"
    ENSEMBLE = "ensemble"
    DT_FS = "dt_fs"
    TEMPERATURE_K = "temperature_K"
    DURATION_NS = "duration_ns"
    PRESSURE_BAR = "pressure_bar"
    FEP_LAMBDA_COUNT = "fep_lambda_count"


@dataclass
class ScoreResult:
    paper_id: str
    per_axis: dict[ScoreAxis, Optional[bool]]    # None = axis not scored
    total: int                                    # number of True entries
    max_score: int                                # number of non-None entries
    notes: list[str] = field(default_factory=list)

    @property
    def percent(self) -> float:
        if self.max_score == 0:
            return 0.0
        return self.total / self.max_score


def score(
    entry: BenchmarkEntry,
    spec: MDSpec,
    *,
    allow_unverified: bool = False,
) -> ScoreResult:
    """Score `spec` against `entry.expected`."""
    if not entry.is_scoreable() and not allow_unverified:
        raise ValueError(
            f"benchmark entry {entry.paper_id!r} has status={entry.status!r}; "
            "set status='verified' after reading the paper, or call with "
            "allow_unverified=True for a dry run"
        )
    expected = entry.expected
    notes: list[str] = []

    # Find the production DynamicsStage (last DynamicsStage in protocol).
    production = None
    for s in reversed(spec.protocol):
        if isinstance(s, DynamicsStage):
            production = s
            break

    # Find the first FEPStage if any.
    fep = next((s for s in spec.protocol if isinstance(s, FEPStage)), None)

    per_axis: dict[ScoreAxis, Optional[bool]] = {}

    per_axis[ScoreAxis.PROTEIN_FF] = _score_str(
        expected.protein_ff, spec.force_field.protein,
    )
    per_axis[ScoreAxis.WATER_MODEL] = _score_str(
        expected.water_model, spec.system.solvent.model,
    )
    per_axis[ScoreAxis.ENSEMBLE] = _score_str(
        expected.ensemble,
        production.ensemble if production else None,
    )
    per_axis[ScoreAxis.DT_FS] = _score_num(
        expected.dt_fs,
        production.dt_fs if production else None,
    )
    per_axis[ScoreAxis.TEMPERATURE_K] = _score_num(
        expected.temperature_K,
        production.temperature_K if production else None,
    )
    per_axis[ScoreAxis.DURATION_NS] = _score_num(
        expected.duration_ns,
        production.duration_ns if production else None,
    )
    per_axis[ScoreAxis.PRESSURE_BAR] = _score_num(
        expected.pressure_bar,
        production.pressure_bar if production else None,
    )
    per_axis[ScoreAxis.FEP_LAMBDA_COUNT] = _score_num(
        expected.fep_lambda_count,
        len(fep.lambda_windows) if fep else None,
    )

    total = sum(1 for v in per_axis.values() if v is True)
    max_score = sum(1 for v in per_axis.values() if v is not None)

    if production is None:
        notes.append("no DynamicsStage in spec — production-stage axes scored 0")
    if expected.fep_lambda_count and not fep:
        notes.append("expected an FEP stage; spec has none — fep_lambda_count scored 0")

    return ScoreResult(
        paper_id=entry.paper_id,
        per_axis=per_axis,
        total=total,
        max_score=max_score,
        notes=notes,
    )


# -----------------------------------------------------------------------------
# Helpers — return None when the axis isn't scored, True/False otherwise.

def _score_str(expected: Optional[str], actual: Optional[str]) -> Optional[bool]:
    if expected is None:
        return None
    if actual is None:
        return False
    return expected.lower() == actual.lower()


def _score_num(expected: Optional[float], actual: Optional[float]) -> Optional[bool]:
    if expected is None:
        return None
    if actual is None:
        return False
    return math.isclose(float(expected), float(actual), rel_tol=1e-6, abs_tol=1e-9)
