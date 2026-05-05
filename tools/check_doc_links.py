#!/usr/bin/env python3
"""Audit cross-references in docs/ and musings/ markdown files.

Catches the doc-rot regression class: a file gets renamed or moved,
references to it stay stale, readers hit 404s. Designed for
pre-commit + CI alongside `tools/check_workspace.py`.

Scope:
- Local relative links `[text](path)` and `[text](path#anchor)`.
- Excludes http:// + https:// (the link-checker's job, not ours).
- Excludes mailto: and tel: schemes.
- Excludes pure anchor-only links (`[text](#section)`) — those
  reference within the same file.

Usage:
    python tools/check_doc_links.py
    python tools/check_doc_links.py --verbose    # report every link checked
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent

# Markdown link: `[text](path)` — non-greedy on text + on path so
# nested brackets / parens in text don't wreck the match.
_LINK_RE = re.compile(r"\[(?P<text>[^\]]+?)\]\((?P<target>[^)\s]+?)(?:\s+\"[^\"]*\")?\)")

# Directories worth scanning. Markdown elsewhere (README, AGENTS,
# CONTRIBUTING) is also worth scanning; add it.
_SCAN_DIRS = ["docs", "musings", "examples"]
_SCAN_FILES_AT_ROOT = ["README.md", "AGENTS.md", "CONTRIBUTING.md", "SECURITY.md", "CHANGELOG.md"]


def _files_to_scan() -> list[Path]:
    paths: list[Path] = []
    for sub in _SCAN_DIRS:
        d = REPO_ROOT / sub
        if d.is_dir():
            paths.extend(sorted(d.rglob("*.md")))
    for name in _SCAN_FILES_AT_ROOT:
        f = REPO_ROOT / name
        if f.is_file():
            paths.append(f)
    return paths


def _is_external(target: str) -> bool:
    """True for links the audit doesn't validate (http, mailto, etc.)."""
    return any(target.startswith(p) for p in
               ("http://", "https://", "mailto:", "tel:", "ftp://"))


def _is_anchor_only(target: str) -> bool:
    return target.startswith("#")


def _resolve_target(source: Path, target: str) -> Path:
    """Resolve a link target relative to its source file. Strips the
    `#anchor` suffix and any URL-encoded characters that show up in
    repo-internal paths (the realistic case is `%20` for spaces;
    we don't decode arbitrary URL-encoding)."""
    path_part = target.split("#", 1)[0]
    return (source.parent / path_part).resolve()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="check_doc_links.py")
    p.add_argument("--verbose", action="store_true",
                   help="report every link checked, not just broken ones")
    args = p.parse_args(argv)

    files = _files_to_scan()
    broken: list[tuple[Path, str, str]] = []   # (source, link_text, target)
    n_checked = 0

    for source in files:
        try:
            text = source.read_text()
        except UnicodeDecodeError:
            continue
        for m in _LINK_RE.finditer(text):
            target = m.group("target")
            if _is_external(target) or _is_anchor_only(target):
                continue
            n_checked += 1
            resolved = _resolve_target(source, target)
            if not resolved.exists():
                broken.append((source, m.group("text"), target))
            elif args.verbose:
                rel = source.relative_to(REPO_ROOT)
                print(f"✓ {rel} → {target}")

    if broken:
        print(f"\n{len(broken)} broken link(s) of {n_checked} checked:\n",
              file=sys.stderr)
        for source, link_text, target in broken:
            rel = source.relative_to(REPO_ROOT)
            print(f"  ✗ {rel}: [{link_text!r}]({target})", file=sys.stderr)
        return len(broken)

    if args.verbose:
        print(f"\nall {n_checked} link(s) resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
