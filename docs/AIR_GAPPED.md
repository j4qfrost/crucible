# Air-gapped Crucible

How to run Crucible with **zero outbound network** after install. For
research environments where IP-policy review forbids any external
service contact, regulated environments (pharma clinical, gov labs),
or threat models where the unpublished-protocol leak risk is more
severe than the productivity cost.

> **Companion to [`docs/ON_PREM.md`](ON_PREM.md).** That doc covers
> on-prem mode for the LLM call alone. This one extends to the
> entire stack: every install touchpoint, every runtime
> touchpoint, every dep update, every model artifact. Choose this
> doc if "on-prem" isn't strict enough for your threat model.

## TL;DR — what's the threat model?

Three increasingly-strict tiers:

| Tier | Constraint | Crucible support |
|---|---|---|
| **On-prem** | LLM call stays inside network; software install allowed | ✅ `LocalProvider` since v1.34; documented in `ON_PREM.md` |
| **Air-gapped install** | No outbound network during runtime; install via internal mirror | ✅ documented here |
| **Air-gapped runtime + audit** | Provable zero-egress; no opaque deps; deterministic outputs | ✅ documented here, with verification scripts |

If your tier is "on-prem," stop here and read `ON_PREM.md`. If it's
"air-gapped install" or stricter, continue.

## Every external touchpoint Crucible has

A complete inventory. Each row identifies a touchpoint + how to
neutralize it for an air-gapped deployment.

