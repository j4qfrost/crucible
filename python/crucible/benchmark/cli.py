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
import os
import sys
from dataclasses import asdict
from datetime import datetime
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


def cmd_verify(args: argparse.Namespace) -> int:
    """Interactive axis-by-axis verification of a single seed entry.

    Walks the user through the 8 ExpectedProtocol axes, accepts a value
    or `none`/empty for each, prints the resulting Python diff, and
    appends a `verified_by` stamp. Writes the change back to papers.py
    so the next pytest run picks it up.

    Designed to lower the friction on the highest-leverage paywall-gated
    punch-list item per `docs/HOW_TO_VERIFY_A_PAPER.md`. Reading the
    paper is still the bottleneck — this just kills the
    "what-was-the-syntax" friction at the keyboard.
    """
    entries_by_id = {e.paper_id: e for e in list_entries()}
    if args.paper_id not in entries_by_id:
        print(f"unknown paper_id {args.paper_id!r}. available:", file=sys.stderr)
        for pid in sorted(entries_by_id):
            print(f"  - {pid}", file=sys.stderr)
        return 1
    entry = entries_by_id[args.paper_id]
    if entry.is_scoreable() and not args.force:
        print(f"{args.paper_id!r} is already verified ({entry.verified_by}). "
              f"Pass --force to re-verify.", file=sys.stderr)
        return 1

    print(f"Verifying: {entry.title}")
    print(f"DOI: https://doi.org/{entry.doi}")
    print()
    print("For each axis, enter a value or 'none' (paper doesn't specify) "
          "or '' to keep current.")
    print("See docs/HOW_TO_VERIFY_A_PAPER.md for allowlist mappings.\n")

    axes: list[tuple[str, str, str, type]] = [
        ("protein_ff", "amber14sb / amber99sb_ildn / charmm36m / opls_aam / "
                       "martini3 / martini2_2", "string", str),
        ("water_model", "TIP3P / TIP4P_EW / SPC_E / implicit_GBSA / vacuum",
         "string", str),
        ("ensemble", "NVE / NVT / NPT (production stage)", "string", str),
        ("dt_fs", "integration timestep in fs (e.g. 2.0)", "float", float),
        ("temperature_K", "production temperature (e.g. 300.0)", "float", float),
        ("duration_ns", "production duration; FEP=per-window, REMD=per-replica",
         "float", float),
        ("pressure_bar", "barostat pressure (NPT only)", "float", float),
        ("fep_lambda_count", "number of FEP λ-windows (FEP only)",
         "int", int),
        ("solvent_padding_nm", "solute-to-box-edge buffer in nm (e.g. 1.0)",
         "float", float),
        ("thermostat", "langevin / nose_hoover / andersen / berendsen",
         "string", str),
    ]

    new_values: dict[str, object] = {}
    notes_lines: list[str] = []
    for name, hint, kind, parse in axes:
        current = getattr(entry.expected, name)
        prompt = f"  {name} ({hint}) [current={current!r}]: "
        try:
            raw = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\naborted.", file=sys.stderr)
            return 130
        if not raw:
            new_values[name] = current
            continue
        if raw.lower() in ("none", "null", "n/a", "-"):
            new_values[name] = None
            notes_lines.append(f"{name}: paper does not specify")
            continue
        try:
            new_values[name] = parse(raw)
        except (ValueError, TypeError):
            print(f"  ⚠ couldn't parse {raw!r} as {kind}; leaving as {current!r}",
                  file=sys.stderr)
            new_values[name] = current

    print("\nNew expected protocol:")
    for name, _, _, _ in axes:
        print(f"  {name} = {new_values[name]!r}")
    print()

    initials = args.initials or os.environ.get("USER", "ANON").upper()[:3]
    today = datetime.now().strftime("%Y-%m-%d")
    verified_by = f"{initials} {today}"

    confirm = input(f"Write to papers.py and stamp 'verified_by=\"{verified_by}\"'? [y/N] ").strip()
    if confirm.lower() not in ("y", "yes"):
        print("aborted.", file=sys.stderr)
        return 1

    papers_path = Path(__file__).resolve().parent / "papers.py"
    text = papers_path.read_text()
    new_text = _patch_entry(
        text, paper_id=args.paper_id,
        new_values=new_values,
        verified_by=verified_by,
        notes_extra=notes_lines,
    )
    if new_text == text:
        print("no change written (regex didn't match — file layout drifted?)",
              file=sys.stderr)
        return 2
    papers_path.write_text(new_text)
    print(f"✓ wrote verified status for {args.paper_id!r}")
    print("next: run `cd python && pytest tests/test_benchmark.py` to confirm.",
          file=sys.stderr)
    return 0


