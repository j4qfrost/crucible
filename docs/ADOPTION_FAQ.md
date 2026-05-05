# Adoption FAQ

The questions that come up across multiple
[`USER_PROFILE_*.md`](USER_PROFILES.md) audiences. Lives here so the
answers don't get re-derived every time someone considers Crucible.

Organized by category, not by profile — a question often spans
several profiles.

## "Does this actually work?"

### Is the LLM right often enough to trust?

The benchmark
([`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md))
is the canonical answer. Until verified entries are scored, the
honest answer is **"we don't know yet, and we won't tell you we do."**

The framework explicitly refuses to score `needs_verification`
entries — fabricated ground truth is the worst possible failure
mode. Once the seed set is human-verified, the benchmark publishes
real numbers; the project's adoption hinges on what those numbers
say.

### What if it's wrong on my paper?

Two paths:

1. **It's wrong because the LLM missed the extraction.** File a
   benchmark issue per
   [`docs/HOW_TO_VERIFY_A_PAPER.md`](HOW_TO_VERIFY_A_PAPER.md);
   your audit becomes a benchmark contribution.
2. **It's wrong because the schema can't represent your case
   (e.g. OPLS3 protein FF).** That's a schema gap. Open an
   issue tagged `schema-allowlist`. Pre-fix: substitute the
   closest allowed value and document the substitution in your
   reproduction.

The validation gates catch most "silently wrong" failures *before*
runtime — that's the wedge. They don't catch "scientifically
wrong" (e.g. wrong system at all); that's still a human
responsibility.

### What's the failure mode that worries you most?

Per the salt-mines panel review (see
`~/Projects/salt-mines/reports/crucible.verdict.md`): the LLM
producing a spec that *passes Gates 1-3* but is physically
incorrect for reasons the gates can't see. Specifically, ambiguous
Methods sections where the LLM picks a plausible-but-wrong default.

Mitigation today: provenance tagging surfaces `assumed` fields, so
reviewers can audit them. Mitigation roadmap: the option-3
fine-tune (Phase 4 of `docs/ADOPTION_PLAN.md`) reduces the rate of
plausible-but-wrong defaults by training on verified pairs.

## "What's it cost?"

### Software cost?

Apache 2.0. Free. Forever.

### Compute cost?

Two pieces:

1. **LLM call** for the protocol extraction. Anthropic API: ~$0.05
   per paper. Local mode (Ollama / Qwen2.5-Coder 7B): the
   electricity cost of a few seconds of GPU time. Crucible's
   `LocalProvider` is OpenAI-API-compatible; configure via env
   vars per [`docs/ON_PREM.md`](ON_PREM.md).
2. **Simulation runtime.** This is the actual MD — Crucible
   doesn't change the cost of the simulation itself. The
   advisor (`crucible advise`) gives a per-job cost estimate.
   For typical solvated-protein NPT: ~$2-5 per ns on cloud GPU.

### Maintainer time cost?

For a research lab adopting Crucible: **~10 minutes per paper**
once you're past the install. The 30-minute path in each
`USER_PROFILE_*.md` includes the install; subsequent papers run
through the same pipeline in seconds.

For a pharma POC: **~30 days for 1 evaluator** per
[`docs/USER_PROFILE_PHARMA_POC.md`](USER_PROFILE_PHARMA_POC.md).

### What about the JOSS / methods paper?

The methods paper is in preparation per
[`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 1. Until it
publishes, citing Crucible is fine but you'll do so via the
GitHub repo URL + the version tag. Once it publishes, the
preferred citation will be in the README.

## "How do I integrate it?"

### Can I call it from my Python pipeline?

Yes. `pip install -e python` (eventually `pip install crucible`
once on PyPI). The Python bindings cover IR + validation + lint
+ corpus + benchmark; the renderer + LLM transpile go through
the Julia CLI via subprocess (see
[`docs/USER_PROFILE_DATA_ENGINEER.md`](USER_PROFILE_DATA_ENGINEER.md)
for the full data-pipeline story).

### Can I call it from my Julia pipeline?

Yes. `using Crucible` after `Pkg.instantiate()`. The Julia API
is in [`docs/IR.md`](IR.md) (auto-generated from schema).

### Can I call it from R / Rust / Go / TypeScript / …?

The IR is JSON; consume it directly. The
[`musings/why_not_protobuf.md`](../musings/why_not_protobuf.md)
discussion explains why JSON Schema (not gRPC) is the
cross-language contract. For TS specifically, run
`quicktype src/spec/schema.json` to generate types.

### Does it work on macOS / Linux / Windows?

macOS + Linux: fully supported.
Windows: experimental — Crucible warns at runtime and several
backends require WSL.
HPC clusters: Linux paths apply; the renderer emits a script you
can submit via slurm/PBS/whatever. The runtime layer (`crucible
run`) shells out to `python script.py`, so respect your cluster's
Python module conventions.

### What about offline / air-gapped environments?

Yes for the Crucible CLI itself: no telemetry, no auto-update.
Local-LLM mode keeps the LLM call inside your network.

The base install requires outbound HTTP to download deps once
(`Pkg.instantiate` from JuliaHub, `pip install` from PyPI). After
that it's offline-capable. If you're truly air-gapped, mirror
JuliaHub + PyPI to your internal registry, then install from there.

### What dependencies does it pull in?

See `Project.toml` (Julia) and `python/pyproject.toml` (Python).
Highlights:

- **Julia:** HTTP.jl, JSON3.jl, JSONSchema.jl, Pluto.jl,
  DuckDB.jl, Mustache.jl, Unitful.jl. All MIT/Apache.
- **Python:** pydantic v2, jsonschema. Optional extras:
  duckdb (for corpus), streamlit (for GUI).
- **Runtime (when actually running an MD):** OpenMM (Python),
  optionally PDBFixer, mdtraj. Pulled via CondaPkg if you opt in.

No proprietary deps. No GPL.

## "What's the IP / data story?"

### Does anything leave my network?

Default: only the LLM call (Anthropic by default). Set
`--provider local` and configure `CRUCIBLE_LOCAL_ENDPOINT` per
[`docs/ON_PREM.md`](ON_PREM.md) — then nothing leaves. The
Crucible CLI itself does no telemetry, no analytics, no
auto-update.

The network-policy preflight script in
[`docs/ON_PREM.md`](ON_PREM.md#network-policy-preflight) is the
audit artifact for IT/security review.

### Does Crucible store my paper text anywhere?

Yes — the transcript store (`~/.local/share/crucible/transcripts.duckdb`)
records every LLM call's input + output for the option-3 fine-tune
flywheel. **This is on your machine; nothing is uploaded.** If you
don't want it kept, delete the file or set `CRUCIBLE_TRANSCRIPT_DISABLE=1`
(coming in v1.62; track the issue if it's not there yet).

### Can I use Crucible's outputs in my paper / patent?

Yes. Apache 2.0 covers the software; the rendered scripts are
your work product. Crucible doesn't claim ownership of anything
you generate.

For attribution: cite the GitHub URL + version tag for now;
the methods paper for after it publishes.

### Can the maintainer see what I'm doing?

No. Crucible has no telemetry. The maintainer learns about your
usage only when you tell them — opening an issue, sending an
email, citing the paper.

## "Where does this go from here?"

### What's the roadmap?

[`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) (18-month strategic) +
[`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
(180-day tactical) + the [`CHANGELOG.md`](../CHANGELOG.md)
(committed history). The roadmap is publicly versioned; what
ships when is what's in those files.

### What's the bus factor?

One full-time-equivalent maintainer. The deliberately-modular
architecture (IR-as-contract, JSON Schema, schema migrations) is
designed so that any single person can pick up the codebase
without prior context — see [`docs/POWER_USERS.md`](POWER_USERS.md)
for the contributor onboarding doc.

If the maintainer disappears, the project's outputs (the IR
schema, the validation rules, the rendered scripts, the
benchmark dataset) remain useful as a citable artifact. That's
by design per
[`musings/scaling_modes.md`](../musings/scaling_modes.md): even
the "academic mode floor" is a citable open-source contribution
of record.

### What happens when the LLM models change?

Crucible is provider-agnostic. The `LLMProvider` abstract type
([`src/llm/Provider.jl`](../src/llm/Provider.jl)) covers
Anthropic, Local (any OpenAI-API-compatible), and the planned
fine-tuned LocalProvider. Adding a new provider (Gemini,
GPT-class, future open-weights model) is one struct + one
function — see [`docs/POWER_USERS.md`](POWER_USERS.md) for the
template.

When Anthropic's API surface changes: pin the version we test
against; ship an upgrade in a coordinated PR. The provider is
isolated; nothing else in the codebase touches the API directly.

### What happens when OpenMM / Molly change?

The renderers emit version-pinned scripts. If OpenMM's API
changes, update the renderer; existing IR specs continue to
load. The `test/` directory has a "live OpenMM smoke" cell that
catches incompatibilities before they reach users.

Molly is younger and moves faster; we pin a version range in
`Project.toml` and update the renderer when it breaks.

### Will Crucible support GROMACS?

Scoped, not yet shipped. See
[`docs/GROMACS_SCOPING.md`](GROMACS_SCOPING.md) for the design;
the renderer skeleton is at
[`src/backends/GROMACSBackend.jl`](../src/backends/GROMACSBackend.jl).
The renderer body lands when a pilot specifically requests it —
speculative builds without pilot pull are deferred per the
commercial-validation plan's "scope expansion ties to pilot"
rule.

## "Help / community"

### Where do I file issues?

GitHub: github.com/j4qfrost/crucible/issues. Tag templates exist
for `bug`, `enhancement`, `schema-allowlist`, `user-profile`.

### Is there a Discord / Slack / Matrix?

Per [`docs/ADOPTION_PLAN.md`](ADOPTION_PLAN.md) Phase 0 deliverable
0.6: a community channel is on the deliverables list. Until it
ships, GitHub Issues + the maintainer's email are the contact
surfaces.

### Who do I email if I need a real conversation?

Maintainer contact in the README. For pharma-POC conversations
specifically: per
[`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
Phase B Track 1, $5K-$15K fixed-fee POCs are the formal entry.

### Can I contribute even if I'm not in comp-chem?

Yes — see [`docs/POWER_USERS.md`](POWER_USERS.md). Real
non-domain contributions: docs improvements, CI/build
hardening, the corpus + benchmark layers (which are
data-engineering, not chemistry), the Python-side packaging.
Most v1.41-v1.55 work was infrastructure, not chemistry.

## See also

- [`docs/USER_PROFILES.md`](USER_PROFILES.md) — the seven profile
  docs the FAQ supports.
- [`docs/PROJECT_PITCH.md`](PROJECT_PITCH.md) — three-length
  pitches that lead into the FAQ.
- [`docs/ADOPTION_TIMELINE.md`](ADOPTION_TIMELINE.md) — what
  activates when.
- [`docs/ADOPTION_STRATEGY_PLAYBOOK.md`](ADOPTION_STRATEGY_PLAYBOOK.md)
  — the meta-doc on writing adoption-strategy material.