| Touchpoint | When | Neutralize |
|---|---|---|
| **PyPI** (Python deps) | install only | Mirror `pydantic`, `jsonschema` (+ optional: `duckdb`, `streamlit`, `anthropic`) to internal index; `pip install --index-url https://internal.pypi/...` |
| **JuliaHub** (Julia deps) | install only | Mirror via `JuliaPkgServer` (an in-network General registry mirror); set `JULIA_PKG_SERVER` env var |
| **conda-forge** (OpenMM + PDBFixer + mdtraj for the OpenMM backend) | install only | Mirror conda-forge subset; configure CondaPkg.toml channel URL or pre-build the env tarball |
| **OpenAlex** (corpus) | runtime, OPT-IN | Disable `corpus fetch` / `fetch-batch`; populate the corpus DB out-of-band from an internal bibliographic source |
| **Anthropic API** (LLM) | runtime, OPT-IN | Use `LocalOpenAIProvider` against an in-network Ollama / vLLM (see `ON_PREM.md`) |
| **Hugging Face** (model weights for `LocalOpenAIProvider`) | one-time download | Pre-download weights; `ollama pull qwen2.5-coder:7b` once, then disable HF DNS |
| **GitHub** (Pluto's CDN for notebook JS assets) | first Pluto launch | Serve via local `PlutoSliderServer.jl`; pre-download the Pluto JS bundle |
| **DOI resolvers / arXiv / bioRxiv** (input adapters) | runtime, OPT-IN | Disable adapters; supply paper text directly via `--paper FILE` |
| **AT Protocol** (`hekate` integration) | runtime, OPT-IN | `CRUCIBLE_HEKATE_DISABLE=1` (already disabled by default; double-gated behind `CRUCIBLE_HEKATE_PUBLISH_EVENTS=1`) |

**No telemetry, no auto-update, no analytics SDK** — those are
absent by design (verified by `tools/check_workspace.py` checks +
the v1.16 SECURITY.md commitment).

The `tools/baselines/egress.json` urllib count also includes
test-suite call sites, which do not reach the public internet:
`test_local_llm_live.py`'s opt-in live smoke probes
`CRUCIBLE_LOCAL_ENDPOINT` (the sanctioned in-network LLM, and is
skipped unless live tests are explicitly enabled), and
`test_corpus_openalex.py` patches `urllib.request.urlopen` to
assert the offline path.

## Install procedure (air-gapped from day 1)

### Step 1: Mirror Python deps

On a connected build host:

```bash
# In a clean venv, install with the Python extras you need.
python -m venv /tmp/build-venv
/tmp/build-venv/bin/pip install --upgrade pip
/tmp/build-venv/bin/pip download \
    --dest /tmp/wheels \
    'pydantic>=2.5' 'jsonschema>=4.20' \
    'duckdb>=1.0' 'streamlit>=1.30' \
    'anthropic>=0.40'   # only if Anthropic-routed; skip for fully local

# Tar the wheels for transport.
tar czf crucible-wheels.tar.gz -C /tmp wheels
```

On the air-gapped host:

```bash
tar xzf crucible-wheels.tar.gz
python -m venv ~/crucible-venv
~/crucible-venv/bin/pip install \
    --no-index --find-links wheels \
    -e /path/to/crucible/python[corpus,ui,llm-anthropic]
```

### Step 2: Mirror Julia deps

The simplest Julia approach: pre-build the project's `Manifest.toml`-resolved
package set into a tarball.

On a connected build host:

```bash
cd /path/to/crucible
julia --project -e 'using Pkg; Pkg.instantiate()'
# Tarball ~/.julia (the depot directory) — this has every package binary.
tar czf julia-depot.tar.gz -C "$HOME" .julia
```

On the air-gapped host:

```bash
tar xzf julia-depot.tar.gz -C "$HOME"
cd /path/to/crucible
julia --project -e 'using Crucible'   # warms the precompile cache
```

For ongoing maintenance, set up a `JuliaPkgServer` mirror inside
your network — see [JuliaPkgServer docs](https://github.com/JuliaPackaging/PkgServer.jl).

### Step 3: Mirror the OpenMM Python env

The OpenMM backend shells out to a Python script that imports
`openmm`. The Python env carrying OpenMM is conda-managed via
`CondaPkg.toml`. Two options:

**(a) Pre-built tarball.** On a connected host, install the env once,
then transport:

```bash
# In the conda env Crucible uses:
mamba create -n crucible-openmm openmm pdbfixer mdtraj -c conda-forge
conda pack -n crucible-openmm -o crucible-openmm.tar.gz
```

On the air-gapped host:

```bash
mkdir -p ~/envs/crucible-openmm
tar xzf crucible-openmm.tar.gz -C ~/envs/crucible-openmm
~/envs/crucible-openmm/bin/python -c 'import openmm; print(openmm.__version__)'

# Point Crucible at this env:
export CRUCIBLE_OPENMM_PYTHON=~/envs/crucible-openmm/bin/python
```

**(b) Internal conda-forge mirror.** Configure `CondaPkg.toml` to
point at your mirror; CondaPkg.jl will use it transparently.

### Step 4: Mirror the LLM model weights

For the `LocalOpenAIProvider` path:

```bash
# On a connected host:
ollama pull qwen2.5-coder:7b
# Find the model dir (default: ~/.ollama/models)
tar czf qwen-weights.tar.gz -C ~/.ollama/models .

# On the air-gapped host:
mkdir -p ~/.ollama/models
tar xzf qwen-weights.tar.gz -C ~/.ollama/models
ollama serve     # then `crucible transpile --provider local`
```

Alternative: vLLM with weights from an internal model registry
(MLflow, MinIO, etc.).

## Runtime procedure (air-gapped after install)

### Configuration

```bash
# Force the local LLM path; never touch Anthropic.
export CRUCIBLE_PROVIDER=local
export CRUCIBLE_LOCAL_ENDPOINT=http://localhost:11434/v1
export CRUCIBLE_LOCAL_MODEL=qwen2.5-coder:7b

# Disable corpus fetch (OpenAlex outbound).
unset CRUCIBLE_OPENALEX_EMAIL  # belt-and-braces; the polite-pool email is opt-in

# Disable AT Protocol publishing (already off by default; explicit).
export CRUCIBLE_HEKATE_DISABLE=1

# Disable Pluto telemetry (Pluto.jl honors this).
export PLUTO_NO_TELEMETRY=1

# Pin the Crucible binary path in case PATH is wonky.
export CRUCIBLE_BIN=/path/to/crucible/bin/crucible
```

### Verify zero-egress

A network-policy preflight + audit:

```bash
# Block all outbound from the Crucible host except your local LLM URL.
# Then run:
crucible doctor
crucible transpile --paper test.txt --provider local
crucible health spec.json
crucible render spec.json --backend openmm > run.py

# Verify zero outbound to anything except 127.0.0.1:11434:
sudo tcpdump -i any -n -c 100 'not host 127.0.0.1'
# Expected: zero packets captured during the above commands.
```

If anything fires that isn't to your local LLM endpoint, file an
issue at https://github.com/j4qfrost/crucible/issues — that's a
contract bug.

## What's deterministic vs. not

For an audit-quality reproduction, you need the *runtime* to be
deterministic. Crucible's commitments:

| Layer | Deterministic? |
|---|---|
| LLM transpile | NO (LLM is stochastic; provenance + benchmark are how we audit) |
| Schema validation | YES (deterministic; exit code is the contract) |
| Renderer (MDSpec → script) | YES (byte-stable for a given MDSpec; pinned by golden tests) |
| OpenMM run | DETERMINISTIC if `CRUCIBLE_SEED` is set; otherwise non-deterministic |
| Corpus DB | YES (DuckDB is single-writer; no time-based fields beyond `fetched_at`) |
| Benchmark scoring | YES (no LLM calls; pure Python) |
| Trends / report | YES (one-shot read of the runs DB) |

If your audit chain requires bit-for-bit reproducibility, set
`CRUCIBLE_SEED` and `CRUCIBLE_PRECISION=double` for OpenMM runs.
The benchmark + corpus + report tiers are deterministic regardless.

## Updating an air-gapped install

The hard case: applying a Crucible patch (or schema bump) to an
air-gapped system. Three paths:

### Path A: rebuild the tarballs

For each release:
1. On the connected build host, `git pull && julia --project -e
   'Pkg.update()'` + `pip install --upgrade -e python`.
2. Re-tarball the Python wheels + Julia depot + OpenMM env.
3. Transport + extract on the air-gapped side.

This is the simplest but most-disruptive path. Use it for major
schema bumps (v1.x → v2.x).

### Path B: incremental patch over rsync

For small changes:
1. `git pull` on the connected host.
2. `rsync` the Crucible source tree to the air-gapped host.
3. Run `tools/check_workspace.py` on the air-gapped side; if green,
   the deps didn't change — no tarball update needed.
4. Run the migration smoke (`tools/migration_smoke.jl`) to verify
   any schema-bump migrations apply cleanly.

This works for ~80% of patches (anything that doesn't add a new
Python or Julia dep).

### Path C: maintain a fork

If the air-gapped environment can't accept upstream Crucible at
all (regulatory pin), maintain a fork in your internal git. Cherry-
pick patches as needed; run the workspace checks on every PR. This
is the highest-fidelity path; also the highest maintenance cost.

## Verification scripts

Crucible ships these to support air-gapped audits:

- [`tools/audit_offline.sh`](../tools/audit_offline.sh) — composite
  one-shot gate. Runs the workspace check (incl. egress baseline),
  the egress inventory dump, and both `crucible doctor --offline`
  surfaces (Python + Julia). Exit code = number of failed steps.
  Use `--skip-julia` on Python-only CI; `--quiet` to suppress
  per-step banners.
- [`tools/check_workspace.py`](../tools/check_workspace.py) — 8
  invariants including the schema-version drift check, manifest
  format, and the **egress baseline** (any new outbound-network
  call site fails until `tools/baselines/egress.json` is
  deliberately bumped + this doc updated). Runs offline.
- [`tools/inventory_egress.py`](../tools/inventory_egress.py) —
  static-analysis dump of every outbound-network call site,
  grouped by category (urllib / anthropic_sdk / julia_HTTP / …).
  No network.
- `python -m crucible doctor --offline` and the Julia
  `crucible doctor --offline` — runtime air-gap audits: error on
  `ANTHROPIC_API_KEY` / `CRUCIBLE_HEKATE_PUBLISH_EVENTS=1`; warn
  on `CRUCIBLE_OPENALEX_EMAIL` / non-private-net
  `CRUCIBLE_LOCAL_ENDPOINT`.
- [`tools/check_doc_links.py`](../tools/check_doc_links.py) — pure
  filesystem; no network.
- [`tools/migration_smoke.jl`](../tools/migration_smoke.jl) — walks
  every fixture through every registered migration target. No
  network.
- [`tools/cross_lang_roundtrip.jl`](../tools/cross_lang_roundtrip.jl)
  — confirms Python emit → Julia parse → Python emit yields
  byte-identical output. No network.

A useful pattern: run `tools/audit_offline.sh` on your air-gapped
CI as the single composite gate. Add the network-policy preflight
(`tcpdump`-based, see above) as a separate audit step that
exercises the runtime under load.

## When this isn't enough

The single most important threat-model question this doc *doesn't*
answer: **what about the model weights themselves?** If your
threat model includes "the open-weights model was poisoned at
training time and emits MDSpec values that look right but are
subtly biased," air-gapping the runtime doesn't help — you've
already imported the threat. Mitigations:

- Run the [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md)
  against the model on your verified-against-Methods seed set
  before promoting. Compare to a reference run on a different
  base model.
- Audit the per-axis accuracy table for systematic biases (e.g.
  consistent wrong-FF picks for a specific paper class).
- For high-stakes work, use Crucible's provenance system: every
  numeric the model emits is tagged `paper` / `paper_default` /
  `assumed`. Manually audit the `assumed` fields before running.

The provenance system is the load-bearing trust mechanism. The
air-gap is the perimeter; the benchmark is the audit.

## See also

- [`docs/ON_PREM.md`](ON_PREM.md) — the lighter-touch on-prem
  mode (this doc's prerequisite reading).
- [`docs/USER_PROFILE_PHARMA_POC.md`](USER_PROFILE_PHARMA_POC.md)
  — the audience this doc is most-often written for.
- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md)
  — the empirical-trust mechanism that complements the air-gap.
- [`musings/why_subprocess_over_pythoncall.md`](../musings/why_subprocess_over_pythoncall.md)
  — why the subprocess boundary makes air-gapping the OpenMM
  runtime tractable (vs. PythonCall.jl which would couple them).
- [`SECURITY.md`](../SECURITY.md) — the project's general
  security commitments.
