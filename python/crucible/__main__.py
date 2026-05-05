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


def _cmd_doctor(args: argparse.Namespace) -> int:
    """Smoke-check the Python install + (optionally) the air-gapped
    configuration."""
    import importlib.metadata
    import os

    findings: list[tuple[str, str, str]] = []   # (level, name, detail)

    def add(level: str, name: str, detail: str) -> None:
        findings.append((level, name, detail))

    # Required deps.
    for pkg in ("pydantic", "jsonschema"):
        try:
            ver = importlib.metadata.version(pkg)
            add("ok", pkg, f"installed ({ver})")
        except importlib.metadata.PackageNotFoundError:
            add("error", pkg, "not installed (required base dep)")

    # Optional extras.
    for pkg, extra in (
        ("duckdb", "[corpus]"),
        ("streamlit", "[ui]"),
        ("anthropic", "[llm-anthropic]"),
    ):
        try:
            ver = importlib.metadata.version(pkg)
            add("info", pkg, f"installed ({ver}) — extra {extra}")
        except importlib.metadata.PackageNotFoundError:
            add("info", pkg, f"not installed — install {extra} if needed")

    # Schema sanity.
    add("ok", "schema_version", f"{SCHEMA_VERSION!r}")

    # Provider config.
    provider = os.environ.get("CRUCIBLE_PROVIDER", "")
    if provider:
        add("ok", "CRUCIBLE_PROVIDER", provider)
    else:
        add("info", "CRUCIBLE_PROVIDER",
            "unset — defaults vary by call site; set explicitly to pin")

    if args.offline:
        # Air-gapped mode: assert that no external-API config is active.
        anth_key = os.environ.get("ANTHROPIC_API_KEY")
        if anth_key:
            add("error", "ANTHROPIC_API_KEY",
                "is set — air-gapped mode forbids the Anthropic API. Unset it.")
        else:
            add("ok", "ANTHROPIC_API_KEY", "not set (correct for air-gapped)")

        oa_email = os.environ.get("CRUCIBLE_OPENALEX_EMAIL")
        if oa_email:
            add("warn", "CRUCIBLE_OPENALEX_EMAIL",
                f"is set ({oa_email!r}) — corpus fetch will hit OpenAlex. "
                "Disable corpus fetch in air-gapped mode.")
        else:
            add("ok", "CRUCIBLE_OPENALEX_EMAIL", "not set")

        local_ep = os.environ.get("CRUCIBLE_LOCAL_ENDPOINT")
        if not local_ep:
            add("warn", "CRUCIBLE_LOCAL_ENDPOINT",
                "not set — LocalOpenAIProvider will use the default "
                "http://localhost:8000/v1. Set explicitly in production.")
        else:
            # Pin to localhost / 127.0.0.1 / private nets only.
            ep_lower = local_ep.lower()
            is_local = any(seg in ep_lower for seg in
                           ("localhost", "127.0.0.1", "10.", "172.16.",
                            "172.17.", "172.18.", "172.19.", "172.2",
                            "172.30.", "172.31.", "192.168."))
            if is_local:
                add("ok", "CRUCIBLE_LOCAL_ENDPOINT",
                    f"{local_ep!r} (looks local — good)")
            else:
                add("warn", "CRUCIBLE_LOCAL_ENDPOINT",
                    f"{local_ep!r} doesn't look like a private-net URL. "
                    "Verify it's inside your air-gap.")

        hekate = os.environ.get("CRUCIBLE_HEKATE_PUBLISH_EVENTS", "0")
        if hekate == "1":
            add("error", "CRUCIBLE_HEKATE_PUBLISH_EVENTS",
                "set to 1 — AT Protocol publishing is enabled. Unset for air-gap.")
        else:
            add("ok", "CRUCIBLE_HEKATE_PUBLISH_EVENTS",
                "not enabled (default; correct for air-gapped)")

    # Render.
    n_error = sum(1 for level, _, _ in findings if level == "error")
    n_warn = sum(1 for level, _, _ in findings if level == "warn")
    if args.format == "json":
        print(json.dumps([
            {"level": level, "name": name, "detail": detail}
            for level, name, detail in findings
        ], indent=2))
    else:
        for level, name, detail in findings:
            mark = {"ok": "✓", "info": "ℹ", "warn": "⚠", "error": "✗"}[level]
            print(f"{mark} {name}: {detail}")
        print()
        if n_error:
            print(f"✗ {n_error} error(s); doctor failed.", file=sys.stderr)
        elif n_warn:
            print(f"⚠ {n_warn} warning(s).", file=sys.stderr)
        else:
            print("✓ all checks passed.", file=sys.stderr)
    return n_error    # exit 0 if no errors; warnings don't fail


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

    pdo = sub.add_parser("doctor",
                         help="smoke-check the install (+ --offline for air-gap audit)")
    pdo.add_argument("--offline", action="store_true",
                     help="verify config is air-gap-ready per docs/AIR_GAPPED.md")
    pdo.add_argument("--format", choices=["text", "json"], default="text")
    pdo.set_defaults(func=_cmd_doctor)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