def _patch_entry(text: str, *, paper_id: str,
                 new_values: dict[str, object],
                 verified_by: str,
                 notes_extra: list[str]) -> str:
    """Surgical re-write of a single BenchmarkEntry block.

    Finds the `paper_id="<paper_id>"` line, walks forward to the matching
    closing `)`, replaces the ExpectedProtocol field block + status +
    verified_by inside. Conservative: returns `text` unchanged if the
    expected shape isn't found.
    """
    import re
    # Find the BenchmarkEntry whose paper_id matches; the entry block ends
    # at the next `\n<INDENT>),\n` where INDENT matches the entry's own
    # opening indent. Indent-based termination avoids the parens-inside-
    # string-literal trap (titles contain things like
    # "(Lindorff-Larsen et al., 2010)").
    pid_re = re.compile(
        r"^([ \t]*)BenchmarkEntry\(\s*\n\s*paper_id=[\"']"
        + re.escape(paper_id) + r"[\"']",
        re.MULTILINE,
    )
    m = pid_re.search(text)
    if not m:
        return text
    indent = m.group(1)
    open_idx = m.start()
    # Walk forward for the closing `\n<indent>),`. There may be inner
    # `),` lines (from nested ExpectedProtocol or List literals) but
    # they're at deeper indentation.
    closer = "\n" + indent + "),"
    close_idx = text.find(closer, m.end())
    if close_idx == -1:
        return text
    end = close_idx + len(closer)
    block = text[open_idx:end]

    # ExpectedProtocol is one indent-level deeper than BenchmarkEntry. Its
    # closing `)` is at indent + "    "; find that for safe termination
    # (regex `[^)]*\)` would close early on parens-in-comments like
    # "(PubMed PMID 20947758)" inside titles or notes).
    field_indent = indent + "        "       # 8 spaces deeper than entry indent
    closer_indent = indent + "    "          # 4 spaces deeper
    field_lines = []
    for k, v in new_values.items():
        field_lines.append(f"{field_indent}{k}={v!r},")
    new_expected = "expected=ExpectedProtocol(\n" + "\n".join(field_lines) + "\n" + closer_indent + ")"

    ep_open_idx = block.find("expected=ExpectedProtocol(")
    if ep_open_idx == -1:
        block_new = block
    else:
        ep_closer = "\n" + closer_indent + ")"
        ep_close_idx = block.find(ep_closer, ep_open_idx)
        if ep_close_idx == -1:
            block_new = block
        else:
            ep_end = ep_close_idx + len(ep_closer)
            block_new = block[:ep_open_idx] + new_expected + block[ep_end:]
    # Strip any existing `status=...,` and `verified_by=...,` lines so we can
    # reinsert canonical ones just before the closing `),`. The dataclass
    # defaults `status="needs_verification"` + `verified_by=None`, so an
    # entry may have neither line at all.
    line_indent = indent + "    "          # one level deeper than entry
    block_new = re.sub(
        r"^[ \t]*status=[^,\n]+,\s*\n",
        "",
        block_new,
        flags=re.MULTILINE,
    )
    block_new = re.sub(
        r"^[ \t]*verified_by=[^,\n]+,\s*\n",
        "",
        block_new,
        flags=re.MULTILINE,
    )
    inject = (
        f'{line_indent}status="verified",\n'
        f'{line_indent}verified_by={verified_by!r},\n'
    )
    # Insert just before the closing `\n<indent>),` of this BenchmarkEntry.
    entry_closer = f"\n{indent}),"
    close_pos = block_new.rfind(entry_closer)
    if close_pos == -1:
        # Defensive: if we somehow lost the closer, leave block_new as-is.
        pass
    else:
        block_new = block_new[:close_pos + 1] + inject + block_new[close_pos + 1:]

    # Append notes_extra to the existing notes.
    if notes_extra:
        joined = "; ".join(notes_extra)
        # Look for the notes= line and append to it.
        notes_re = re.compile(
            r'(notes=)("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')',
            re.DOTALL,
        )
        nm = notes_re.search(block_new)
        if nm:
            old_notes_literal = nm.group(2)
            try:
                old_notes = eval(old_notes_literal)  # safe — captured string literal
            except Exception:
                old_notes = ""
            new_notes_text = f"{old_notes}\n\n[verify {verified_by}] {joined}"
            block_new = block_new[:nm.start()] + f"notes={new_notes_text!r}" + block_new[nm.end():]

    return text.replace(block, block_new, 1)


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
    trends_conn = None
    if args.trends_db:
        from .runs_store import open_runs_store
        trends_conn = open_runs_store(args.trends_db)
    md = render_report(
        pairs, intro=args.intro,
        trends_db=trends_conn,
        brief=getattr(args, "brief", False),
    )
    if trends_conn is not None:
        trends_conn.close()
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
            text = corpus_store.paper_text_for_doi(
                entry.doi,
                prefer_full_text=args.full_text,
                cache_dir=Path(args.full_text_cache) if args.full_text_cache else None,
            )
            if text:
                return text
        return entry.title

    if args.mock:
        # Deterministic mock — returns the vanilla template for every paper.
        # Promoted to MockTranspileProvider so tests can call it directly.
        from .runner import MockTranspileProvider
        transpile_fn = MockTranspileProvider(template_name="vanilla")
    else:
        from ..cli_bridge import _run as cli_run
        from ..spec import MDSpec
        def transpile_fn(text):
            res = cli_run(["transpile", "--stdin", "--format", "json"], stdin=text)
            return MDSpec.from_json(res.stdout)

    out_path = Path(args.out) if args.out else None
    if out_path:
        out_path.parent.mkdir(parents=True, exist_ok=True)

    # Open the longitudinal runs store if --runs-db was passed, OR reuse
    # the corpus DB by default if --corpus-db was passed (single shared
    # DuckDB file is the friction-minimum config).
    runs_store = None
    runs_db_path = args.runs_db or args.corpus_db
    run_id = None
    if runs_db_path:
        from .runs_store import open_runs_store, new_run_id
        runs_store = open_runs_store(runs_db_path)
        run_id = new_run_id()

    # Optional: also write per-paper accuracy back into the corpus DB so the
    # corpus GUI surfaces "this paper's last benchmark accuracy was X%".
    score_back_corpus = corpus_store
    by_paper_id = {e.paper_id: e for e in entries}

    llm_provider = "mock" if args.mock else "cli_bridge"
    llm_model = args.llm_model

    from ..spec import SCHEMA_VERSION
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

        if runs_store is not None and run_id is not None:
            from .runs_store import insert_outcome
            insert_outcome(
                runs_store,
                run_id=run_id,
                outcome=outcome,
                llm_provider=llm_provider,
                llm_model=llm_model,
                schema_version=SCHEMA_VERSION,
            )

        # Write per-paper score back to the corpus DB so it surfaces in
        # the corpus tier (GUI / `corpus papers` queries).
        if (
            score_back_corpus is not None
            and outcome.score_result is not None
            and outcome.ok
        ):
            entry = by_paper_id.get(outcome.paper_id)
            if entry is not None and entry.doi:
                score_back_corpus.upsert_benchmark_score(
                    doi=entry.doi,
                    paper_id=outcome.paper_id,
                    total=outcome.score_result.total,
                    max_score=outcome.score_result.max_score,
                    provider=llm_provider,
                )
    if runs_store is not None:
        runs_store.close()
        print(f"recorded run {run_id!r} → {runs_db_path}", file=sys.stderr)
    if out_path is not None:
        out_path.write_text("\n".join(rows) + "\n")
        print(f"wrote {len(rows)} outcomes → {out_path}", file=sys.stderr)
    return 0


