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


def cmd_add(args: argparse.Namespace) -> int:
    """Append a `needs_verification` stub to papers.py.

    Exists to lower the friction of adding a new benchmark entry —
    rather than editing Python, the user runs one command and then
    walks through `docs/HOW_TO_VERIFY_A_PAPER.md` to populate the
    fields. The stub's ExpectedProtocol fields are all None until
    a human reads the source.
    """
    if args.paper_id in {e.paper_id for e in list_entries()}:
        print(f"paper_id {args.paper_id!r} already in seed set", file=sys.stderr)
        return 1
    papers_path = Path(__file__).resolve().parent / "papers.py"
    text = papers_path.read_text()
    sentinel = "]\n\n\ndef list_entries"
    if sentinel not in text:
        print(f"could not locate seed-set sentinel in {papers_path} — papers.py "
              f"layout has drifted from the expected shape; add the entry by "
              f"hand and update this CLI",
              file=sys.stderr)
        return 2
    snippet = (
        f"    BenchmarkEntry(\n"
        f"        paper_id={args.paper_id!r},\n"
        f"        doi={args.doi!r},\n"
        f"        title={args.title!r},\n"
        f"        expected=ExpectedProtocol(),  # all axes None until verified\n"
        f"        status=\"needs_verification\",\n"
        f"        notes=\"Stub appended via `crucible benchmark add`. "
        f"Verify per docs/HOW_TO_VERIFY_A_PAPER.md before scoring.\",\n"
        f"    ),\n"
    )
    new_text = text.replace(sentinel, snippet + sentinel)
    papers_path.write_text(new_text)
    print(f"appended stub for {args.paper_id!r} to papers.py")
    print("next: open docs/HOW_TO_VERIFY_A_PAPER.md and walk through the procedure",
          file=sys.stderr)
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

    # Open the corpus DB once if --corpus-db was passed; reuse for every entry.
    corpus_store = None
    if args.corpus_db:
        from ..corpus.store import CorpusStore
        corpus_store = CorpusStore.open(args.corpus_db)

    def paper_text_fn(entry):
        # Resolution order:
        #   1. <papers_dir>/<paper_id>.txt  — Methods-section sidecar (best signal)
        #   2. corpus DB by DOI            — title + abstract (medium signal)
        #   3. entry.title                 — worst-case fallback
        if args.papers_dir:
            p = Path(args.papers_dir) / f"{entry.paper_id}.txt"
            if p.exists():
                return p.read_text()
        if corpus_store is not None and entry.doi:
            text = corpus_store.paper_text_for_doi(entry.doi)
            if text:
                return text
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

    pa = sub.add_parser("add", help="append a needs_verification stub to papers.py")
    pa.add_argument("--paper-id", required=True,
                    help="short slug, e.g. mobley_2007_alchemical")
    pa.add_argument("--doi", required=True,
                    help="canonical DOI (Crossref-verifiable)")
    pa.add_argument("--title", required=True,
                    help="paper title (single-line; can be long)")
    pa.set_defaults(func=cmd_add)

    pr = sub.add_parser("run", help="run the transpile against the seed set")
    pr.add_argument("--mock", action="store_true",
                    help="use a deterministic mock transpile (smoke test)")
    pr.add_argument("--papers-dir", default=None,
                    help="dir containing <paper_id>.txt sidecar files (best signal)")
    pr.add_argument("--corpus-db", default=None,
                    help="path to a corpus DuckDB (title+abstract by DOI)")
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
