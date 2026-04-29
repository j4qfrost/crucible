"""Provenance coverage + lint — Python port of `src/spec/Coverage.jl`.

`provenance_coverage(spec)` is the metric.
`lint(spec)` is the advisory layer beyond Gates 1-3.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .spec import (
    DynamicsStage,
    FEPStage,
    MDSpec,
    MetadynamicsStage,
    MinimizeStage,
    REMDStage,
)


@dataclass
class CoverageReport:
    total_numeric_fields: int = 0
    fields_with_provenance: int = 0
    by_source: dict[str, int] = field(default_factory=dict)
    missing_paths: list[str] = field(default_factory=list)


def provenance_coverage(spec: MDSpec) -> CoverageReport:
    paths = _enumerate_provenance_keys(spec)
    by_source: dict[str, int] = {}
    missing: list[str] = []
    n_with = 0
    for p in paths:
        if p in spec.provenance:
            n_with += 1
            src = spec.provenance[p].source
            by_source[src] = by_source.get(src, 0) + 1
        else:
            missing.append(p)
    return CoverageReport(
        total_numeric_fields=len(paths),
        fields_with_provenance=n_with,
        by_source=by_source,
        missing_paths=missing,
    )


def _enumerate_provenance_keys(spec: MDSpec) -> list[str]:
    keys: list[str] = []
    keys.append("system.n_atoms_estimate")
    keys.append("system.solvent.ions_NaCl_mM")
    if spec.system.solvent.membrane is not None:
        keys.append("system.solvent.membrane.n_lipids")
        keys.append("system.solvent.membrane.chol_mol_fraction")
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, MinimizeStage):
            keys.append(f"protocol[{i}].max_iterations")
            keys.append(f"protocol[{i}].tolerance_kj_mol_nm")
        elif isinstance(s, DynamicsStage):
            keys.append(f"protocol[{i}].duration_ns")
            keys.append(f"protocol[{i}].dt_fs")
            keys.append(f"protocol[{i}].temperature_K")
            keys.append(f"protocol[{i}].friction_ps")
            if s.pressure_bar is not None:
                keys.append(f"protocol[{i}].pressure_bar")
            if s.restraints.selection != "none":
                keys.append(f"protocol[{i}].restraints.k_kj_mol_nm2")
        elif isinstance(s, FEPStage):
            keys.append(f"protocol[{i}].lambda_windows")
            keys.append(f"protocol[{i}].duration_per_window_ns")
            keys.append(f"protocol[{i}].temperature_K")
            keys.append(f"protocol[{i}].dt_fs")
        elif isinstance(s, REMDStage):
            keys.append(f"protocol[{i}].temperature_ladder_K")
            keys.append(f"protocol[{i}].duration_per_replica_ns")
            keys.append(f"protocol[{i}].exchange_attempt_period_ps")
        elif isinstance(s, MetadynamicsStage):
            keys.append(f"protocol[{i}].bias_height_kj_mol")
            keys.append(f"protocol[{i}].bias_deposit_period_ps")
            keys.append(f"protocol[{i}].duration_ns")
            keys.append(f"protocol[{i}].temperature_K")
            keys.append(f"protocol[{i}].bias_factor")
            for j in range(1, len(s.cvs) + 1):
                keys.append(f"protocol[{i}].cvs[{j}].sigma")
    for k in range(1, len(spec.observables) + 1):
        keys.append(f"observables[{k}].stride_ps")
    return keys


def coverage_score(report: CoverageReport) -> float:
    if report.total_numeric_fields == 0:
        return 0.0
    weights = {
        "paper": 1.0,
        "paper_default": 0.7,
        "user": 1.0,
        "assumed": 0.4,
        "runtime_default": 0.2,
    }
    s = 0.0
    for src, n in report.by_source.items():
        s += n * weights.get(src, 0.0)
    return s / report.total_numeric_fields


# -----------------------------------------------------------------------------
# Lint

@dataclass
class LintFinding:
    severity: str            # "info" | "warn" | "advisory"
    rule: str                # rule identifier
    path: str                # JSONPath-ish key the finding applies to
    message: str


@dataclass
class LintReport:
    findings: list[LintFinding] = field(default_factory=list)
    coverage: CoverageReport = field(default_factory=CoverageReport)

    def __bool__(self) -> bool:
        return bool(self.findings)


def lint(spec: MDSpec) -> LintReport:
    cov = provenance_coverage(spec)
    report = LintReport(coverage=cov)

    def _record(severity: str, rule: str, path: str, msg: str) -> None:
        report.findings.append(LintFinding(severity, rule, path, msg))

    # Production-shape rules
    seen_eq = False
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, DynamicsStage):
            if s.role == "equilibrate":
                seen_eq = True
            elif s.role == "production":
                if not seen_eq:
                    _record(
                        "warn", "no_equilibration", f"protocol[{i}]",
                        "production stage with no preceding equilibrate stage; "
                        "results may be biased by initial conditions",
                    )
                if s.duration_ns < 1.0:
                    _record(
                        "advisory", "short_production",
                        f"protocol[{i}].duration_ns",
                        f"production duration {s.duration_ns} ns is very short; "
                        f"consider ≥1 ns for any non-toy result",
                    )

    # Observable-shape rules
    has_traj = any(o.type == "trajectory" for o in spec.observables)
    needs_traj = any(o.type in ("rmsd", "rmsf", "rg") for o in spec.observables)
    if needs_traj and not has_traj:
        _record(
            "warn", "rmsd_no_trajectory", "observables",
            "computing rmsd / rmsf / rg requires a :trajectory observable; "
            "post-run mdtraj analysis will skip without one",
        )
    total_dur = sum(s.duration_ns for s in spec.protocol if isinstance(s, DynamicsStage))
    for k, o in enumerate(spec.observables, start=1):
        if o.type == "trajectory" and o.stride_ps * 1e-3 > total_dur / 10:
            _record(
                "advisory", "trajectory_observable_no_stride",
                f"observables[{k}].stride_ps",
                f"trajectory stride {o.stride_ps} ps writes <10 frames over the "
                f"{round(total_dur, 2)} ns total run; consider a smaller stride",
            )

    # FEP / REMD / metad shape
    for i, s in enumerate(spec.protocol, start=1):
        if isinstance(s, FEPStage):
            if len(s.lambda_windows) < 5:
                _record(
                    "advisory", "fep_few_windows",
                    f"protocol[{i}].lambda_windows",
                    f"FEP with {len(s.lambda_windows)} λ windows; ≥11 is typical "
                    f"for binding ΔG",
                )
            if s.duration_per_window_ns < 0.1:
                _record(
                    "advisory", "fep_short_window",
                    f"protocol[{i}].duration_per_window_ns",
                    f"FEP per-window {s.duration_per_window_ns} ns; ≥0.5 ns "
                    f"recommended for convergence",
                )
        elif isinstance(s, REMDStage):
            if len(s.temperature_ladder_K) < 4:
                _record(
                    "advisory", "remd_few_replicas",
                    f"protocol[{i}].temperature_ladder_K",
                    f"REMD with {len(s.temperature_ladder_K)} replicas; ≥4 typically "
                    f"needed for useful exchange statistics",
                )
        elif isinstance(s, MetadynamicsStage):
            if not s.well_tempered:
                _record(
                    "advisory", "metad_no_well_tempered",
                    f"protocol[{i}].well_tempered",
                    "non-well-tempered metadynamics; well-tempered (γ>1) is the "
                    "modern default for convergence",
                )

    # Provenance coverage
    if cov.total_numeric_fields > 0:
        score = coverage_score(cov)
        if score < 0.5:
            _record(
                "warn", "provenance_low", "provenance",
                f"provenance score {round(score, 2)} (< 0.5); "
                f"{len(cov.missing_paths)} of {cov.total_numeric_fields} numeric "
                f"fields lack a provenance entry",
            )
        n_assumed = cov.by_source.get("assumed", 0)
        if cov.fields_with_provenance > 0 and n_assumed / cov.fields_with_provenance > 0.5:
            _record(
                "advisory", "assumed_dominates", "provenance",
                f"{n_assumed} of {cov.fields_with_provenance} provenance entries "
                f"are :assumed; consider re-extracting with a stronger LLM or "
                f"stricter prompt",
            )

    return report
