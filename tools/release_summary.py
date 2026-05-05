#!/usr/bin/env python3
"""One-line-per-version summary of CHANGELOG.md.

The CHANGELOG has grown long enough (70+ versions, ~3000 lines at
this commit) that scanning for "what changed in v1.5x?" is friction.
This emits a compact view: one line per version with the headline
title, optionally filtered to a version prefix.

Usage:
    python tools/release_summary.py
    python tools/release_summary.py --prefix v1.4
    python tools/release_summary.py --since v1.50
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = REPO_ROOT / "CHANGELOG.md"

# `### v1.42 — corpus full-text fetch (PDF → pdftotext) (2026-05-04)`
_HEADER_RE = re.compile(
    r"^###\s+(?P<version>v\d+\.\d+(?:\.\d+)?)\s*—\s*(?P<title>.+?)\s*(?:\((?P<date>[^)]+)\))?\s*$",
    re.MULTILINE,
)


def _semver_tuple(version: str) -> tuple[int, ...]:
    """For sorting / comparison. v1.5 → (1, 5); v1.5.2 → (1, 5, 2)."""
    parts = version.lstrip("v").split(".")
    return tuple(int(p) for p in parts)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="release_summary.py")
    p.add_argument("--prefix", default=None,
                   help="filter to versions matching this prefix (e.g. v1.4)")
    p.add_argument("--since", default=None,
                   help="only versions >= this (e.g. v1.50)")
    p.add_argument("--latest", type=int, default=None,
                   help="show only the N most-recent versions")
    args = p.parse_args(argv)

    if not CHANGELOG.is_file():
        print(f"CHANGELOG not found at {CHANGELOG}", file=sys.stderr)
        return 1
    text = CHANGELOG.read_text()

    rows: list[tuple[str, str, str]] = []   # (version, title, date)
    for m in _HEADER_RE.finditer(text):
        rows.append((m.group("version"),
                     m.group("title"),
                     m.group("date") or ""))

    # Apply filters.
    if args.prefix:
        rows = [r for r in rows if r[0].startswith(args.prefix)]
    if args.since:
        try:
            cutoff = _semver_tuple(args.since)
            rows = [r for r in rows if _semver_tuple(r[0]) >= cutoff]
        except ValueError:
            print(f"--since must be vX.Y or vX.Y.Z; got {args.since!r}",
                  file=sys.stderr)
            return 2

    if args.latest:
        # Keep insertion order (newest-first in the file); take the first N.
        rows = rows[: args.latest]

    if not rows:
        print("(no versions match the filter)", file=sys.stderr)
        return 0

    # Format: `v1.42  2026-05-04  corpus full-text fetch (PDF → pdftotext)`
    max_version_w = max(len(r[0]) for r in rows)
    max_date_w = max(len(r[2]) for r in rows)
    for version, title, date in rows:
        # Strip backticks from titles for compact display.
        clean_title = title.replace("`", "")
        print(f"{version:<{max_version_w}}  {date:<{max_date_w}}  {clean_title}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
