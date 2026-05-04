"""Subcommand dispatch for `python -m crucible benchmark …`.

Subcommands:
  list       — show seed-set entries (verified vs needs_verification)
  run        — run an iterable of entries through a transpile callback
  report     — render the markdown report from a run-results JSONL
  status     — verification progress (e.g. "3 of 5 verified")
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from .papers import list_entries, load_seed_set
from .reporter import render_report
from .runner import RunOutcome
from .scorer import ScoreResult


def cmd_list(args: argparse.Namespace) -> int:
    entries = load_seed_set(verified_only=args.verified_only)
    for e in entries:
        print(json.dumps({
            "paper_id": e.paper_id,
            "doi": e.doi,
            "title": e.title,
            "status": e.status,
            "verified_by": e.verified_by,
        }))
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    entries = list_entries()
    by_status: dict[str, int] = {}
    for e in entries:
        by_status[e.status] = by_status.get(e.status, 0) + 1
    print(json.dumps({
        "total": len(entries),
        "by_status": by_status,
        "verified_pct": by_status.get("verified", 0) / max(len(entries), 1),
    }, indent=2))
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    """Render a markdown report from a run-results JSONL file."""
    pairs = []
    by_id = {e.paper_id: e for e in list_entries()}
    with open(args.runs) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            entry = by_id.get(obj["paper_id"])
            if entry is None:
                print(f"warning: unknown paper_id {obj['paper_id']!r}; skipping",
                      file=sys.stderr)
                continue
            sr_obj = obj.get("score_result")
            sr = None
            if sr_obj:
                from .scorer import ScoreAxis
                sr = ScoreResult(
                    paper_id=sr_obj["paper_id"],
                    per_axis={ScoreAxis(k): v
                              for k, v in sr_obj["per_axis"].items()},
                    total=sr_obj["total"],
                    max_score=sr_obj["max_score"],
                    notes=sr_obj.get("notes", []),
                )
            outcome = RunOutcome(
                paper_id=obj["paper_id"],
                ok=obj["ok"],
                elapsed_s=obj["elapsed_s"],
                score_result=sr,
                error=obj.get("error"),
            )
            pairs.append((entry, outcome))
    md = render_report(pairs, intro=args.intro)
    if args.out:
        Path(args.out).write_text(md)
        print(f"wrote {args.out}", file=sys.stderr)
    else:
        print(md)
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    """Run the benchmark via the Julia CLI transpile (or a mock for tests)."""
    from .runner import run as run_benchmark

    entries = load_seed_set(verified_only=args.verified_only)

    def paper_text_fn(entry):
        # MVP: read text from a sidecar file at args.papers_dir/<paper_id>.txt
        # if present; otherwise return the title (worst-case input). Enhance
        # by integrating with the corpus module when full-text fetch lands.
        if args.papers_dir:
            p = Path(args.papers_dir) / f"{entry.paper_id}.txt"
            if p.exists():
                return p.read_text()
        return entry.title

    if args.mock:
        # Identity transpile for smoke testing — returns a vanilla template.
        from ..templates import init as init_template
        def transpile_fn(_text):
            return init_template("vanilla")
    else:
        from ..cli_bridge import _run as cli_run
        from ..spec import MDSpec
        def transpile_fn(text):
            res = cli_run(["transpile", "--stdin", "--format", "json"], stdin=text)
            return MDSpec.from_json(res.stdout)

    out_path = Path(args.out) if args.out else None
    if out_path:
        out_path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[str] = []
    for outcome in run_benchmark(entries, paper_text_fn, transpile_fn,
                                 allow_unverified=args.allow_unverified):
        record = {
            "paper_id": outcome.paper_id,
            "ok": outcome.ok,
            "elapsed_s": outcome.elapsed_s,
            "error": outcome.error,
        }
        if outcome.score_result is not None:
            record["score_result"] = {
                "paper_id": outcome.score_result.paper_id,
                "per_axis": {k.value: v
                             for k, v in outcome.score_result.per_axis.items()},
                "total": outcome.score_result.total,
                "max_score": outcome.score_result.max_score,
                "notes": outcome.score_result.notes,
            }
        line = json.dumps(record)
        rows.append(line)
        if out_path is None:
            print(line)
    if out_path is not None:
        out_path.write_text("\n".join(rows) + "\n")
        print(f"wrote {len(rows)} outcomes → {out_path}", file=sys.stderr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="crucible-benchmark",
        description="Hallucination benchmark for the Crucible LLM transpile.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pl = sub.add_parser("list", help="list seed-set entries (JSONL)")
    pl.add_argument("--verified-only", action="store_true")
    pl.set_defaults(func=cmd_list)

    pst = sub.add_parser("status", help="verification progress")
    pst.set_defaults(func=cmd_status)

    pr = sub.add_parser("run", help="run the transpile against the seed set")
    pr.add_argument("--mock", action="store_true",
                    help="use a deterministic mock transpile (smoke test)")
    pr.add_argument("--papers-dir", default=None,
                    help="dir containing <paper_id>.txt sidecar files")
    pr.add_argument("--out", default=None, help="output JSONL path")
    pr.add_argument("--verified-only", action="store_true")
    pr.add_argument("--allow-unverified", action="store_true",
                    help="score unverified entries (dry-run measurement)")
    pr.set_defaults(func=cmd_run)

    pp = sub.add_parser("report", help="render markdown report from a runs JSONL")
    pp.add_argument("runs", help="path to JSONL produced by `benchmark run`")
    pp.add_argument("--out", default=None, help="output .md path (default: stdout)")
    pp.add_argument("--intro", default=None, help="optional intro paragraph")
    pp.set_defaults(func=cmd_report)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