def cmd_trends(args: argparse.Namespace) -> int:
    """Per-paper accuracy rollup from the longitudinal runs store."""
    from .runs_store import open_runs_store, stats, trends
    conn = open_runs_store(args.runs_db)
    if args.paper_id:
        rows = list(trends(conn, paper_id=args.paper_id))
    else:
        rows = list(trends(conn))
    out = {
        "stats": stats(conn),
        "trends": [
            {
                "paper_id": r.paper_id,
                "n_runs": r.n_runs,
                "avg_pct": round(r.avg_pct, 3),
                "last_run_at": r.last_run_at,
                "providers": r.providers,
            }
            for r in rows
        ],
    }
    print(json.dumps(out, indent=2))
    conn.close()
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    """Dump the runs table to JSONL — option-3 fine-tune flywheel feeder."""
    from .runs_store import export_jsonl, open_runs_store
    conn = open_runs_store(args.runs_db)
    sink = open(args.out, "w") if args.out else sys.stdout
    n = 0
    try:
        for line in export_jsonl(
            conn,
            paper_id=args.paper_id,
            llm_provider=args.provider,
        ):
            sink.write(line + "\n")
            n += 1
    finally:
        if args.out:
            sink.close()
    print(f"exported {n} row(s)" + (f" → {args.out}" if args.out else ""),
          file=sys.stderr)
    conn.close()
    return 0


