"""`python -m crucible` — minimal Python CLI.

Pure-Python operations only (validate, lint, coverage, templates, migrate).
Heavy lifting (render, run) goes through `crucible-bin` via the Julia CLI;
use `crucible <subcommand>` directly for those.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import (
    MDSpec,
    SCHEMA_VERSION,
    coverage_score,
    lint,
    migrate_json,
    provenance_coverage,
    templates,
)
from .validate import run_validation


def _read_input(path: str | None) -> str:
    if path is None or path == "-":
        return sys.stdin.read()
    return Path(path).read_text()


def _cmd_validate(args: argparse.Namespace) -> int:
    text = _read_input(args.spec)
    try:
        spec = MDSpec.from_json(text)
    except Exception as exc:
        print(f"validate: could not parse spec: {exc}", file=sys.stderr)
        return 2
    report = run_validation(spec, spec_json=text)
    if args.format == "json":
        print(json.dumps({
            "ok": report.ok,
            "errors": report.errors,
            "warnings": report.warnings,
        }, indent=2))
    else:
        print(f"ok={report.ok}")
        for e in report.errors:
            print(f"  ERROR: {e}")
        for w in report.warnings:
            print(f"  WARN:  {w}")
    return 0 if report.ok else 1


def _cmd_lint(args: argparse.Namespace) -> int:
    spec = MDSpec.from_json(_read_input(args.spec))
    report = lint(spec)
    if args.format == "json":
        print(json.dumps({
            "findings": [{"severity": f.severity, "rule": f.rule,
                          "path": f.path, "message": f.message}
                         for f in report.findings],
            "coverage": {
                "total_numeric_fields": report.coverage.total_numeric_fields,
                "fields_with_provenance": report.coverage.fields_with_provenance,
                "by_source": report.coverage.by_source,
                "missing_paths": report.coverage.missing_paths,
                "score": coverage_score(report.coverage),
            },
        }, indent=2))
    else:
        for f in report.findings:
            print(f"  {f.severity.upper():9s} [{f.rule}] {f.path}: {f.message}")
        print(f"\ncoverage score: {coverage_score(report.coverage):.2f}")
    return 0


def _cmd_templates(args: argparse.Namespace) -> int:
    if args.action == "list":
        for name in templates.list_templates():
            print(name)
        return 0
    if args.action == "init":
        spec = templates.init(args.name)
        print(spec.to_json(indent=2))
        return 0
    return 2


def _cmd_migrate(args: argparse.Namespace) -> int:
    text = _read_input(args.spec)
    out = migrate_json(text, target=args.target)
    print(out)
    return 0


def _cmd_spec_describe(args: argparse.Namespace) -> int:
    """Pretty-print the IR's structure — quick reference for users
    writing custom adapters or hand-editing specs."""
    from . import spec as spec_mod
    sections: list[tuple[str, list[str]]] = []

    sections.append(("Schema version", [spec_mod.SCHEMA_VERSION]))
    sections.append(("Protein force fields (allowlist)",
                     list(spec_mod.PROTEIN_FF)))
    sections.append(("Water models (allowlist)", list(spec_mod.WATER_MODELS)))
    sections.append(("Ligand FFs (allowlist)", list(spec_mod.LIGAND_FF)))
    sections.append(("Lipid FFs (allowlist)", list(spec_mod.LIPID_FF)))
    sections.append(("Lipid bilayer compositions",
                     list(spec_mod.LIPID_COMPOSITION)))
    sections.append(("Coarse-grained protein FFs",
                     list(spec_mod.CG_PROTEIN_FF)))

    if args.format == "json":
        out = {title: items for title, items in sections}
        print(json.dumps(out, indent=2))
        return 0

    for title, items in sections:
        print(f"## {title}")
        for item in items:
            print(f"  - {item}")
        print()
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    # Passthrough subcommands: dispatch to their own argparse trees BEFORE the
    # outer argparse runs, otherwise argparse claims any `--flag` token as
    # outer-level and `nargs=REMAINDER` won't recover it. argparse.REMAINDER
    # is famously surprising about this.
    if argv and argv[0] == "corpus":
        from .corpus.cli import main as corpus_main
        return corpus_main(argv[1:])
    if argv and argv[0] == "benchmark":
        from .benchmark.cli import main as benchmark_main
        return benchmark_main(argv[1:])

    p = argparse.ArgumentParser(prog="crucible-py",
                                description="Crucible Python bindings — pure-Python ops")
    sub = p.add_subparsers(dest="cmd", required=True)

    pv = sub.add_parser("validate", help="run gates 1+2 against a spec JSON")
    pv.add_argument("spec", nargs="?", default="-",
                    help="path to JSON, or - for stdin (default)")
    pv.add_argument("--format", choices=["text", "json"], default="text")
    pv.set_defaults(func=_cmd_validate)

    pl = sub.add_parser("lint", help="lint + provenance coverage")
    pl.add_argument("spec", nargs="?", default="-")
    pl.add_argument("--format", choices=["text", "json"], default="text")
    pl.set_defaults(func=_cmd_lint)

    pt = sub.add_parser("templates", help="canned starter MDSpecs")
    pt.add_argument("action", choices=["list", "init"])
    pt.add_argument("name", nargs="?")
    pt.set_defaults(func=_cmd_templates)

    pm = sub.add_parser("migrate", help="migrate JSON across schema versions")
    pm.add_argument("spec", nargs="?", default="-")
    pm.add_argument("--target", default=SCHEMA_VERSION)
    pm.set_defaults(func=_cmd_migrate)

    psd = sub.add_parser("spec-describe",
                         help="print the IR's allowlists + schema version")
    psd.add_argument("--format", choices=["text", "json"], default="text")
    psd.set_defaults(func=_cmd_spec_describe)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
