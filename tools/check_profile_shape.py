#!/usr/bin/env python3
"""Audit `USER_PROFILE_*.md` files for the v1.59 playbook shape.

Per `docs/ADOPTION_STRATEGY_PLAYBOOK.md`, every profile doc has six
required pieces, in order:

    1. One-paragraph hook         (top blockquote starting "You leave with")
    2. Pre-flight                 (## Pre-flight ... section)
    3. The 30-minute path         (## The 30-minute path ... OR similar)
    4. The first-week path        (## The first-week path ... OR a longer
                                   variant — "The 30-day path" for the pharma
                                   POC; "A 1-week course module" for instructor)
    5. Failure modes              (## Failure modes specific to this profile)
    6. When to read X next        (## When to read X next)

This auditor enforces the *presence* of each piece, not the content.
Catches the regression class where a new profile doc gets added but
skips the failure-modes section (turning the profile into a Tour, per
the playbook's anti-pattern list).

Usage:
    python tools/check_profile_shape.py
    python tools/check_profile_shape.py --verbose   # report passes too
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
PROFILES_DIR = REPO_ROOT / "docs"


# Each rule is (display_name, predicate). Predicates take the file
# text and return True if present. Multiple synonyms allowed for
# section names that vary in wording (the playbook tolerates "30-day
# path" for pharma POC and "1-week course module" for instructor).

def _has_hook(text: str) -> bool:
    """Top blockquote starting with 'You leave with' — the playbook's
    required-artifact framing."""
    return bool(re.search(
        r"^>\s*\*?\*?You leave with",
        text,
        flags=re.MULTILINE | re.IGNORECASE,
    ))


def _has_section(text: str, *prefixes: str) -> bool:
    for prefix in prefixes:
        pattern = r"^##\s+" + re.escape(prefix)
        if re.search(pattern, text, flags=re.MULTILINE | re.IGNORECASE):
            return True
    return False


REQUIRED = [
    ("hook (you-leave-with blockquote)", _has_hook),
    ("pre-flight", lambda t: _has_section(t, "Pre-flight")),
    ("30-minute path", lambda t: _has_section(t, "The 30-minute path",
                                              "The 30-day path",
                                              "The 30-minute smoke review")),
    ("first-week / multi-day path",
     lambda t: _has_section(t, "The first-week path",
                            "A 1-week course module",
                            "The deeper review",
                            "The 30-day path",
                            "The audit becomes a benchmark contribution")),
    ("failure modes", lambda t: _has_section(t, "Failure modes")),
    ("when to read X next", lambda t: _has_section(t, "When to read X next",
                                                   "When to read")),
]


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="check_profile_shape.py")
    p.add_argument("--verbose", action="store_true",
                   help="report sections present, not just missing")
    args = p.parse_args(argv)

    profiles = sorted(PROFILES_DIR.glob("USER_PROFILE_*.md"))
    if not profiles:
        print(f"no USER_PROFILE_*.md files under {PROFILES_DIR}",
              file=sys.stderr)
        return 0

    n_failed = 0
    for profile in profiles:
        text = profile.read_text()
        missing: list[str] = []
        for name, predicate in REQUIRED:
            if not predicate(text):
                missing.append(name)
        rel = profile.relative_to(REPO_ROOT)
        if missing:
            n_failed += 1
            print(f"✗ {rel}", file=sys.stderr)
            for m in missing:
                print(f"    missing: {m}", file=sys.stderr)
        elif args.verbose:
            print(f"✓ {rel} (all 6 sections present)")

    if n_failed and not args.verbose:
        print(f"\n{n_failed} profile(s) missing required sections "
              f"(see docs/ADOPTION_STRATEGY_PLAYBOOK.md for the shape).",
              file=sys.stderr)
    elif args.verbose:
        print(f"\nall {len(profiles)} profile(s) conform.")
    return n_failed


if __name__ == "__main__":
    sys.exit(main())
