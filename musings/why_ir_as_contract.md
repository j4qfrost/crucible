# Why the IR is the contract (architecture decision)

The IR-first design is the most-important call Crucible makes. If you
read one architecture note about this project, this is the one.

## The choice we made

The LLM emits **structured JSON conforming to `schema.json`**, not
runnable Python (or Julia, or LAMMPS input files, or anything else
executable). That JSON is an `MDSpec` — types defined in
`src/spec/MDSpec.jl`. Renderers translate `MDSpec → script`, but no
one translates `paper → script` directly.

```
                  classical                          rendering
   paper text ─────────────► MDSpec (JSON) ─────────────► run_openmm.py
                  ↑LLM                       ↑Crucible              ↑user
                  ↑contract: schema.json
```

Everything downstream — validation gates, cloud advisor, web frontend,
transcript store, fine-tune flywheel — operates on the IR, not on the
script. The script is a render target, not a source of truth.

## What we considered

### Option A: LLM emits runnable Python (the obvious choice)

Tell Claude "extract the methods section and emit an OpenMM script."
This is what most demo papers do. The output is immediately runnable.

Why we rejected it:

1. **Hallucination surface is unbounded.** "OpenMM script" is the
   space of all Python text. A 1% hallucination rate is catastrophic
   when the wrong number is `temperature_K = 30` instead of `300`.
   We can't validate "is this a correct OpenMM script" without
   actually running it.

2. **Multiple backends is a copy-paste tax.** If the user wants to
   route a 5k-atom CG system to Molly instead of OpenMM, the LLM has
   to re-emit the protocol in Julia. We'd be asking the LLM to be
   fluent in two simulation engines simultaneously.

3. **No structural validation.** Schema validation is impossible
   without a schema. Semantic checks (NPT requires a barostat,
   dt > 5 fs is rejected, …) require parsing the script — which means
   building a Python AST analyzer. JSON validation is one library
   call.

4. **Provenance becomes inline comments.** Every numeric field in the
   spec needs an audit trail ("this came from Methods §2.3"). With a
   structured IR, that's a Provenance struct. With a Python script,
   it's `temperature = 300  # from Methods §2.3` — and the LLM
   regularly drops or rewords the comment. We can't compare comments
   semantically.

5. **The fine-tune flywheel goes from feasible to nightmare.**
   Curating `(paper, MDSpec_json)` pairs is straightforward — pairs
   are deterministic, validate against schema, diffable. Curating
   `(paper, runnable_script)` pairs requires running every script to
   know if it's correct. The training-data labeling cost goes from
   "JSON Schema validator" to "GPU farm."

### Option B: LLM emits IR, Crucible renders (what we shipped)

The LLM's output space is constrained to the schema's enums + numeric
ranges. JSON Schema validation catches most hallucinations cheaply
(Gate 1). Semantic rules in pure Julia catch the rest (Gate 2).
Multi-backend rendering becomes "loop over a `Vector{Stage}`," not
"ask the LLM in another language."

Strengths and where they bite us, in order of impact:

1. **Hallucination collapses to a finite enum/numeric space.** If
   the LLM tries to emit `force_field.protein = "Amber99"`, schema
   rejects it. The LLM cannot output "Amber99" because the prompt's
   enum list doesn't include it. (We log a warning if the paper says
   "Amber99" and we map it to `:amber99sb_ildn`.)

2. **Schema versions are a reproducibility primitive.** A spec from
   2026-04-25 is a v0.1.0 spec; we have a forward-migration to today's
   v0.3.0. Old transcripts replay cleanly. Old simulations replay
   bit-identically. (Compare: a Python script from 2024 against
   OpenMM 8.x might break on every API rename.)

3. **Multi-backend is free.** OpenMM and Molly both render from the
   same `MDSpec`. We added FEP, REMD, metadynamics, membrane, Martini,
   constph by adding stage types and renderer cases — never by
   re-prompting.

4. **The web UI, the CLI, and the transcript store all share one
   serialization.** `JSON3.write(spec)` is the canonical wire form.
   No custom protocol per consumer.

5. **Fine-tune training data is JSON pairs.** A 1k-pair corpus is
   curatable by hand. Each pair is a JSON object that round-trips
   through `spec_from_json + spec_to_json` deterministically. JSON
   Schema validity is the cheapest correctness signal we have.

The cost is an extra layer (the LLM ↔ schema mapping). The benefit is
that everything else gets simpler. After ~12 months of iteration the
balance is well past obvious.

## What this commits us to

If you find yourself wanting to do something IR-bypassing — direct
script generation, side-channel from the LLM to the renderer, an
"unstructured" provider that returns raw Python — stop and read this
note.

The bypass typically presents as:
- "Sometimes the paper says something the IR can't represent (a
  custom integrator, a CV that's not in the metad list, …) — let's
  let the LLM emit raw OpenMM for that."
- "The schema is too strict; we should allow `additionalProperties:
  true` so the LLM has wiggle room."
- "Why don't we just expose `Simulation.step(n)` to the LLM so it
  can write the run loop?"

Each of those is real, valid feedback. The right answer is **extend
the IR**: add the new stage type, add the new CV kind, add the new
parameter as an optional field with a migration. The wrong answer
is to widen the contract.

The constph + Martini scaffolding (see `docs/PLAN.md`) is the canonical
example of doing this right. Both have NotImplementedError stubs in
the renderer because we don't have a runtime yet — but the IR shape
is committed, validation runs, and a future runtime drops in without
breaking the contract.

## The exception that proves the rule

There is one path where Crucible bypasses the IR: the
`AnthropicProvider`'s `raw_response` field. We capture the LLM's
literal output for audit purposes, even when it doesn't validate.
That data goes into the transcript store. It's NOT consumed by any
downstream code — only humans look at it during corpus review.

## TL;DR

- LLM outputs MDSpec JSON, never raw scripts.
- Crucible renders MDSpec to scripts.
- Validation, advisor, web, transcript store, fine-tune all read
  MDSpec.
- New features = extend IR + register migration + add renderer case.
- Don't bypass the IR even when it would be locally convenient. It
  always loses globally.
