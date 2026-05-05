"""Run an LLM transpile against benchmark entries.

The runner is **transpile-callback agnostic**: pass in any callable
`(paper_text: str) -> MDSpec` and the runner handles iteration,
timing, error capture, and aggregation. The default callback shells
out to the Julia CLI's `transpile` subcommand via
`crucible.cli_bridge`, which is gated by `ANTHROPIC_API_KEY` (or
routes through Claude CLI / a `LocalProvider` per the user's setup).

Tests inject a mock callable; CI doesn't pay for live LLM tokens.
"""

from __future__ import annotations

import time
import traceback
from dataclasses import dataclass, field
from typing import Callable, Iterable, Iterator, Optional

from ..spec import MDSpec
from .papers import BenchmarkEntry
from .scorer import ScoreResult, score


TranspileFn = Callable[[str], MDSpec]


class MockTranspileProvider:
    """Deterministic mock transpile callable.

    Returns a `MDSpec` chosen by `template_name` (defaults to vanilla).
    Useful for smoke tests + CI cells that exercise the runner /
    scorer / reporter without paying for live LLM tokens.

    Use as a `TranspileFn`:

        runner.run(entries, paper_text_fn,
                   MockTranspileProvider(template_name="vanilla"))

    Promoted from an inline lambda inside `cli.py:cmd_run` so tests can
    exercise the same code path the `--mock` CLI flag does.
    """

    def __init__(self, *, template_name: str = "vanilla"):
        self.template_name = template_name

    def __call__(self, _paper_text: str) -> MDSpec:
        from ..templates import init as init_template
        return init_template(self.template_name)


@dataclass
class RunOutcome:
    paper_id: str
    ok: bool
    elapsed_s: float
    score_result: Optional[ScoreResult] = None
    error: Optional[str] = None


def run(
    entries: Iterable[BenchmarkEntry],
    paper_text_fn: Callable[[BenchmarkEntry], Optional[str]],
    transpile_fn: TranspileFn,
    *,
    allow_unverified: bool = True,
) -> Iterator[RunOutcome]:
    """Run the benchmark.

    Args:
        entries: iterable of `BenchmarkEntry`.
        paper_text_fn: maps an entry to the paper text (Methods section,
            full text, or abstract). Returning `None` skips the entry
            with `ok=False, error="no paper text"`.
        transpile_fn: maps paper text to an `MDSpec`. Default in the CLI
            is the Julia transpile subprocess; tests pass a mock.
        allow_unverified: scores entries whose `status != "verified"`.
            Default `True` because the runner is also useful for
            measuring drift on the unverified seed set; the published
            benchmark uses `allow_unverified=False`.

    Yields one `RunOutcome` per entry.
    """
    for entry in entries:
        t0 = time.perf_counter()
        try:
            text = paper_text_fn(entry)
            if text is None:
                yield RunOutcome(
                    paper_id=entry.paper_id, ok=False,
                    elapsed_s=time.perf_counter() - t0,
                    error="no paper text",
                )
                continue
            spec = transpile_fn(text)
            sr = score(entry, spec, allow_unverified=allow_unverified)
            yield RunOutcome(
                paper_id=entry.paper_id, ok=True,
                elapsed_s=time.perf_counter() - t0,
                score_result=sr,
            )
        except Exception as exc:
            yield RunOutcome(
                paper_id=entry.paper_id, ok=False,
                elapsed_s=time.perf_counter() - t0,
                error=f"{type(exc).__name__}: {exc}",
            )