def cmd_publish(args: argparse.Namespace) -> int:
    """One-shot: run the benchmark + render the report + (optionally) write
    it to a docs path. Reduces the publish cycle from 3 commands to 1.
    """
    import tempfile
    runs_jsonl = tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False)
    runs_jsonl.close()
    runs_path = Path(runs_jsonl.name)

    # Reuse the existing run + report code paths via Namespace shims so we
    # don't duplicate the corpus-resolution / runs-store wiring.
    run_args = argparse.Namespace(
        db=None,
        mock=args.mock,
        papers_dir=args.papers_dir,
        corpus_db=args.corpus_db,
        full_text=args.full_text,
        full_text_cache=None,
        runs_db=args.runs_db or args.corpus_db,
        llm_model=args.llm_model,
        out=str(runs_path),
        verified_only=args.verified_only,
        allow_unverified=args.allow_unverified,
    )
    rc = cmd_run(run_args)
    if rc != 0:
        runs_path.unlink(missing_ok=True)
        return rc

    report_args = argparse.Namespace(
        db=None,
        runs=str(runs_path),
        out=args.out,
        intro=args.intro,
        trends_db=args.runs_db or args.corpus_db,
    )
    rc = cmd_report(report_args)
    runs_path.unlink(missing_ok=True)
    return rc


def cmd_runs_stats_md(args: argparse.Namespace) -> int:
    """Markdown variant of `runs-stats` — embeddable in reports."""
    from .reporter import render_runs_stats_md
    from .runs_store import open_runs_store
    conn = open_runs_store(args.runs_db)
    md = render_runs_stats_md(conn)
    if not md:
        print("_(no runs recorded yet)_", file=sys.stderr)
    else:
        print(md)
    conn.close()
    return 0


