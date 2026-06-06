# Security Policy

## Reporting a Vulnerability

If you find a security issue in `crucible`, please **do not** open a public issue. Report it
privately instead:

- Preferred: open a private advisory via GitHub Private Vulnerability Reporting —
  <https://github.com/j4qfrost/crucible/security/advisories/new>
- Fallback: email `j4qfrost@gmail.com`.

Expect an acknowledgement within ~5 business days (best-effort, solo maintainer). Coordinated
disclosure on a mutually agreed timeline is preferred.

## Supported Versions

This project is pre-1.0. Security fixes land on the default branch; only the latest default-branch
state / current `v0.x` is supported. There are no backports to older tags.

| Version | Supported |
| ------- | --------- |
| latest default branch | ✅ |
| older tags | ❌ |

## Scope

**In scope** (please report):
- Vulnerabilities in the rendered Python / Julia simulation scripts that could lead to arbitrary
  code execution beyond what the user explicitly asked for (e.g. shell injection through paper
  text, path traversal in `--out` arguments, deserialization issues in the IR).
- Issues in the LLM provider layer that could leak the user's API key or paper contents to
  unintended destinations.
- Issues in the transcript store that could expose private paper text to other users on a shared
  host.

**Out of scope**:
- The simulation scripts crucible *generates* are run by the user, on the user's hardware. Bugs
  that produce *physically wrong* simulation output (energy drift, missing restraints, etc.) are
  correctness bugs, not security bugs — file a normal issue.
- Bugs in OpenMM, Molly.jl, mdtraj, PDBFixer, or other downstream tools — report those upstream.

## Handling of secrets

- **Never embed an API key** (`ANTHROPIC_API_KEY`, Forgejo / Woodpecker / GitHub tokens, etc.) in
  code, configuration files, fixtures, or the transcript store. Keys are read from the environment
  at use-time and are never written to disk by `crucible` itself. The Pluto notebook displays the
  provider name and cost estimate, never the key.
- The transcript store records the LLM **response** but not the **request authentication**. If a
  response itself contains sensitive content (e.g. a paper's restricted-access full text), the
  user chooses whether to share the transcript JSONL.
- If you discover a code path that violates these rules, treat it as an in-scope vulnerability and
  report it via the channels above.
