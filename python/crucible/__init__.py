"""Crucible — Python bindings.

Pure-Python IR + validation + lint + templates. Anything that touches a
real backend (render, run, serve) is delegated to the Julia CLI via
`crucible.cli_bridge`.

Public API:

    import crucible
    spec = crucible.templates.init("kinase_inhibitor_fep")
    spec.system.source.ligand_smiles = "Cc1ccc(NC(=O)c2cccnc2)cc1"
    report = crucible.validate(spec)        # gates 1+2 (no Julia required)
    health = crucible.health(spec)          # gates 1-3 + lint + coverage (Julia)
    script = crucible.render(spec, "openmm")  # via Julia CLI
    crucible.run(spec, workdir="runs/exp1", seed=42, precision="mixed")
    events = crucible.events("runs/exp1")
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional, Union

from . import cli_bridge, coverage, migrate, templates, validate
from .coverage import (
    CoverageReport,
    LintFinding,
    LintReport,
    coverage_score,
    lint,
    provenance_coverage,
)
from .migrate import migrate as migrate_json
from .spec import (
    SCHEMA_VERSION,
    CollectiveVariable,
    DynamicsStage,
    FEPStage,
    ForceFieldSpec,
    LipidBilayer,
    MDSpec,
    MetadynamicsStage,
    MinimizeStage,
    Observable,
    Provenance,
    ProtonationSpec,
    REMDStage,
    RestraintSpec,
    SolventSpec,
    SystemSource,
    SystemSpec,
    required_features,
)
from .validate import ValidationReport, gate_schema, gate_semantic, run_validation

__version__ = "0.3.0"
__all__ = [
    "MDSpec",
    "SystemSpec", "SystemSource", "SolventSpec", "LipidBilayer", "ProtonationSpec",
    "ForceFieldSpec", "RestraintSpec",
    "MinimizeStage", "DynamicsStage", "FEPStage", "REMDStage",
    "MetadynamicsStage", "CollectiveVariable",
    "Observable", "Provenance",
    "ValidationReport", "CoverageReport", "LintReport", "LintFinding",
    "templates", "validate", "lint", "provenance_coverage", "coverage_score",
    "migrate_json", "required_features",
    "render", "run", "health", "events", "doctor", "diff", "info",
    "SCHEMA_VERSION", "__version__",
]


# -----------------------------------------------------------------------------
# Top-level convenience wrappers — `crucible.validate(spec)` etc.

def _validate(spec: Union[MDSpec, str]) -> ValidationReport:
    """Run gates 1+2 in pure Python. No Julia required."""
    if isinstance(spec, str):
        json_text = spec
        try:
            spec_obj = MDSpec.from_json(spec)
        except Exception as exc:
            r = ValidationReport()
            r.add_error(f"could not parse spec JSON: {exc}")
            return r
        return run_validation(spec_obj, spec_json=json_text)
    return run_validation(spec)


# Re-export validate as both module and callable
class _ValidateCallable:
    __call__ = staticmethod(_validate)
    gate_schema = staticmethod(gate_schema)
    gate_semantic = staticmethod(gate_semantic)
    run_validation = staticmethod(run_validation)


validate = _ValidateCallable()  # type: ignore[assignment]


def render(spec: Union[MDSpec, str], backend: str = "openmm",
           *, out_path: Optional[Path] = None) -> str:
    """Render an MDSpec to a backend script via the Julia CLI."""
    json_text = spec.to_json() if isinstance(spec, MDSpec) else spec
    return cli_bridge.render(json_text, backend=backend, out_path=out_path)


def run(spec: Union[MDSpec, str], *, workdir: Union[str, Path],
        backend: str = "openmm", **kwargs) -> cli_bridge.RunResult:
    """Run the spec end-to-end via the Julia CLI."""
    json_text = spec.to_json() if isinstance(spec, MDSpec) else spec
    return cli_bridge.run(json_text, workdir=Path(workdir),
                          backend=backend, **kwargs)


def health(spec: Union[MDSpec, str]) -> dict:
    """Full health report via the Julia CLI (gates 1-3 + lint + coverage)."""
    json_text = spec.to_json() if isinstance(spec, MDSpec) else spec
    return cli_bridge.health(json_text)


def events(workdir: Union[str, Path], *, format: str = "json"):
    return cli_bridge.events(Path(workdir), format=format)


def doctor() -> str:
    return cli_bridge.doctor()


def diff(left: Union[MDSpec, str], right: Union[MDSpec, str],
         *, intent: bool = False) -> dict:
    left_json = left.to_json() if isinstance(left, MDSpec) else left
    right_json = right.to_json() if isinstance(right, MDSpec) else right
    return cli_bridge.diff(left_json, right_json, intent=intent)


def info() -> dict:
    return cli_bridge.info()
