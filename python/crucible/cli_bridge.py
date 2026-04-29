"""Subprocess bridge to the Julia CLI.

Pure-Python users get IR + validate + lint + templates natively (no Julia
required for those). Anything that touches a real backend — render, run,
serve, plot, events — shells out via `bin/crucible`. This is a deliberate
extension of `musings/why_subprocess_over_pythoncall.md`: the integration
boundary stays at the process layer in both directions.

Discovery order for the Julia CLI:
  1. `CRUCIBLE_BIN` env var
  2. `bin/crucible` next to the Python package (dev tree)
  3. `crucible` on PATH

Functions raise `CrucibleNotInstalled` if no binary is found, with a
remediation hint pointing at `julia --project -e 'using Pkg; Pkg.instantiate()'`.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional


class CrucibleNotInstalled(RuntimeError):
    """Raised when the Julia CLI binary cannot be located."""


class CrucibleSubprocessError(RuntimeError):
    """Raised when the Julia CLI exits non-zero."""


@dataclass
class SubprocessResult:
    returncode: int
    stdout: str
    stderr: str
    parsed: Optional[Any] = None        # populated when --format json is used


def find_crucible_bin() -> Path:
    """Locate the Julia CLI entrypoint. Order: env, dev tree, PATH."""
    env = os.environ.get("CRUCIBLE_BIN")
    if env:
        p = Path(env)
        if p.is_file() and os.access(p, os.X_OK):
            return p
        raise CrucibleNotInstalled(
            f"CRUCIBLE_BIN={env} is not an executable file"
        )
    here = Path(__file__).resolve().parent
    candidate = here.parent.parent / "bin" / "crucible"
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return candidate
    on_path = shutil.which("crucible")
    if on_path:
        return Path(on_path)
    raise CrucibleNotInstalled(
        "could not find the Crucible Julia CLI. Set $CRUCIBLE_BIN, run "
        "`julia --project -e 'using Pkg; Pkg.instantiate()'` from the "
        "Crucible repo root, or put `bin/crucible` on PATH."
    )


def _run(
    args: list[str],
    *,
    stdin: Optional[str] = None,
    parse_json: bool = False,
    cwd: Optional[Path] = None,
    env: Optional[dict[str, str]] = None,
    check: bool = True,
) -> SubprocessResult:
    binary = find_crucible_bin()
    cmd = [str(binary), *args]
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    proc = subprocess.run(
        cmd,
        input=stdin,
        capture_output=True,
        text=True,
        cwd=str(cwd) if cwd else None,
        env=full_env,
        check=False,
    )
    parsed: Optional[Any] = None
    if parse_json and proc.stdout.strip():
        try:
            parsed = json.loads(proc.stdout)
        except json.JSONDecodeError:
            parsed = None
    if check and proc.returncode != 0:
        raise CrucibleSubprocessError(
            f"crucible {' '.join(args)} exited {proc.returncode}\n"
            f"stderr: {proc.stderr.strip()}"
        )
    return SubprocessResult(
        returncode=proc.returncode,
        stdout=proc.stdout,
        stderr=proc.stderr,
        parsed=parsed,
    )


# -----------------------------------------------------------------------------
# Render

def render(spec_json: str, *, backend: str = "openmm",
           out_path: Optional[Path] = None) -> str:
    """Render an MDSpec to a backend script via `crucible render`. Returns
    the script source as a string."""
    if backend not in ("openmm", "molly"):
        raise ValueError(f"backend must be 'openmm' or 'molly', got {backend!r}")
    args = ["render", "--backend", backend, "--stdin"]
    if out_path is not None:
        args.extend(["--out", str(out_path)])
    res = _run(args, stdin=spec_json)
    if out_path is not None:
        return out_path.read_text()
    return res.stdout


# -----------------------------------------------------------------------------
# Run

@dataclass
class RunResult:
    workdir: Path
    returncode: int
    stdout: str
    stderr: str


def run(spec_json: str, *, workdir: Path, backend: str = "openmm",
        seed: Optional[int] = None,
        precision: Optional[str] = None,
        checkpoint_period_ps: Optional[float] = None,
        resume_from: Optional[Path] = None,
        extra_args: Optional[list[str]] = None) -> RunResult:
    """Execute the spec end-to-end via `crucible run`. Wraps the same env vars
    the Julia CLI honors (CRUCIBLE_SEED, CRUCIBLE_PRECISION, etc.).
    """
    workdir.mkdir(parents=True, exist_ok=True)
    args = ["run", "--backend", backend, "--workdir", str(workdir), "--stdin"]
    if extra_args:
        args.extend(extra_args)
    env: dict[str, str] = {}
    if seed is not None:
        env["CRUCIBLE_SEED"] = str(seed)
    if precision is not None:
        env["CRUCIBLE_PRECISION"] = precision
    if checkpoint_period_ps is not None:
        env["CRUCIBLE_CHECKPOINT_PERIOD_PS"] = str(checkpoint_period_ps)
    if resume_from is not None:
        env["CRUCIBLE_RESUME_FROM"] = str(resume_from)
    res = _run(args, stdin=spec_json, env=env, check=False)
    return RunResult(
        workdir=workdir,
        returncode=res.returncode,
        stdout=res.stdout,
        stderr=res.stderr,
    )


# -----------------------------------------------------------------------------
# Other CLI passthroughs (each is a thin convenience wrapper)

def health(spec_json: str) -> dict:
    """Run gates 1-3 + lint + coverage via the Julia CLI; returns the JSON
    health report. Use this when you want gate 3 (loadability) which the
    pure-Python validator can't run.
    """
    res = _run(["health", "--stdin", "--format", "json"],
               stdin=spec_json, parse_json=True)
    return res.parsed or {}


def lint_via_cli(spec_json: str) -> dict:
    res = _run(["lint", "--stdin", "--format", "json"],
               stdin=spec_json, parse_json=True)
    return res.parsed or {}


def coverage_via_cli(spec_json: str) -> dict:
    res = _run(["coverage", "--stdin", "--format", "json"],
               stdin=spec_json, parse_json=True)
    return res.parsed or {}


def diff(left_json: str, right_json: str, *,
         intent: bool = False) -> dict:
    args = ["diff", "--left-stdin", "--right-stdin", "--format", "json"]
    if intent:
        args.append("--intent")
    # crucible diff with two stdin streams uses NUL delimiter
    payload = left_json + "\0" + right_json
    res = _run(args, stdin=payload, parse_json=True)
    return res.parsed or {}


def events(workdir: Path, *, format: str = "json") -> Any:
    args = ["events", "--workdir", str(workdir), "--format", format]
    res = _run(args, parse_json=(format == "json"))
    return res.parsed if format == "json" else res.stdout


def doctor() -> str:
    """Run `crucible doctor` to check the install. Returns stdout."""
    return _run(["doctor"], check=False).stdout


def info() -> dict:
    """Allowlists + version + supported features."""
    res = _run(["info", "--format", "json"], parse_json=True)
    return res.parsed or {}
