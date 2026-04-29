### A Pluto.jl notebook ###
# v0.20.0

using Markdown
using InteractiveUtils

# Crucible study notebook: the five-gate validation pipeline.
#
# Run with: julia --project -e 'using Pluto; Pluto.run(notebook="examples/study_validation_gates.jl")'
#
# This notebook is a hands-on tour of how Crucible validates an MDSpec.
# You'll start with a known-good template, mutate fields, and watch the
# gates respond. Goal: by the end you can predict which gate will fire
# for any plausible spec mistake.
#
# The notebook is the third "study" example in the project; pairs with
# examples/walkthrough_v15_methods.jl (UI tour) and the cancer-MD
# walkthroughs.

macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ 11111111-1111-1111-1111-111111111111
using Crucible

# ╔═╡ 11111111-1111-1111-1111-111111111112
using PlutoUI

# ╔═╡ 11111111-1111-1111-1111-111111111113
import JSON3

# ╔═╡ 22222222-2222-2222-2222-222222222222
md"""
# Crucible study: the five-gate validation pipeline

Crucible refuses to run a spec until five gates pass in order:

1. **Schema** — JSON conforms to `schema.json` (enums, types, required fields).
2. **Semantic** — Julia-coded cross-field rules the schema can't express.
3. **Loadability** — chosen backend can actually load the topology + coords.
4. **Preview run** — short integration smoke (NaN-energy detection, etc.).
5. **User confirmation** — Pluto/CLI gate before production.

This notebook lets you mutate a starter spec one field at a time and
watch which gate catches the mutation. Goal: predict the gate before
you click "validate."
"""

# ╔═╡ 33333333-3333-3333-3333-333333333333
md"## 1. Pick a starter template"

# ╔═╡ 44444444-4444-4444-4444-444444444444
@bind template_name Select(
    [String(n) => String(n) for n in list_templates()];
    default = "vanilla",
)

# ╔═╡ 55555555-5555-5555-5555-555555555555
base_spec = get_template(Symbol(template_name))

# ╔═╡ 66666666-6666-6666-6666-666666666666
md"""
**Notes:** $(base_spec.notes)

Starter is schema-valid by construction. Click through the mutations
below and predict which gate will fire before scrolling to the
result.
"""

# ╔═╡ 77777777-7777-7777-7777-777777777777
md"## 2. Mutation 1 — bad force-field name (Gate 1)"

# ╔═╡ 88888888-8888-8888-8888-888888888888
md"""
The schema's `force_field.protein` is an enum. Try setting it to
`"Amber99"` (note the casing — the allowlist uses `:amber99sb_ildn`).
"""

# ╔═╡ 99999999-9999-9999-9999-999999999999
@bind protein_ff_input TextField(default = "Amber99")

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
mutated_spec_1_json = let
    obj = Dict{String,Any}(JSON3.read(Crucible.spec_to_json(base_spec), Dict))
    obj["force_field"]["protein"] = protein_ff_input
    JSON3.write(obj)
end

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
result_1 = Crucible.gate_schema(mutated_spec_1_json)

# ╔═╡ cccccccc-cccc-cccc-cccc-cccccccccccc
md"""
**Gate 1 (schema) result:** $(result_1.ok ? "✓ pass" : "✗ fail")

$(isempty(result_1.errors) ? "" : "**Error:** `" * first(result_1.errors) * "`")

**What happened:** the value $(repr(protein_ff_input)) is not in the
schema's `force_field.protein` enum (`amber14sb`, `amber99sb_ildn`,
`amber03`, `charmm36m`, `opls_aam`, `martini3`, `martini2_2`).
JSON Schema validation catches this before the spec ever reaches
Crucible's Julia code.
"""

# ╔═╡ dddddddd-dddd-dddd-dddd-dddddddddddd
md"## 3. Mutation 2 — NPT without barostat (Gate 2)"

# ╔═╡ eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
md"""
The schema lets you write NPT with `barostat=null` (because of how
JSON Schema's `if/then` works on optional fields), but Gate 2's
semantic rules catch the inconsistency.

Pick a stage and remove its barostat:
"""

# ╔═╡ ffffffff-ffff-ffff-ffff-ffffffffffff
@bind drop_barostat CheckBox(default = false)

