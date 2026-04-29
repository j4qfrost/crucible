# Why subprocess > PythonCall (architecture decision)

A v0 design decision the project keeps reaffirming: when Crucible needs
to interoperate with a Python library (OpenMM, OpenFF Toolkit, PDBFixer,
mdtraj, openmmtools), it shells out to `python script.py` rather than
embedding Python in the Julia process via `PythonCall.jl` + `CondaPkg`.

The original v0 plan called for PythonCall. We never shipped it. Every
time we've come back to this decision — first when wiring the
OpenMMBackend, then for the OpenFFParameterizer, then for the
SMIRNOFFTemplateGenerator path inside `:protein_ligand` — subprocess
has won. This note is so the next contributor doesn't waste a week
re-deriving it.

## What we considered

### Option A: PythonCall.jl + CondaPkg (the original plan)

In-process Python interop. Add `PythonCall` and `CondaPkg` to
`Project.toml`; in `OpenMMBackend.run!`, do something like:

```julia
using PythonCall
const openmm = pyimport("openmm")
function run!(b::OpenMMBackend, job::PreparedJob; ...)
    forcefield = openmm.app.ForceField(...)
    sim = openmm.app.Simulation(...)
    sim.step(n_steps)
end
```

Strengths: zero-overhead value handoff (no JSON or file roundtrip),
direct error propagation (a Python exception becomes a Julia
exception), can stream progress back to Julia in real time.

### Option B: subprocess (what we shipped)

The renderer emits a complete, runnable `run_openmm.py` script.
`run!` shells out to `python run_openmm.py` and tails its stdout.
The script is hermetic: anyone can run it without Crucible installed.

## Why subprocess won

### 1. The script is a deliverable, not an artifact

The single most-important property of Crucible's output is that **the
rendered script is what the user is going to inspect, share, and
publish.** A senior researcher reviewing the IR's correctness wants to
look at the Python they'd actually run, not at a Julia function that
happens to call `pyimport`.

PythonCall makes the integration *easier* but the deliverable
*harder* — the user can't just check `run_openmm.py` into their
notebook + run it; the actual logic lives in Crucible.

### 2. Optional dependencies stay optional

A user who only wants the IR + LLM layer (transpile a paper, get a
spec, hand it to a collaborator who will run it elsewhere) doesn't
need OpenMM installed. With subprocess, `Pkg.add("Crucible")` works
on any machine; `python` and the optional deps come into play only
at execution time.

With PythonCall, OpenMM would be a transitive build-time dependency,
because CondaPkg solves the conda environment when the package
loads. That makes:
- Crucible's docker test loop need OpenMM (currently it doesn't —
  `Pkg.test()` runs in `julia:1.10` with zero Python).
- The `crucible-` shell wrapper need a working conda env (today it
  doesn't).
- CI cycles 5-10x slower (CondaPkg solves on every cold cache).

### 3. The integration boundary is the LLM, not the runtime

Crucible's IR-first design means the contract is **MDSpec ↔ JSON ↔
Python script.** The Python script is the leaf of the tree. We don't
need to *introspect* OpenMM's runtime state from Julia — we just need
to render a script and check whether it ran. Subprocess maps cleanly
onto that.

If we were doing live, interactive simulation control (live
visualization, real-time parameter twiddling), PythonCall would be
the right call. Crucible isn't that product.

### 4. Multi-platform handoff is trivial

The user runs the rendered script on whatever Python they have:
their workstation's conda, an HPC cluster's module, a Singularity
image, an AWS Deep Learning AMI. Crucible doesn't care.

With PythonCall + CondaPkg, the runtime is whatever conda environment
CondaPkg solved at install time. Cross-machine portability gets harder.

### 5. Failures are observable, not opaque

A Python exception in a subprocess is a stack trace in stdout. We can
capture it, display it, log it to the transcript store. The user can
copy-paste it into a debugger.

A Python exception bubbled through PythonCall is a `Py` object that
needs `pyconvert(String, ...)` and a careful catch — and the user is
debugging a Julia/Python interop problem that doesn't exist if the
Python ran in its own process.

## Where the cost shows up

Subprocess isn't free. The costs we've absorbed:

- **Startup latency.** Python interpreter takes ~200ms to boot.
  Negligible for a 100ns MD simulation that takes hours; annoying
  for unit tests, which we mitigate by NOT actually running the
  scripts in offline tests (we test rendering only).
- **Value handoff via files.** When the OpenFFParameterizer produces
  a `.parm7`, OpenMMBackend reads it from disk in a separate process.
  In PythonCall this would be an in-memory dict. The disk roundtrip
  is real but trivial (~ms for a small parameter file).
- **No live progress reporting back to Julia.** We can `tail -f` the
  script's stdout but we can't `getstate()` the simulation context.
  v1 doesn't need that; v2's web UI might, and at that point we
  could selectively add PythonCall just for the live-state path.

## The rule

If a feature genuinely needs to pull values out of a running Python
context — not just observe stdout, not just orchestrate via files —
then PythonCall is on the table for **that one feature**, not for the
whole backend. Default for everything else: subprocess.

The OpenFFParameterizer (`src/ligand/Parameterizer.jl` + `parameterize_openff.py`)
is the canonical example. The renderer-side OpenMM scripts are another.
The metadynamics + REMD additions all followed this pattern. Don't
relitigate it without a concrete case where subprocess can't serve.
