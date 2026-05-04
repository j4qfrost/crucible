# How to verify a benchmark seed entry

Step-by-step for turning a `needs_verification` entry in
`python/crucible/benchmark/papers.py` into a `verified` one. The
benchmark refuses to score unverified entries — verifying is the gate
to publishing a real number, which is the gate to the
[`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) credibility wedge.

> **Time per paper:** 15-45 minutes once you have the source.
> **The bottleneck is reading the Methods section, not editing the file.**

## Pre-flight (one-time)

You need:

- Read access to the paper's full text (or at minimum the SI for
  protocol-detail papers). Paywall workarounds:
  - Your institution's library proxy
  - The `unpaywall` extension (legitimate OA copies only)
  - Author preprint on bioRxiv / arXiv (search the title)
  - Email the corresponding author — most send a reprint within a
    day, especially for academic outreach
- A Crucible Python environment installed:
  ```bash
  cd ~/Projects/crucible/python && .venv/bin/python -m pytest -q
  ```
  Should report 95+ passes. If not, run
  `~/Projects/crucible/tools/repair_manifest.sh` first.

## The 8 axes you're verifying

Per [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md):

| Axis | Where in the paper to look |
|---|---|
| `protein_ff` | Methods §"Force field" or §"System preparation" |
| `water_model` | Methods §"Solvent" — explicit word like "TIP3P" |
| `ensemble` | Methods §"MD" — production-stage row of the protocol table |
| `dt_fs` | Methods §"Integrator" — usually 1-2 fs |
| `temperature_K` | Production-stage temperature; reject Kelvin-or-Celsius confusion |
| `duration_ns` | Production length; FEP / REMD = per-window, per-replica |
| `pressure_bar` | NPT only; usually 1 bar / 1 atm (these differ slightly!) |
| `fep_lambda_count` | FEP papers only; count the λ values listed |

Three rules:

1. **`None` is a real value.** If the paper genuinely doesn't state
   a knob, leave the field as `None`. The scorer drops `None` from
   both numerator and denominator. Don't fill in a "reasonable
   default" — that's exactly the failure mode the benchmark is
   designed to catch.
2. **Cite the section.** Add a `notes` field entry like
   `"protein_ff: Methods §2.1 first paragraph"` so the next
   reviewer can audit your read.
3. **If the paper's value isn't in Crucible's allowlist,**
   document the gap (e.g. OPLS3 isn't in
   `python/crucible/spec.py:PROTEIN_FF`). Use the closest allowed
   value + a note explaining the substitution. This is a
   **schema gap to fix**, not a verification failure.

## The procedure

### 1. Find the entry

Open `python/crucible/benchmark/papers.py`. Each entry's `paper_id`
matches the slug used elsewhere — search for the slug.

### 2. Read the Methods section

Open the paper's PDF. Find:
- Methods (sometimes under Materials & Methods, Computational
  Methods, or Simulation Setup).
- For Science / Nature papers: the SI usually has the protocol
  details; the main text only summarizes.

Walk through the 8 axes in order. For each one:
- If the paper states a value, write it down.
- If the paper doesn't, write `None`.
- If the paper is ambiguous (e.g. "MD simulations were performed
  using AMBER"), pick the most-specific value from the surrounding
  paragraphs; if you can't, note the ambiguity in `notes` and use
  `None`.

### 3. Map the value into Crucible's allowlist

Force-field allowlist (from `python/crucible/spec.py`):
- `PROTEIN_FF`: amber14sb, amber99sb_ildn, amber03, charmm36m,
  opls_aam, martini3, martini2_2
- `WATER_MODELS`: TIP3P, TIP4P_EW, SPC_E, implicit_GBSA, vacuum
- `LIGAND_FF`: user_supplied, gaff2, openff_sage_2_2_0
- `LIPID_FF`: charmm36_lipid, lipid21, slipids

Common mappings:
- "ff14SB" → `amber14sb`
- "ff99SB-ILDN" → `amber99sb_ildn`
- "CHARMM36m" → `charmm36m`
- "OPLS-AA" → `opls_aam`
- "OPLS3 / OPLS3e / OPLS4" → **gap**: not in allowlist; document.
- "GAFF" → `gaff2` (close-enough for v0.3 schema)
- "OpenFF Sage 2.2" → `openff_sage_2_2_0`
- "TIP3P" → `TIP3P`
- "GBSA" → `implicit_GBSA`

### 4. Edit the entry

```python
BenchmarkEntry(
    paper_id="paper_slug",
    doi="10.xxxx/yyy",
    title="…",
    expected=ExpectedProtocol(
        protein_ff="amber14sb",       # Methods §2.1 line 4
        water_model="TIP3P",          # Methods §2.2
        ensemble="NPT",               # Methods table 1, production row
        dt_fs=2.0,                    # Methods §2.3
        temperature_K=300.0,          # Methods §2.3
        duration_ns=100.0,            # Methods §2.4 ("100 ns production")
        pressure_bar=1.0,             # Methods §2.3
        fep_lambda_count=None,        # not an FEP paper
    ),
    status="verified",                # ← flipped
    verified_by="AQN 2026-05-04",     # ← initials + ISO date
    notes="Verified against Methods §2.1-2.4. AMBER ff14SB + TIP3P, "
          "NPT 1 bar, 2 fs, 300 K, 100 ns production. Force field "
          "and water model are explicit in §2.1 first paragraph.",
)
```

### 5. Run the tests

```bash
cd ~/Projects/crucible/python && .venv/bin/python -m pytest -q \
    tests/test_benchmark.py tests/test_corpus_benchmark_bridge.py
```

If `test_seed_set_doi_format_compatible_with_find_by_doi` fails,
the DOI is malformed. Other failures usually mean the entry's
fields are out of allowed range — re-read the schema constraints
in `python/crucible/spec.py`.

### 6. Score it (optional dry run)

If you want to see how Anthropic's transpile handles this paper
*before* publishing the benchmark:

```bash
# Set up local LLM (or ANTHROPIC_API_KEY).
export ANTHROPIC_API_KEY=sk-ant-…

# Run against just this one entry.
python -m crucible benchmark run \
    --verified-only \
    --papers-dir ~/papers/methods_sections \
    --out /tmp/runs.jsonl

# Render the report.
python -m crucible benchmark report /tmp/runs.jsonl
```

Where `~/papers/methods_sections/<paper_id>.txt` is the extracted
Methods text you read. If you don't have the text in a file, the
runner falls back to the corpus-DB title+abstract (which is
meaningfully worse signal — ~50% accuracy in our calibration runs).

### 7. Commit

```bash
git add python/crucible/benchmark/papers.py
git commit -m "benchmark: verify <paper_slug> against §X-Y of Methods"
```

## How to add a brand-new entry

For papers not in the seed set:

```bash
python -m crucible benchmark add \
    --paper-id mobley_2007_alchemical \
    --doi 10.1016/j.jmb.2007.06.002 \
    --title "Predicting Absolute Ligand Binding Free Energies …"
```

This appends a `needs_verification` stub to `papers.py` with
ExpectedProtocol all `None`. Then verify it with the procedure
above.

## Common pitfalls

- **"The paper says AMBER ff03"** → that's `amber03` in our
  allowlist. Plain "AMBER" is ambiguous; mark as `None` and add a
  note.
- **"The paper says 1 atm"** → 1 atm = 1.01325 bar. Crucible's
  schema uses bar; round to 1.0 only if the paper uses bar
  explicitly. Otherwise use 1.01325 and note the unit conversion.
- **"The paper has different protocols for different systems"** →
  pick one system, lock its protocol values, name it in `notes`.
  Don't try to encode "averaged" values.
- **"The paper's FF is OPLS3 / OPLS4"** → not in our allowlist.
  Mark `protein_ff=None` for now; this is a schema-gap follow-up
  (file an issue tagged `schema-allowlist`).
- **"FEP λ-window count varies by chemical step"** → for the
  binding-FEP demo, count just the decoupling step's windows.
  Note the choice.

## See also

- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md)
  — the methodology this verifies against.
- [`python/crucible/benchmark/papers.py`](../python/crucible/benchmark/papers.py)
  — the file you'll be editing.
- [`python/crucible/spec.py`](../python/crucible/spec.py) — the
  allowlist for each field's allowed values.
- [`docs/PUNCHLIST.md`](PUNCHLIST.md) — the open verification list,
  ordered by likely-easiest-to-verify.
