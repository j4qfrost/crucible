# Why not protobuf (for the IR)

Periodically the question comes up: should `MDSpec` be defined in
protobuf instead of JSON Schema? The pitch — strict schema, compact
wire format, free language bindings via codegen — sounds like it
should be a strict upgrade. This musing is the durable record of why
the answer is **no for the IR**, and the narrower places where
protobuf could still legitimately land.

## The core argument in one paragraph

Crucible's IR is consumed primarily by an LLM, secondarily by humans
(transcripts, templates, audit). Both consumers are JSON-native. The
LLM emits JSON because Anthropic's tool-use binds a JSON Schema as
`input_schema`; transcripts are JSONL so `jq`/`grep`/`cat` work; templates
are `cat`-able. Specs are kb-scale, so protobuf's wire compactness
buys nothing the workload notices. The codegen pitch ("free Python
bindings, free Rust bindings") sounds compelling until you realize the
hand-tuned ports already encode invariants codegen doesn't capture
(discriminated unions, pydantic v2 strict-enum literals, the
`provenance` sparse map). Don't switch. The IR stays JSON.

## What protobuf gets right (where the temptation comes from)

- **Strict typed schema with field numbers.** Backward-compat is
  enforced by the protocol, not by reviewer discipline.
- **Codegen for ~10 languages.** One `.proto` produces Python, Rust,
  Go, TS, Java, C++, … bindings. Theoretically free.
- **Compact wire format.** ~3-10× smaller than JSON.
- **Mature tooling.** `protoc`, `buf`, schema registries, lint rules,
  breaking-change detection.
- **gRPC integration.** If you want streaming RPC, protobuf is the
  default companion.

If you were starting a binary-protocol distributed system today, this
list is most of what you'd want. The question for Crucible is whether
those wins apply to *its* workload.

## What Crucible would lose

### LLM-friendliness

The single most-load-bearing axis. Anthropic's `tools` API binds a
JSON Schema as `input_schema`. The LLM produces structured JSON that
matches the schema. You can wrap protobuf around this — emit JSON
that maps onto a `.proto` — but then the JSON Schema is still doing
the work; protobuf is along for the ride.

OpenAI / Google / open-source LLMs are the same: structured output is
a JSON-Schema-shaped feature. Nothing in the LLM ecosystem treats
protobuf as a first-class output format. A protobuf-first IR makes
the LLM extraction *worse*, not better.

### Human readability

`crucible templates init kinase_inhibitor_fep` returns a spec the
user is meant to read, edit, and redirect. Protobuf binary is
opaque; the text encoding is verbose and less readable than JSON.
This breaks:

- the `cat`-able-template invariant
- the "user inspects what the LLM produced" flow in the Pluto UI
- the "open the JSON in an editor and tweak it" workflow
- the entire diff/intent surface (`crucible diff` works on JSON
  semantics)

JSON's lingua-franca status is itself the feature.

### The transcript flywheel

`docs/ADOPTION_PLAN.md` Phase 4 (option-3 fine-tune) collects
`(paper_text, MDSpec, user_edits, validation_outcome)` tuples in
DuckDB / JSONL for fine-tuning. JSONL transcripts are:

- pipeable through `jq`
- grep-able for specific protocol shapes
- replay-able byte-stable through migrations
- inspectable without a schema dependency

Protobuf transcripts require the `.proto` schema to read. Three years
later, when you're curating training data, the schema has bumped
five times and decoding old binary records is a chore. JSONL
ages well; binary formats don't.

### Provenance map

The `provenance: Dict[String, Provenance]` field is a sparse keyed
map (e.g. `"protocol[2].temperature_K"`). JSON object syntax
expresses this naturally. Protobuf's `map<string, Provenance>` is the
moral equivalent but:

- protobuf maps are unordered (JSON is too, but humans don't read
  protobuf so that's worse)
- map field numbers are awkward
- the JSONPath-ish keys aren't typed, which is fine in JSON but
  feels wrong in a typed schema

This is solvable, but the fact that it's solvable doesn't make
protobuf a *better* fit; just a viable one.

### The hand-port advantage

Both Python (`python/crucible/spec.py`) and Julia (`src/spec/MDSpec.jl`)
ship hand-tuned types that encode invariants codegen can't:

| Invariant                                | Codegen handles? |
|------------------------------------------|------------------|
| Discriminated `Stage` union              | Awkwardly        |
| Pydantic v2 strict `Literal[…]` enums    | No               |
| `extra="forbid"` reject-on-unknown       | Partially        |
| Default factories vs default values      | No               |
| Cross-language semantic gate equivalence | No               |
| Provenance enrichment helpers            | No               |

The Python port is ~700 LOC, the Julia port is ~700 LOC. They're
parallel by construction (the v1.24 port maps line-for-line to the
Julia source). Codegen would replace ~200 of those lines on each
side with auto-generated structs and add a build step. The other
~500 lines — validation, lint, migrations, templates, semantic rules
— don't come from codegen anyway.

### Schema-as-source-of-truth flexibility

JSON Schema is permissive. We use:

- `if/then/else` conditional rules ("if `source.type=smiles` then
  require `ligand_smiles`")
- `oneOf` discriminated unions (the `Stage` types)
- `additionalProperties: false` at every level
- `const` for the `schema_version` pin

Protobuf has discriminated `oneof`s but no first-class conditional
rules. Cross-field invariants would migrate from the schema to
the validation layer — moving complexity, not removing it.

## What Crucible would gain (the honest accounting)

- **Wire-format compactness** the workload doesn't need (specs are kb).
- **Free language bindings** for ~6 languages we don't have a stated
  need for. The two we *do* care about — Python, Julia — have
  hand-ports.
- **A build step** (`buf generate` or `protoc`) where there isn't one.
- **Backward-compat enforcement** that JSON Schema + the migration
  registry already provide.

That's the list, honestly accounted.

## What about gRPC?

A separate, narrower question. If `crucible serve` ever fronts a
typed RPC daemon (today it's HTTP+JSON for the SPA, which is fine),
protobuf + gRPC is the natural pairing. *That* could legitimately
adopt protobuf without disturbing the IR:

- `.proto` defines RPC methods + request/response wrappers
- the request body still carries `MDSpec` JSON as a `string`
  (or a wrapped `bytes` payload validated against `schema.json`)
- the IR layer doesn't change

This is the same separation as TS frontend ↔ JSON IR ↔ Julia core
today — the wire protocol between *services* can be protobuf without
the *content* being protobuf. No conflict.

## What about codegen-from-JSON-Schema?

Closer to the wins protobuf would offer, without the costs:

- `quicktype` produces TS / Go / Rust / Swift / C# / Kotlin types
  from `src/spec/schema.json` directly.
- `datamodel-code-generator` produces Pydantic models from JSON
  Schema (if we wanted to drop the hand-tuned `python/crucible/spec.py`,
  this would be the path — and the hand-tuned version exists on
  purpose, see "The hand-port advantage" above).

If a contributor wants Rust bindings, the answer is "run quicktype
on `schema.json` and ship a `crucible-rs` crate." No `.proto`
required. The schema is the contract; everything else is downstream.

## When this analysis should change

- **Specs grow into the megabyte range.** Today they're a few kb;
  if Crucible starts shipping IRs with embedded trajectories or
  large lookup tables, wire-format size becomes a real concern.
  Track if any spec exceeds ~100 kb in a transcript.
- **A typed RPC daemon becomes load-bearing.** If `crucible serve`
  needs streaming RPC across machines (not the current scope), the
  RPC envelope should be protobuf even if the body stays JSON.
  Track at the Phase 2c gate (`docs/ADOPTION_PLAN.md`).
- **LLM tooling shifts to a non-JSON structured-output format.**
  Currently no provider treats protobuf as a structured-output
  format. If this changed, the JSON-friendliness argument weakens.
  Probability: low. Track annually.
- **A protobuf-native scientific-computing community emerges.** Same
  trigger logic as `why_not_mojo.md`: the question becomes
  "follow the community" rather than "pick the right format."
  Probability: very low.

Until one of these triggers, the answer is: **JSON Schema for the
IR; reserve protobuf for the RPC envelope (if ever); generate
language types via `quicktype` from `schema.json` when needed**.

## See also

- `musings/why_ir_as_contract.md` — why the IR is JSON in the first
  place. The "LLM-friendliness" argument here is a corollary.
- `musings/why_subprocess_over_pythoncall.md` — same shape of
  argument: the integration boundary should match the workload's
  natural shape, not the most-fashionable technology.
- `musings/ecosystem_alternatives.md` — broader version: the IR
  being JSON is what makes the polyglot story tractable. Switching
  to protobuf would re-tighten the language-coupling that JSON loosens.
- `docs/ADOPTION_PLAN.md` Phase 2b/2c — Python bindings (done
  v1.24) and the future web frontend; both consume JSON IR
  natively without protobuf.
