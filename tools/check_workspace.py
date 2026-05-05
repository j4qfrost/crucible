#!/usr/bin/env python3
"""Aggregate consistency checks for the workspace.

Bundles the cross-file invariants that v1.41–v1.55 introduced into a
single fail-fast script. Designed for pre-commit + CI + ad-hoc human
invocation.

Each check is independent + has a one-line failure message. Exit code
is the number of failed checks (so CI sees non-zero on any failure).

Checks:
    1. Python `SCHEMA_VERSION` matches `src/spec/schema.json` const
    2. Python `SCHEMA_VERSION` matches `src/spec/MDSpec.jl` keyword default
    3. Every test fixture under test/fixtures/*.json has a `schema_version`
       in {0.1.0, 0.2.0, 0.3.0, 0.4.0} (known versions; the migration
       chain handles all of them)
    4. `Manifest.toml` has `manifest_format = "2.0"` (Pkg.jl modern)
    5. `python/pyproject.toml` declares `pydantic>=2` (the pydantic-v1
       split was painful enough that pinning v2 is load-bearing)
    6. Doc cross-references resolve (delegated to `check_doc_links.py`)
    7. USER_PROFILE_*.md files match the v1.59 playbook shape
    8. Outbound-network call inventory has not exceeded the baseline
       in `tools/baselines/egress.json` (any new egress site forces
       a deliberate baseline bump + AIR_GAPPED.md update — air-gap audit gate)

Usage:
    python tools/check_workspace.py
    python tools/check_workspace.py --verbose   # report passed checks too
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent


def _check_python_schema_matches_json() -> tuple[bool, str]:
    sys.path.insert(0, str(REPO_ROOT / "python"))
    try:
        from crucible.spec import SCHEMA_VERSION
    except Exception as exc:
        return False, f"could not import crucible.spec: {exc}"
    schema = json.loads((REPO_ROOT / "src" / "spec" / "schema.json").read_text())
    canonical = schema["properties"]["schema_version"]["const"]
    if SCHEMA_VERSION != canonical:
        return False, (
            f"SCHEMA_VERSION ({SCHEMA_VERSION!r}) drifts from "
            f"src/spec/schema.json const ({canonical!r})"
        )
    return True, f"SCHEMA_VERSION ({SCHEMA_VERSION!r}) matches schema.json const"


def _check_python_schema_matches_julia() -> tuple[bool, str]:
    from crucible.spec import SCHEMA_VERSION
    text = (REPO_ROOT / "src" / "spec" / "MDSpec.jl").read_text()
    m = re.search(r'schema_version\s*=\s*"(\d+\.\d+\.\d+)"', text)
    if m is None:
        return False, "could not find schema_version=\"…\" in MDSpec.jl"
    julia_default = m.group(1)
    if SCHEMA_VERSION != julia_default:
        return False, (
            f"SCHEMA_VERSION ({SCHEMA_VERSION!r}) drifts from MDSpec.jl "
            f"default ({julia_default!r})"
        )
    return True, f"SCHEMA_VERSION matches MDSpec.jl default ({julia_default})"


_KNOWN_SCHEMA_VERSIONS = {"0.1.0", "0.2.0", "0.3.0", "0.4.0"}


def _check_fixtures_have_known_schema_version() -> tuple[bool, str]:
    fixtures_dir = REPO_ROOT / "test" / "fixtures"
    if not fixtures_dir.is_dir():
        return True, "no test/fixtures dir; skipped"
    bad: list[str] = []
    for fixture in fixtures_dir.glob("*.json"):
        try:
            obj = json.loads(fixture.read_text())
        except json.JSONDecodeError as exc:
            bad.append(f"{fixture.name}: invalid JSON ({exc})")
            continue
        if not isinstance(obj, dict):
            continue
        ver = obj.get("schema_version")
        if ver is None:
            continue   # not a spec fixture
        if ver not in _KNOWN_SCHEMA_VERSIONS:
            bad.append(f"{fixture.name}: schema_version={ver!r} unknown")
    if bad:
        return False, "fixture issues:\n  - " + "\n  - ".join(bad)
    return True, f"all spec fixtures use known schema versions"


def _check_manifest_format() -> tuple[bool, str]:
    path = REPO_ROOT / "Manifest.toml"
    if not path.is_file():
        return True, "no Manifest.toml; skipped"
    text = path.read_text()
    m = re.search(r'manifest_format\s*=\s*"([^"]+)"', text)
    if m is None:
        return False, "Manifest.toml: could not find manifest_format"
    fmt = m.group(1)
    if fmt != "2.0":
        return False, (
            f"Manifest.toml: manifest_format={fmt!r}; expected 2.0 "
            f"(Pkg modern). Regenerate with `julia --project -e 'using Pkg; Pkg.instantiate()'`."
        )
    return True, "Manifest.toml uses manifest_format 2.0"


def _check_pydantic_pinned_v2() -> tuple[bool, str]:
    path = REPO_ROOT / "python" / "pyproject.toml"
    if not path.is_file():
        return True, "no python/pyproject.toml; skipped"
    text = path.read_text()
    # pydantic>=2 or pydantic>=2.5 etc.
    if not re.search(r'"pydantic\s*>=\s*2', text):
        return False, "python/pyproject.toml: pydantic must be pinned >=2 (v1 split risk)"
    return True, "pydantic pinned to v2"


def _check_doc_links() -> tuple[bool, str]:
    import subprocess
    proc = subprocess.run(
        [sys.executable, str(REPO_ROOT / "tools" / "check_doc_links.py")],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        snippet = (proc.stderr or proc.stdout).strip().splitlines()
        head = "; ".join(snippet[:3])
        return False, f"check_doc_links.py reported {proc.returncode} broken link(s): {head}"
    return True, "all doc cross-references resolve"


def _check_profile_shape() -> tuple[bool, str]:
    import subprocess
    proc = subprocess.run(
        [sys.executable, str(REPO_ROOT / "tools" / "check_profile_shape.py")],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        snippet = (proc.stderr or proc.stdout).strip().splitlines()
        head = "; ".join(snippet[:3])
        return False, f"{proc.returncode} profile(s) missing playbook sections: {head}"
    return True, "all USER_PROFILE_*.md files match the v1.59 playbook shape"


def _check_egress_baseline() -> tuple[bool, str]:
    """Ensure no new outbound-network call site has crept in past the
    baseline in tools/baselines/egress.json. New sites force a
    deliberate baseline bump + an AIR_GAPPED.md update."""
    import subprocess
    baseline_path = REPO_ROOT / "tools" / "baselines" / "egress.json"
    if not baseline_path.is_file():
        return True, "no egress baseline; skipped"
    baseline = json.loads(baseline_path.read_text())
    expected = baseline.get("counts") or {}

    proc = subprocess.run(
        [sys.executable, str(REPO_ROOT / "tools" / "inventory_egress.py"),
         "--format", "json"],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return False, f"inventory_egress.py exited {proc.returncode}: {proc.stderr.strip()[:200]}"
    try:
        hits = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        return False, f"inventory_egress.py emitted invalid JSON: {exc}"

    actual: dict[str, int] = {}
    for h in hits:
        actual[h["category"]] = actual.get(h["category"], 0) + 1

    drift: list[str] = []
    for cat, n in actual.items():
        baseline_n = expected.get(cat, 0)
        if n > baseline_n:
            drift.append(f"{cat}: {n} > baseline {baseline_n}")
    if drift:
        return False, (
            "egress baseline exceeded:\n  - " + "\n  - ".join(drift)
            + "\n  bump tools/baselines/egress.json + update docs/AIR_GAPPED.md"
        )
    total = sum(actual.values())
    return True, f"egress inventory within baseline ({total} site(s) across {len(actual)} categor{'y' if len(actual)==1 else 'ies'})"


CHECKS = [
    ("python_schema_matches_json", _check_python_schema_matches_json),
    ("python_schema_matches_julia", _check_python_schema_matches_julia),
    ("fixtures_have_known_schema_version", _check_fixtures_have_known_schema_version),
    ("manifest_format", _check_manifest_format),
    ("pydantic_pinned_v2", _check_pydantic_pinned_v2),
    ("doc_links", _check_doc_links),
    ("profile_shape", _check_profile_shape),
    ("egress_baseline", _check_egress_baseline),
]


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="check_workspace.py")
    p.add_argument("--verbose", action="store_true",
                   help="report passing checks too")
    args = p.parse_args(argv)

    n_failed = 0
    for name, check in CHECKS:
        try:
            ok, msg = check()
        except Exception as exc:
            ok, msg = False, f"check raised {type(exc).__name__}: {exc}"
        marker = "✓" if ok else "✗"
        if not ok or args.verbose:
            print(f"{marker} {name}: {msg}")
        if not ok:
            n_failed += 1

    if n_failed:
        print(f"\n{n_failed} check(s) failed.", file=sys.stderr)
    elif args.verbose:
        print(f"\nall {len(CHECKS)} check(s) passed.")
    return n_failed


if __name__ == "__main__":
    sys.exit(main())
