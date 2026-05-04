# On-prem mode

How to run Crucible's LLM transpile **entirely inside your network** —
no third-party API call, no protocol leaving your infrastructure.

> **Why this page exists.** Phase A weeks 4-6 of
> [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
> identified pharma IP policies as a deal-blocker. ~50% of CADD groups
> are forbidden from sending unpublished protocols to third-party LLM
> APIs. This page is the answer. It is also Tranche-2 spend in the
> commercial plan: the `--mailto` of pharma conversations.

## TL;DR

Crucible's `LocalProvider` ([`src/llm/LocalProvider.jl`](../src/llm/LocalProvider.jl))
is an **OpenAI-API-compatible client**. Point it at any endpoint that
speaks `/v1/chat/completions` with structured-output `response_format`:

- **Ollama** (OpenAI mode)
- **vLLM**
- **llama.cpp server**
- **LM Studio**
- **OpenRouter** (still external — only useful if your IP-policy
  permits OpenRouter's listed providers)

The contract is identical to `AnthropicProvider`. Same MDSpec schema
binding. Same fail-soft behavior on parse failure. Same provenance
field. The only thing that changes is the URL.

## What "on-prem" actually means here

Two things must be true for the on-prem story to hold:

1. **The model weights live inside your network.** Pulling weights
   from Hugging Face once is fine; subsequent inference is local.
2. **The Crucible CLI invokes the local endpoint, not Anthropic.**
   Either via `LocalProvider` directly, or via a routing policy that
   never falls back to a remote provider.

We document both below so a security-review-conscious buyer can pin
the chain end-to-end.

## Quickstart — Ollama

Ollama is the simplest path because it bundles model serving + an
OpenAI-compatible API.

```bash
# Install Ollama (Linux)
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model. Recommended for MD protocol extraction:
ollama pull qwen2.5-coder:7b      # ~4 GB, runs on consumer GPU or Mac
# Or for higher accuracy at higher VRAM:
ollama pull llama3.1:70b-instruct-q4_K_M    # ~40 GB, needs A100-class

# Ollama listens on :11434 by default. Point Crucible at it:
export CRUCIBLE_LOCAL_ENDPOINT="http://localhost:11434/v1"
export CRUCIBLE_LOCAL_MODEL="qwen2.5-coder:7b"
export CRUCIBLE_LOCAL_API_KEY="ollama"   # any non-empty string

# Run a transpile:
crucible transpile --provider local --paper methods.txt
```

**Sanity check** — transpile against a known paper, validate the
output:

```bash
crucible transpile --provider local --paper methods.txt --out spec.json
crucible validate spec.json
crucible health spec.json
```

## Quickstart — vLLM (production-class)

vLLM is the right choice when you need throughput (100s of papers per
day, batch processing of an existing protocol library). It does not
ship its own model downloader.

```bash
# Install vLLM (in a Python env with CUDA + PyTorch).
pip install vllm

# Serve a model with the OpenAI-compatible API.
python -m vllm.entrypoints.openai.api_server \
    --model Qwen/Qwen2.5-Coder-7B-Instruct \
    --port 8000 \
    --gpu-memory-utilization 0.9

# Configure Crucible.
export CRUCIBLE_LOCAL_ENDPOINT="http://localhost:8000/v1"
export CRUCIBLE_LOCAL_MODEL="Qwen/Qwen2.5-Coder-7B-Instruct"
export CRUCIBLE_LOCAL_API_KEY="EMPTY"

crucible transpile --provider local --paper methods.txt
```

vLLM's structured-output support uses Outlines or `xgrammar` under the
hood; both bind the MDSpec JSON Schema correctly. If you see schema
violations in the output, upgrade vLLM (the structured-output stack
moves fast).

## Quickstart — llama.cpp (CPU-only / Apple Silicon)

For laptops or for offline single-user evaluation:

```bash
# Build llama.cpp's OpenAI-compatible server.
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp && cmake -B build && cmake --build build --target llama-server

# Run with a quantized model.
./build/bin/llama-server \
    --model models/qwen2.5-coder-7b-instruct-q4_K_M.gguf \
    --port 8080 \
    --json-schema-to-grammar

export CRUCIBLE_LOCAL_ENDPOINT="http://localhost:8080/v1"
export CRUCIBLE_LOCAL_MODEL="qwen-local"
export CRUCIBLE_LOCAL_API_KEY="EMPTY"

crucible transpile --provider local --paper methods.txt
```

Apple Silicon (M-series): `--gpu-layers 999` enables Metal acceleration.
Q4_K_M is the right quantization for 16 GB Macs; Q6_K for 32 GB.

## Model-selection guide

The MD protocol-extraction task is small-output (~1 KB JSON) but
demands precise instruction-following + structured-output fidelity.

| Model | VRAM | Accuracy (qualitative) | Throughput | Notes |
|---|---|---|---|---|
| **Qwen2.5-Coder 7B** | 8 GB | Good | High | **Recommended starter.** Best small-model schema fidelity in our tests. |
| **Qwen2.5-Coder 32B** | 24 GB | Very Good | Medium | Right call when accuracy matters more than batch size. |
| **Llama 3.1 70B** (q4) | 40 GB | Excellent | Low | Best small-output structured-extraction we've seen open-source. |
| **DeepSeek-Coder V2 16B** | 24 GB | Good | High | Strong if you need code-flavored output (irrelevant here, but mentioned for completeness). |
| **Gemma 3 9B** | 10 GB | Fair | High | Fast on consumer hardware; weaker than Qwen on schema adherence. |

When in doubt: start with Qwen2.5-Coder 7B in Ollama, run the
[`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) seed
set against it, compare against the AnthropicProvider numbers, and
graduate to a larger model only if the accuracy gap is real for your
use case.

## Hard guarantees this gives you

Per the threat model that triggers most pharma IP-policy blocks:

- **No paper text is sent to a third-party API.** The
  `LocalProvider` only knows about `CRUCIBLE_LOCAL_ENDPOINT`. It
  never falls back to Anthropic — even if `ANTHROPIC_API_KEY` is set,
  passing `--provider local` (or setting `CRUCIBLE_PROVIDER=local`)
  routes 100% to the local endpoint.
- **No telemetry from Crucible itself.** Crucible has no telemetry,
  no analytics SDK, no crash-reporting. The transpile is one HTTP
  POST to the URL you configured.
- **The rendered script is deterministic.** Given the same MDSpec,
  the OpenMM renderer emits byte-identical Python scripts. This is
  testable — see [`musings/why_subprocess_over_pythoncall.md`](../musings/why_subprocess_over_pythoncall.md).
- **No update mechanism phones home.** Crucible is `git pull` +
  `julia --project -e 'using Pkg; Pkg.instantiate()'`. No Crucible
  binary checks for updates.

## What this DOESN'T give you

To preempt the security-review questions:

- **Model weights are not audited by us.** You're trusting whoever
  trained the model (Qwen, Meta, etc.) and whoever hosts the weights
  (Hugging Face by default).
- **No air-gap guarantee for the OpenMM runtime.** OpenMM itself
  doesn't phone home, but its Conda dependencies (numpy, scipy,
  pyparsing) update from PyPI/conda-forge. Pin those if your
  threat model requires it.
- **Your paper text passes through the local LLM's logging.** Most
  servers (Ollama, vLLM, llama.cpp) log requests by default.
  Disable per-server (`OLLAMA_DEBUG=0`, vLLM's `--disable-log-stats`,
  etc.) if your audit policy requires it.

## Network-policy preflight

A short test you can hand to your IT/security team:

```bash
# 1. Block all outbound from the Crucible host except your local LLM URL.
# 2. Run:
crucible transpile --provider local --paper test_paper.txt
# 3. Verify success.
# 4. Verify no Crucible-initiated outbound connection appeared in your
#    network log.
```

If step 4 fails, file an issue at
https://github.com/j4qfrost/crucible/issues — that's a contract bug.

## Pilot scope (what a 30-day POC looks like)

For pharma-side conversations starting in Phase B Track 1:

| Phase | Days | What ships |
|---|---|---|
| **Setup** | Day 0-3 | Single-node Docker compose: Crucible + Ollama + Qwen2.5-Coder 7B. ~2-hour install on a single GPU workstation or pharma desktop. |
| **Internal benchmark** | Day 4-7 | Run Crucible against 10 of your internal protocols. Compare extracted MDSpecs against your manual baseline (ground truth). |
| **Iteration** | Day 8-21 | Two cycles of accuracy review + prompt-tuning + model swap (Qwen 7B → 32B if needed). |
| **Report** | Day 22-30 | Written eval: accuracy by protocol type, time-to-first-spec, false-positive rate, comparison against Schrödinger's per-protocol time. |
| **Decision** | Day 30 | Continue / kill / scope expansion. Fixed POC fee. |

Pricing: **$5K-$15K** for the 30-day POC. No ongoing commitment;
deliverable is the eval report. Scope expansion (custom adapter for
your internal paper format, multi-tenant deployment, etc.) is a
separate conversation.

## See also

- [`src/llm/LocalProvider.jl`](../src/llm/LocalProvider.jl) — the
  source. Read it before integrating; ~95 lines of Julia.
- [`src/llm/Provider.jl`](../src/llm/Provider.jl) — the abstract
  contract every provider satisfies (drop-in replacement).
- [`docs/HALLUCINATION_BENCHMARK.md`](HALLUCINATION_BENCHMARK.md) —
  what you should run against your local model first.
- [`docs/COMMERCIAL_VALIDATION_PLAN.md`](COMMERCIAL_VALIDATION_PLAN.md)
  Phase A weeks 4-6 — the planning context.
- [`docs/CAMPAIGN_2026Q2.md`](CAMPAIGN_2026Q2.md) — pharma-CADD
  outreach template that cites this page.
- [`docs/ON_PREM_DEPLOY_DOCKER.md`](ON_PREM_DEPLOY_DOCKER.md) —
  follow-up doc with a concrete docker-compose. (TODO: write
  alongside the first real pilot conversation.)