# ╔═╡ a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1
mutated_spec_2 = let
    spec = base_spec
    if drop_barostat
        new_proto = copy(spec.protocol)
        for (i, s) in enumerate(new_proto)
            if s isa DynamicsStage && s.ensemble == :NPT
                new_proto[i] = DynamicsStage(
                    role = s.role, ensemble = :NPT,
                    duration_ns = s.duration_ns, dt_fs = s.dt_fs,
                    temperature_K = s.temperature_K,
                    pressure_bar = s.pressure_bar,
                    thermostat = s.thermostat,
                    barostat = nothing,            # the mutation
                    friction_ps = s.friction_ps,
                    constraints = s.constraints,
                    restraints = s.restraints,
                )
                break
            end
        end
        MDSpec(system = spec.system, force_field = spec.force_field,
               protocol = new_proto, observables = spec.observables,
               provenance = spec.provenance, warnings = spec.warnings,
               notes = spec.notes)
    else
        spec
    end
end

# ╔═╡ a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2
result_2 = Crucible.gate_semantic(mutated_spec_2)

# ╔═╡ a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3
md"""
**Gate 2 (semantic) result:** $(result_2.ok ? "✓ pass" : "✗ fail")

$(isempty(result_2.errors) ? "" : "**Error:** `" * first(result_2.errors) * "`")

**What happened:** $(drop_barostat ?
"the `_rule_npt_requires_barostat` rule fired. NPT (constant pressure) requires a barostat to actually maintain pressure. The schema permits the field to be null, but semantically it's incoherent — a real run would just sit at constant volume." :
"check the box above to drop the barostat from the first NPT stage and watch this rule fire.")
"""

# ╔═╡ a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4
md"## 4. Mutation 3 — ligand without topology (Gate 3)"

# ╔═╡ a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5
md"""
Gate 3 (loadability) is backend-specific. For ligand systems with
`source.type=:user_supplied + force_field.ligand=:user_supplied`,
the OpenMMBackend requires `source.topology` to be set. Drop it:
"""

# ╔═╡ a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6
@bind drop_topology CheckBox(default = false)

# ╔═╡ a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7
mutated_spec_3 = let
    if !drop_topology
        base_spec
    else
        # Force the spec into the "user_supplied + has_ligand + ligand_ff=user_supplied + no topology" shape.
        sys = SystemSpec(
            SystemSource(type=:user_supplied, topology=nothing,
                         coordinates="x.pdb"),
            base_spec.system.n_atoms_estimate,
            true,                                 # has_ligand
            base_spec.system.solvent,
        )
        ff = ForceFieldSpec(protein = base_spec.force_field.protein,
                            water = base_spec.force_field.water,
                            ligand = :user_supplied,
                            lipid = base_spec.force_field.lipid)
        MDSpec(system = sys, force_field = ff, protocol = base_spec.protocol,
               observables = base_spec.observables,
               provenance = base_spec.provenance,
               warnings = base_spec.warnings, notes = base_spec.notes)
    end
end

# ╔═╡ a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
result_3 = Crucible.gate_loadability(OpenMMBackend(), mutated_spec_3)

# ╔═╡ a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
md"""
**Gate 3 (loadability) result:** $(result_3.ok ? "✓ pass" : "✗ fail")

$(isempty(result_3.errors) ? "" : "**Error:** `" * first(result_3.errors) * "`")

**What happened:** $(drop_topology ?
"the OpenMMBackend's validate_spec caught the BYO-topology contract violation. With has_ligand=true + ligand_ff=:user_supplied, the user has to provide the topology because the LLM never invents FF parameters (Hard Rule #1)." :
"check the box above to drop the topology and watch the BYO-topology gate fire.")
"""

# ╔═╡ b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1
md"## 5. The whole pipeline at once"

# ╔═╡ b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2
md"""
`Crucible.run_validation(spec_json, spec, backend)` runs gates 1-3 in
sequence. If gate N fails, gate N+1 doesn't run. This is the
fail-fast invariant the project depends on.
"""

# ╔═╡ b3b3b3b3-b3b3-b3b3-b3b3-b3b3b3b3b3b3
@bind which_mutation Select(
    ["none" => "none (starter spec)",
     "schema" => "Mutation 1: bad FF name → Gate 1",
     "semantic" => "Mutation 2: NPT without barostat → Gate 2",
     "loadability" => "Mutation 3: ligand without topology → Gate 3"];
    default = "none",
)

# ╔═╡ b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4
spec_for_pipeline =
    which_mutation == "schema"      ? base_spec :  # we mutate the JSON below
    which_mutation == "semantic"    ? begin
        new_proto = copy(base_spec.protocol)
        for (i, s) in enumerate(new_proto)
            if s isa DynamicsStage && s.ensemble == :NPT
                new_proto[i] = DynamicsStage(
                    role = s.role, ensemble = :NPT,
                    duration_ns = s.duration_ns, dt_fs = s.dt_fs,
                    temperature_K = s.temperature_K,
                    pressure_bar = s.pressure_bar,
                    thermostat = s.thermostat, barostat = nothing,
                    friction_ps = s.friction_ps,
                    constraints = s.constraints, restraints = s.restraints)
                break
            end
        end
        MDSpec(system = base_spec.system, force_field = base_spec.force_field,
               protocol = new_proto, observables = base_spec.observables,
               provenance = base_spec.provenance,
               warnings = base_spec.warnings, notes = base_spec.notes)
    end :
    which_mutation == "loadability" ? mutated_spec_3 :
    base_spec

