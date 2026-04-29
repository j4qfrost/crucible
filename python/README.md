# Crucible — Python bindings

Pure-Python access to the Crucible IR + validation + lint + templates.
The renderer, runtime, and LLM transpile stay in Julia and are reached
through a subprocess bridge.

This is **Phase 2b, Path 3** of the adoption plan
([`musings/ecosystem_alternatives.md`](../musings/ecosystem_alternatives.md)):
the IR is the cross-language contract; the IR layer ships natively in
Python so Python-only labs can build, mutate, validate, lint, and
serialize MDSpecs without learning Julia. Heavy operations
(`render`, `run`, `serve`) shell out to the Julia CLI exactly the way
the Python rendered scripts shell out to OpenMM — the integration
boundary stays at the process layer in both directions
([`musings/why_subprocess_over_pythoncall.md`](../musings/why_subprocess_over_pythoncall.md)).

## What works without Julia installed

- Build any of the 13 starter templates (`crucible.templates.init(...)`).
- Construct, mutate, and JSON-serialize MDSpecs (pydantic-typed).
- Run **Gate 1 (JSON Schema)** + **Gate 2 (semantic rules)** validation.
- Compute provenance coverage + run all lint rules.
- Migrate JSON across schema versions (0.1.0 → 0.2.0 → 0.3.0).

## What requires the Julia CLI

- `crucible.render(spec, "openmm")` — script generation.
- `crucible.run(spec, workdir=…)` — full simulation.
- `crucible.health(spec)` — Gate 3 (loadability) on top of Gates 1–2.
- `crucible.events(workdir)` — read the structured event log.
- `crucible.diff(left, right)` — IR diff (intent or syntactic).

The Python wrappers find the Julia binary in this order:

1. `$CRUCIBLE_BIN`
2. `bin/crucible` next to the package (dev tree)
3. `crucible` on `$PATH`

## Install

```bash
# from the Crucible repo root, dev install:
pip install -e python[dev]

# from PyPI (when published):
pip install crucible
```

Python ≥ 3.10. Hard deps: `pydantic>=2.5`, `jsonschema>=4.20`.

## Quickstart

```python
import crucible

# Pick a starter template — same registry as the Julia CLI's
# `crucible templates init`.
spec = crucible.templates.init("kinase_inhibitor_fep")

# Mutate any field — pydantic validates on assignment.
spec = spec.model_copy(update={
    "notes": "Imatinib + mutant Abl, Q3 2026 retro",
})
spec.system.source.ligand_smiles = "Cc1ccc(NC(=O)c2cccnc2)cc1"

# Gates 1 + 2 — pure Python, no Julia required.
report = crucible.validate(spec)
assert report.ok, (report.errors, report.warnings)

# Provenance coverage + lint.
lint = crucible.lint(spec)
print(f"coverage score: {crucible.coverage_score(lint.coverage):.2f}")
for f in lint.findings:
    print(f"  {f.severity}: {f.rule}: {f.message}")

# Wire-format JSON the Julia loader can read.
json_text = spec.to_json(indent=2)

# Anything below this line uses the Julia CLI subprocess.
script = crucible.render(spec, "openmm")
result = crucible.run(spec, workdir="runs/exp1",
                      seed=42, precision="mixed")
events = crucible.events("runs/exp1")
```

## Module-mode CLI

```bash
python -m crucible templates list
python -m crucible templates init kinase_inhibitor_fep > spec.json
python -m crucible validate spec.json
python -m crucible lint spec.json --format json
python -m crucible migrate old_v01.json --target 0.3.0 > new.json
```

The Julia CLI (`crucible <subcommand>`) is the full surface — these
are pure-Python conveniences for the IR layer only.

## Cross-language consistency

The schema at [`src/spec/schema.json`](../src/spec/schema.json) is the
single source of truth. Python and Julia each load it separately:

- Julia: `JSONSchema.jl` against the file.
- Python: `jsonschema.validate` against a packaged copy.

When the schema bumps, both sides get a `register_migration` entry and
both test suites pin the new behavior. See
[`docs/POWER_USERS.md`](../docs/POWER_USERS.md) for the contributor
workflow.

## Testing

```bash
cd python
pip install -e .[dev]
pytest
```

Tests do not require Julia. Cross-language consistency tests (Python
emit → Julia load) live under `test/` in the Julia tree and are run
in CI when both runtimes are available.

## Versioning

The Python package version tracks the schema version it targets. Today:
`0.3.0`. A schema bump bumps both packages together; older Python clients
keep working against newer Julia daemons via the migration registry.