def cmd_runs_stats(args: argparse.Namespace) -> int:
    """Per-axis accuracy + per-provider breakdown from the runs DB."""
    from .runs_store import (
        open_runs_store, per_axis_accuracy, per_provider_summary,
        schema_version_distribution, stats,
    )
    conn = open_runs_store(args.runs_db)
    out = {
        "stats": stats(conn),
        "schema_version_distribution": schema_version_distribution(conn),
        "per_provider": per_provider_summary(conn),
        "per_axis_overall": per_axis_accuracy(conn),
    }
    if args.provider:
        out["per_axis_for_provider"] = {
            args.provider: per_axis_accuracy(conn, llm_provider=args.provider),
        }
    print(json.dumps(out, indent=2))
    conn.close()
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

    pt = sub.add_parser("trends", help="per-paper accuracy rollup from runs DB")
    pt.add_argument("runs_db", help="path to the DuckDB with benchmark_runs table")
    pt.add_argument("--paper-id", default=None, help="filter to one paper")
    pt.set_defaults(func=cmd_trends)

    prs = sub.add_parser("runs-stats",
                         help="per-axis + per-provider accuracy from runs DB")
    prs.add_argument("runs_db", help="path to the DuckDB with benchmark_runs table")
    prs.add_argument("--provider", default=None,
                     help="also emit per-axis accuracy filtered to this provider")
    prs.set_defaults(func=cmd_runs_stats)

    prsm = sub.add_parser("runs-stats-md",
                          help="markdown variant of runs-stats (embeddable in reports)")
    prsm.add_argument("runs_db", help="path to the DuckDB with benchmark_runs table")
    prsm.set_defaults(func=cmd_runs_stats_md)

    pe = sub.add_parser("export-jsonl",
                        help="dump benchmark_runs to JSONL (option-3 flywheel feeder)")
    pe.add_argument("runs_db", help="path to the DuckDB with benchmark_runs table")
    pe.add_argument("--out", default=None, help="output path (default: stdout)")
    pe.add_argument("--paper-id", default=None, help="filter to one paper")
    pe.add_argument("--provider", default=None, help="filter to one provider")
    pe.set_defaults(func=cmd_export)

    pb = sub.add_parser("publish",
                        help="one-shot: run + report (writes to --out path)")
    pb.add_argument("--mock", action="store_true",
                    help="use a deterministic mock transpile (smoke test)")
    pb.add_argument("--papers-dir", default=None)
    pb.add_argument("--corpus-db", default=None)
    pb.add_argument("--runs-db", default=None,
                    help="defaults to --corpus-db if set")
    pb.add_argument("--full-text", action="store_true")
    pb.add_argument("--llm-model", default=None)
    pb.add_argument("--verified-only", action="store_true")
    pb.add_argument("--allow-unverified", action="store_true")
    pb.add_argument("--intro", default=None)
    pb.add_argument("--out", default=None,
                    help="markdown destination (default: stdout)")
    pb.set_defaults(func=cmd_publish)

    pv = sub.add_parser("verify",
                        help="interactive axis-by-axis verification of one entry")
    pv.add_argument("--paper-id", required=True,
                    help="paper_id of the seed entry to verify")
    pv.add_argument("--initials", default=None,
                    help="initials for verified_by (default: $USER first 3 chars)")
    pv.add_argument("--force", action="store_true",
                    help="re-verify an already-verified entry")
    pv.set_defaults(func=cmd_verify)

    pr = sub.add_parser("run", help="run the transpile against the seed set")
    pr.add_argument("--mock", action="store_true",
                    help="use a deterministic mock transpile (smoke test)")
    pr.add_argument("--papers-dir", default=None,
                    help="dir containing <paper_id>.txt sidecar files (best signal)")
    pr.add_argument("--corpus-db", default=None,
                    help="path to a corpus DuckDB (title+abstract by DOI)")
    pr.add_argument("--full-text", action="store_true",
                    help="fetch the OA PDF + run pdftotext when available "
                         "(needs network + system pdftotext; falls back to "
                         "title+abstract on any failure)")
    pr.add_argument("--full-text-cache", default=None,
                    help="directory to cache extracted PDF text "
                         "(default: $XDG_CACHE_HOME/crucible/corpus_full_text)")
    pr.add_argument("--runs-db", default=None,
                    help="path to a DuckDB to record this run's outcomes "
                         "(default: reuses --corpus-db if set)")
    pr.add_argument("--llm-model", default=None,
                    help="model name to record alongside the run "
                         "(e.g. claude-opus-4-7, qwen2.5-coder-7b)")
    pr.add_argument("--out", default=None, help="output JSONL path")
    pr.add_argument("--verified-only", action="store_true")
    pr.add_argument("--allow-unverified", action="store_true",
                    help="score unverified entries (dry-run measurement)")
    pr.set_defaults(func=cmd_run)

    pp = sub.add_parser("report", help="render markdown report from a runs JSONL")
    pp.add_argument("runs", help="path to JSONL produced by `benchmark run`")
    pp.add_argument("--out", default=None, help="output .md path (default: stdout)")
    pp.add_argument("--intro", default=None, help="optional intro paragraph")
    pp.add_argument("--trends-db", default=None,
                    help="path to a runs DuckDB to include a trends section")
    pp.add_argument("--brief", action="store_true",
                    help="emit a single-table summary instead of per-axis detail")
    pp.set_defaults(func=cmd_report)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