# ╔═╡ b5b5b5b5-b5b5-b5b5-b5b5-b5b5b5b5b5b5
spec_json_for_pipeline =
    which_mutation == "schema" ? mutated_spec_1_json :
    Crucible.spec_to_json(spec_for_pipeline)

# ╔═╡ b6b6b6b6-b6b6-b6b6-b6b6-b6b6b6b6b6b6
pipeline_report = try
    Crucible.run_validation(spec_json_for_pipeline, spec_for_pipeline, OpenMMBackend())
catch err
    # gate 1 failure throws if the spec is unparseable
    nothing
end

# ╔═╡ b7b7b7b7-b7b7-b7b7-b7b7-b7b7b7b7b7b7
md"""
**Pipeline result:** $(
    pipeline_report === nothing ? "✗ exception (Gate 1 unparseable)" :
    pipeline_report.ok ? "✓ all gates passed" : "✗ failed"
)

$(pipeline_report === nothing || isempty(pipeline_report.errors) ? "" :
    "**First error:** `" * first(pipeline_report.errors) * "`")

**Hard invariant:** if gate N fails, gates N+1..3 don't run. Any
errors you see come from a single gate. The CLI surfaces this with
`crucible health <spec>`.
"""

# ╔═╡ b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8
md"""
## What you've learned

By now you should be able to predict, for a plausible spec mistake,
which gate will catch it:

- **Bad enum value** (FF name, source type, observable type) → Gate 1.
- **Missing required field** (NPT without `barostat`, FEP NPT
  without `pressure_bar`) → Gate 2.
- **Backend-specific incompatibility** (BYO-topology gate, kineticsBackend
  rejecting an MD spec) → Gate 3.
- **Integrator instability** (NaN energies, force blowup) → Gate 4
  (preview run; needs the actual python subprocess; not exercised
  here).
- **Anything you'd want a human to confirm** before a 1000-GPU-hour
  run → Gate 5 (the user-confirm gate; CLI bakes this into
  `crucible run`'s validation pre-check).

The whole point is that a malicious or hallucinated spec gets caught
cheaply, before any GPU time is spent. That's the value of the
five-gate pipeline.

## Next

- `crucible health <spec>` — runs gates 1-3 + lint + coverage in
  one panel from the CLI.
- `examples/walkthrough_v15_methods.jl` — Pluto tour of all the
  v1.5 methods.
- `docs/PLAN.md` — the canonical architecture doc.
- `docs/GLOSSARY.md` — term definitions when something here was
  jargon-dense.
"""

# ╔═╡ Cell order:
# ╠═11111111-1111-1111-1111-111111111111
# ╠═11111111-1111-1111-1111-111111111112
# ╠═11111111-1111-1111-1111-111111111113
# ╟─22222222-2222-2222-2222-222222222222
# ╟─33333333-3333-3333-3333-333333333333
# ╠═44444444-4444-4444-4444-444444444444
# ╠═55555555-5555-5555-5555-555555555555
# ╟─66666666-6666-6666-6666-666666666666
# ╟─77777777-7777-7777-7777-777777777777
# ╟─88888888-8888-8888-8888-888888888888
# ╠═99999999-9999-9999-9999-999999999999
# ╠═aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# ╠═bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
# ╟─cccccccc-cccc-cccc-cccc-cccccccccccc
# ╟─dddddddd-dddd-dddd-dddd-dddddddddddd
# ╟─eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
# ╠═ffffffff-ffff-ffff-ffff-ffffffffffff
# ╠═a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1
# ╠═a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2
# ╟─a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3
# ╟─a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4
# ╟─a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5
# ╠═a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6
# ╠═a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7
# ╠═a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
# ╟─a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
# ╟─b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1
# ╟─b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2
# ╠═b3b3b3b3-b3b3-b3b3-b3b3-b3b3b3b3b3b3
# ╠═b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4
# ╠═b5b5b5b5-b5b5-b5b5-b5b5-b5b5b5b5b5b5
# ╠═b6b6b6b6-b6b6-b6b6-b6b6-b6b6b6b6b6b6
# ╟─b7b7b7b7-b7b7-b7b7-b7b7-b7b7b7b7b7b7
# ╟─b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8
