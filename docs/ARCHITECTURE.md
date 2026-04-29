# Architecture

This document is the visual companion to `musings/why_ir_as_contract.md`,
`musings/why_subprocess_over_pythoncall.md`, and `docs/PLAN.md`. Diagrams
are Mermaid — GitHub renders them natively. If you're reading the raw
file, the code blocks are the source.

## 1. The pipeline at a glance

What a Crucible session looks like end-to-end, from "PDF dropped on a
Pluto cell" to "GPU running a simulation":

```mermaid
flowchart LR
    Paper[("paper.pdf<br/>arXiv ID<br/>bioRxiv DOI<br/>pasted notes")]
    Adapter[Input adapter<br/>PDF / arXiv / bioRxiv / Notes]
    LLM["LLM transpile<br/><i>Anthropic / Local</i>"]
    IR{{"MDSpec JSON<br/><b>schema-validated</b>"}}
    Gates[5-gate validation]
    Renderer[Renderer<br/>OpenMM | Molly]
    Script["Rendered script<br/><i>the deliverable</i>"]
    Backend[Backend run<br/>OpenMM subprocess<br/>Molly in-process]
    Artifacts[(workdir/<br/>events.jsonl<br/>traj.dcd<br/>state.xml)]

    Paper --> Adapter --> LLM --> IR
    IR --> Gates --> Renderer --> Script --> Backend --> Artifacts
    Gates -. fails .-> User([User])
    Backend -. progress events .-> Artifacts
```

The horizontal arrow IR → Gates → Renderer is the **load-bearing
contract**: every layer to the right of IR is downstream of pure JSON,
which is why the polyglot story works
(`musings/ecosystem_alternatives.md`).

## 2. The five validation gates

Each gate is sequential and non-skippable; if N fails, N+1 doesn't run.
Gates 1-2 are pure (no LLM, no GPU). Gate 3 hits the backend.

```mermaid
flowchart TD
    JSON[Spec JSON] --> G1{Gate 1<br/>JSON Schema}
    G1 -- fail --> ER1[Reject:<br/>schema error]
    G1 -- pass --> G2{Gate 2<br/>Semantic Julia rules<br/>NPT/barostat,<br/>dt/constraints,<br/>FEP λ monotonic, …}
    G2 -- fail --> ER2[Reject:<br/>semantic error]
    G2 -- pass --> G3{Gate 3<br/>Loadability<br/>can backend load<br/>topology + coords?}
    G3 -- fail --> ER3[Reject:<br/>topology error]
    G3 -- pass --> G4{Gate 4<br/>Preview run<br/>100–1000 steps,<br/>energies finite,<br/>T within ±50 K}
    G4 -- fail --> ER4[Reject:<br/>physics error]
    G4 -- pass --> G5{Gate 5<br/>User confirm<br/>Pluto button}
    G5 -- click --> RUN[Production run]
    G5 -- skip --> ABORT[Abort cleanly]
```

Why sequencing matters: gate 4 (preview run) costs CPU/GPU minutes;
gate 1 costs microseconds. Failing fast at the cheap gates keeps the
"reject before allocating GPU time" promise.

## 3. The IR is the cross-language contract

Each row of the table below is one layer, the wire format it speaks,
and the languages that already implement (or could implement) it. This
is the architecture the polyglot story rests on:

```mermaid
flowchart TB
    subgraph Producers
      L["LLM transpile<br/>(Julia today)"]
      P["Python-builds<br/>(crucible.templates)"]
      H["Hand-edited JSON"]
    end

    subgraph Contract["Cross-language contract"]
      direction LR
      Schema["src/spec/schema.json<br/>JSON Schema 0.3.0"]
      Migrations["Migrations<br/>0.1 → 0.2 → 0.3"]
      Schema --- Migrations
    end

    subgraph Consumers
      JR["Julia renderer<br/>(OpenMM, Molly)"]
      JC["Julia CLI<br/>30 subcommands"]
      PY["Python bindings<br/>(this PR)"]
      OTHER["Future:<br/>Rust / TS / Go<br/>any JSON consumer"]
    end

    Producers --> Contract --> Consumers
```

Both Julia and Python validate against the same `schema.json`. Both
sides ship a migration registry indexed by `(from_version, to_version)`.
A schema bump is a coordinated PR that updates the file plus both
language ports.

## 4. Subprocess-as-integration-boundary

`musings/why_subprocess_over_pythoncall.md` says the integration
boundary should be at the **process layer**, not the function-call
layer. The Python bindings extend this in both directions:

