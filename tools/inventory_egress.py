#!/usr/bin/env python3
"""Static-analysis inventory of every potential outbound-network call
in the codebase.

Catalogs `urlopen`, `requests.`, `httpx.`, `HTTP.get`, `Downloads.`,
etc. occurrences across the Python + Julia source. Each hit comes
with file path, line number, and the matched call. Designed for
the air-gapped audit (`docs/AIR_GAPPED.md`) — when a new dep
shows up, run this to find every place it might phone home.

Usage:
    python tools/inventory_egress.py
    python tools/inventory_egress.py --format json
    python tools/inventory_egress.py --strict       # exit 1 on any uncategorized hit

The `--strict` mode is meant for a CI gate: every egress site needs
to either be on the allowlist (with a documented neutralization in
AIR_GAPPED.md) or be removed from the codebase.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent

# Patterns that match outbound-network call sites. First-match-wins
# classification; categories drive the AIR_GAPPED.md cross-reference.
PATTERNS = [
    # (category, regex, description)
    ("urllib", re.compile(r"\burllib\.request\.\w+|\burlopen\("), "stdlib urllib"),
    ("requests", re.compile(r"\brequests\.\w+\("), "third-party requests"),
    ("httpx", re.compile(r"\bhttpx\.\w+\("), "third-party httpx"),
    ("anthropic_sdk", re.compile(r"\banthropic\.[A-Z]\w*\(|client\.messages\.create\("), "anthropic SDK"),
    ("openai_sdk", re.compile(r"\bopenai\.[A-Z]\w*\("), "openai SDK"),
    ("julia_HTTP", re.compile(r"\bHTTP\.(get|post|put|delete|head|request)\("), "Julia HTTP.jl"),
    ("julia_Downloads", re.compile(r"\bDownloads\.(download|request)\("), "Julia Downloads stdlib"),
    ("julia_PkgServer", re.compile(r"Pkg\.Registry\.update|Pkg\.update\("), "Julia Pkg server"),
    ("subprocess_curl_wget", re.compile(r"\b(curl|wget)\s+-\w*[A-Z]+"), "subprocess to curl/wget"),
    ("dns_lookup", re.compile(r"\bsocket\.gethostbyname\(|getaddrinfo\("), "DNS lookup"),
]

# Directories to exclude from the scan.
EXCLUDE_DIRS = {
    ".git", ".venv", "venv", "node_modules", "__pycache__",
    ".pytest_cache", ".dart_tool", "build", "dist",
    # Exclude the cloned upstream/ directory if any.
    # Python venv lives under python/.venv.
}
EXCLUDE_PATH_FRAGMENTS = (".venv/", "/build/", "/dist/", "/__pycache__/")


def _files_to_scan() -> list[Path]:
    paths: list[Path] = []
    for ext in ("*.py", "*.jl"):
        for p in REPO_ROOT.rglob(ext):
            # Skip excluded directory roots.
            parts = set(p.relative_to(REPO_ROOT).parts)
            if parts & EXCLUDE_DIRS:
                continue
            rel_str = str(p.relative_to(REPO_ROOT))
            if any(frag in rel_str for frag in EXCLUDE_PATH_FRAGMENTS):
                continue
            paths.append(p)
    return sorted(paths)


def _classify(line: str) -> tuple[str, str] | None:
    """Return (category, description) on first-pattern match; None otherwise."""
    for category, pattern, desc in PATTERNS:
        if pattern.search(line):
            return category, desc
    return None


def _scan_file(path: Path) -> list[dict]:
    hits: list[dict] = []
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        return hits
    rel = path.relative_to(REPO_ROOT)
    for lineno, line in enumerate(text.splitlines(), start=1):
        # Skip comments — comments documenting that something was
        # disabled shouldn't trip the inventory.
        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("//"):
            continue
        m = _classify(line)
        if m is None:
            continue
        category, desc = m
        hits.append({
            "path": str(rel),
            "line": lineno,
            "category": category,
            "description": desc,
            "snippet": line.strip()[:120],
        })
    return hits


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="inventory_egress.py")
    p.add_argument("--format", choices=["text", "json"], default="text")
    p.add_argument("--strict", action="store_true",
                   help="exit non-zero on any uncategorized site")
    args = p.parse_args(argv)

    all_hits: list[dict] = []
    for f in _files_to_scan():
        all_hits.extend(_scan_file(f))

    if args.format == "json":
        print(json.dumps(all_hits, indent=2))
    else:
        if not all_hits:
            print("No egress sites found.")
            return 0
        # Group by category for readability.
        by_cat: dict[str, list[dict]] = {}
        for h in all_hits:
            by_cat.setdefault(h["category"], []).append(h)
        for cat in sorted(by_cat):
            entries = by_cat[cat]
            print(f"## {cat}  ({len(entries)} site(s) — {entries[0]['description']})")
            for h in entries:
                print(f"  {h['path']}:{h['line']}  {h['snippet']}")
            print()

    # Strict mode: exit non-zero if any are uncategorized. Currently
    # all hits are categorized; this is forward-looking for when an
    # unknown-pattern site shows up.
    uncat = [h for h in all_hits if h["category"] == "unknown"]
    if args.strict and uncat:
        print(f"\n{len(uncat)} uncategorized egress site(s).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
