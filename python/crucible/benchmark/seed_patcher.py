"""Surgical text-mutation of `papers.py` BenchmarkEntry blocks.

Extracted from `benchmark/cli.py` in v1.78 — the `_patch_entry`
algorithm is text-munging that's distinct in shape from the CLI
dispatch surrounding it. Lives here so the CLI file stays scannable.

The patcher is "surgical" in two senses:

1. **Indent-based block termination.** Naive `[^)]*\)` regex would
   close early on parens-in-titles like `"(Lindorff-Larsen et al., 2010)"`
   or `"(PubMed PMID 20947758)"`. Indent-walking ignores those.
2. **In-place rewrite.** Existing `status=` / `verified_by=` lines
   are stripped and re-inserted at a canonical position just before
   the entry's closing `),` so the patcher is idempotent across
   re-runs.

Caller in `benchmark/cli.py:cmd_verify` passes:
- `paper_id`: the entry slug to find
- `new_values`: dict of axis name → new value (for ExpectedProtocol)
- `verified_by`: stamp like "AQN 2026-05-04"
- `notes_extra`: list of strings to append to the entry's notes

Returns the modified file text. Returns the input text unchanged if
the entry isn't found or its shape has drifted from the conventional
layout (defensive: would rather leave a real-world papers.py
untouched than corrupt it).
"""

from __future__ import annotations

import re


def patch_entry(text: str, *, paper_id: str,
                new_values: dict[str, object],
                verified_by: str,
                notes_extra: list[str]) -> str:
    # Find the BenchmarkEntry whose paper_id matches; the entry block
    # ends at the next `\n<INDENT>),\n` where INDENT matches the
    # entry's own opening indent.
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
    closer = "\n" + indent + "),"
    close_idx = text.find(closer, m.end())
    if close_idx == -1:
        return text
    end = close_idx + len(closer)
    block = text[open_idx:end]

    block_new = _replace_expected_protocol(block, indent, new_values)
    block_new = _strip_status_and_verified_by(block_new)
    block_new = _inject_status_lines(block_new, indent, verified_by)
    if notes_extra:
        block_new = _append_to_notes(block_new, verified_by, notes_extra)

    return text.replace(block, block_new, 1)


def _replace_expected_protocol(block: str, indent: str,
                               new_values: dict[str, object]) -> str:
    """Replace the `expected=ExpectedProtocol(...)` body with new
    field values. Indent-walks the closing `)` to avoid early-closing
    on parens-in-string-literals."""
    field_indent = indent + "        "       # 8 spaces deeper than entry
    closer_indent = indent + "    "          # 4 spaces deeper
    field_lines = [f"{field_indent}{k}={v!r}," for k, v in new_values.items()]
    new_expected = (
        "expected=ExpectedProtocol(\n"
        + "\n".join(field_lines)
        + "\n" + closer_indent + ")"
    )
    ep_open_idx = block.find("expected=ExpectedProtocol(")
    if ep_open_idx == -1:
        return block
    ep_closer = "\n" + closer_indent + ")"
    ep_close_idx = block.find(ep_closer, ep_open_idx)
    if ep_close_idx == -1:
        return block
    ep_end = ep_close_idx + len(ep_closer)
    return block[:ep_open_idx] + new_expected + block[ep_end:]


def _strip_status_and_verified_by(block: str) -> str:
    """Drop existing `status=…,` and `verified_by=…,` lines. The
    dataclass defaults supply both, so an entry may have neither
    line at all — strip is a no-op then."""
    block = re.sub(r"^[ \t]*status=[^,\n]+,\s*\n", "", block,
                   flags=re.MULTILINE)
    block = re.sub(r"^[ \t]*verified_by=[^,\n]+,\s*\n", "", block,
                   flags=re.MULTILINE)
    return block


def _inject_status_lines(block: str, indent: str, verified_by: str) -> str:
    """Insert canonical `status="verified",` + `verified_by=...,`
    just before the entry's closing `),`."""
    line_indent = indent + "    "
    inject = (
        f'{line_indent}status="verified",\n'
        f'{line_indent}verified_by={verified_by!r},\n'
    )
    entry_closer = f"\n{indent}),"
    close_pos = block.rfind(entry_closer)
    if close_pos == -1:
        return block
    return block[:close_pos + 1] + inject + block[close_pos + 1:]


def _append_to_notes(block: str, verified_by: str,
                     notes_extra: list[str]) -> str:
    """Append a `[verify <stamp>] note1; note2; …` line to the
    existing notes string literal. Falls through if the notes field
    is missing."""
    joined = "; ".join(notes_extra)
    notes_re = re.compile(
        r'(notes=)("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')',
        re.DOTALL,
    )
    nm = notes_re.search(block)
    if not nm:
        return block
    old_notes_literal = nm.group(2)
    try:
        old_notes = eval(old_notes_literal)   # safe — captured string literal
    except Exception:
        old_notes = ""
    new_notes_text = f"{old_notes}\n\n[verify {verified_by}] {joined}"
    return (
        block[:nm.start()]
        + f"notes={new_notes_text!r}"
        + block[nm.end():]
    )