```mermaid
flowchart LR
    PyUser[Python user code]
    PyIR[crucible.MDSpec<br/>pydantic IR]
    PyValidate[crucible.validate<br/>gates 1+2]
    JuliaCLI[bin/crucible<br/>Julia CLI]
    JuliaCore[Julia: IR + render +<br/>LLM transpile]
    OpenMM[python script.py<br/>→ OpenMM in subprocess]
    Molly[Molly.jl in-process]
    GPU[(GPU<br/>CUDA / HIP / OpenCL / CPU)]

    PyUser --> PyIR --> PyValidate
    PyValidate -. JSON .-> JuliaCLI
    JuliaCLI --> JuliaCore
    JuliaCore -- emit script --> OpenMM --> GPU
    JuliaCore -- in-process --> Molly --> GPU
```

Two process boundaries, both honored: Python ↔ Julia (for
render/run/serve), and Julia ↔ Python-script-running-OpenMM. Each
boundary is JSON or subprocess-stdin/stdout. No native interop, no
shared address space, no version-pinning headaches. The cost is one
fork()/exec() per operation — negligible against a multi-hour MD run.

## 5. Adoption-plan layout

How the existing pieces line up against `docs/ADOPTION_PLAN.md` Phases
0–4. This is the strategic shape, mapped onto the codebase:

```mermaid
flowchart TB
    subgraph P0["Phase 0 — Foundation (done)"]
      direction TB
      P0_IR["IR + schema + migrations"]
      P0_Gates["Gates 1–3 + lint + coverage"]
      P0_Renderers["OpenMM + Molly renderers"]
      P0_LLM["Anthropic provider"]
      P0_CLI["30-subcommand CLI"]
      P0_Pluto["Pluto walkthrough notebooks"]
    end

    subgraph P1["Phase 1 — Templates + use cases (done)"]
      P1_Cancer["3 cancer templates"]
      P1_Materials["2 materials templates"]
      P1_Protein["2 protein-engineering templates"]
      P1_Docs["docs/HOW_TO_READ + GLOSSARY"]
    end

    subgraph P2["Phase 2 — Adoption (in progress)"]
      P2a["2a: study notebook + visualization"]
      P2b["<b>2b: Python bindings (this PR)</b>"]
      P2c["2c: Web frontend (deferred)"]
    end

    subgraph P3["Phase 3 — Data flywheel"]
      P3_Transcripts["Transcript store (DuckDB)"]
      P3_Curation["Crowdsourced (paper, MDSpec) pairs"]
    end

    subgraph P4["Phase 4 — Option-3 fine-tune"]
      P4_Train["Fine-tune Qwen2.5-Coder<br/>on the corpus"]
      P4_Local["Drop-in LocalProvider"]
    end

    P0 --> P1 --> P2 --> P3 --> P4
```

Path 3 (this PR) is the load-bearing piece of Phase 2b: the IR is what
Python users most want to manipulate programmatically; the renderer
and LLM transpile remain Julia, called via subprocess.

## 6. Data flow at a single timestep

For the curious: how a single dynamics step actually flows from the
IR through the stack:

```mermaid
sequenceDiagram
    participant U as User
    participant Spec as MDSpec JSON
    participant CLI as crucible CLI
    participant R as OpenMMBackend<br/>renderer
    participant Py as Python script
    participant OM as OpenMM
    participant GPU as GPU

    U->>Spec: edit ligand_smiles
    Spec->>CLI: crucible run --backend openmm
    CLI->>R: render(spec)
    R->>Py: emit script.py
    CLI->>Py: subprocess.run(script.py)
    Py->>OM: simtk.openmm.System
    Py->>OM: integrator.step(N)
    OM->>GPU: CUDA / HIP kernel
    GPU-->>OM: forces, positions
    OM-->>Py: trajectory frame
    Py-->>CLI: stdout: "{event: progress, ns_done: 0.1}"
    CLI-->>U: live progress
    Py-->>CLI: events.jsonl + traj.dcd
```

The `events.jsonl` is structured (one JSON object per line). It's the
narrow waist that lets `crucible events` and the Pluto study notebook
both consume the same wire format. See `src/spec/Events.jl` for the
schema.

## 7. Where to read more

- `docs/PLAN.md` — operational sprint plan, milestones v0.1 / v0.2 / v0.3.
- `docs/ADOPTION_PLAN.md` — the 18-month strategic roadmap.
- `docs/HOW_TO_READ.md` — role-specific reading guides.
- `docs/POWER_USERS.md` — extending Crucible (lint rules, templates,
  schema bumps, Python bindings).
- `musings/why_ir_as_contract.md` — why the LLM emits JSON, not Python.
- `musings/why_subprocess_over_pythoncall.md` — why the integration
  boundary is the process layer.
- `musings/ecosystem_alternatives.md` — why Julia for the core, Python
  bindings for adoption.
