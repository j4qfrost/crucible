# Regenerate docs/IR.md from the live MDSpec types + schema.json.
#
# Run from the repo root:
#   julia --project tools/regenerate_docs.jl
#
# The output is committed to docs/IR.md so contributors can read it without
# running Julia. CI doesn't require running this — out-of-date docs are a
# review-time concern, not a build break.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using JSON3

const SCHEMA_PATH = joinpath(@__DIR__, "..", "src", "spec", "schema.json")
const OUT_PATH    = joinpath(@__DIR__, "..", "docs", "IR.md")

schema = JSON3.read(read(SCHEMA_PATH, String), Dict)

io = IOBuffer()
println(io, "# MDSpec — IR field reference\n")
println(io, "Auto-generated from `src/spec/schema.json` by `tools/regenerate_docs.jl`. Do not edit by hand.\n")
println(io, "**Schema version:** `", schema["properties"]["schema_version"]["const"], "`\n")
println(io, "## Top-level fields\n")
println(io, "| field | type | required | notes |")
println(io, "|-------|------|----------|-------|")
for (name, prop) in schema["properties"]
    typ = get(prop, "type", "")
    if isa(typ, AbstractVector); typ = join(typ, " or "); end
    if haskey(prop, "const"); typ = string("`\"", prop["const"], "\"`"); end
    required = name in get(schema, "required", String[])
    notes = get(prop, "description", "")
    println(io, "| `", name, "` | `", typ, "` | ", required ? "✓" : "—", " | ", notes, " |")
end
println(io)

function describe_object(obj_schema, prefix="")
    haskey(obj_schema, "properties") || return
    println(io, "### ", isempty(prefix) ? "fields" : prefix * " fields", "\n")
    println(io, "| field | type | required | notes |")
    println(io, "|-------|------|----------|-------|")
    for (name, prop) in obj_schema["properties"]
        typ = _format_type(prop)
        required = name in get(obj_schema, "required", String[])
        notes = _format_constraints(prop)
        println(io, "| `", name, "` | ", typ, " | ", required ? "✓" : "—", " | ", notes, " |")
    end
    println(io)
    for (name, prop) in obj_schema["properties"]
        if get(prop, "type", "") == "object"
            describe_object(prop, prefix == "" ? name : "$(prefix).$(name)")
        end
    end
end

function _format_type(p)
    if haskey(p, "enum")
        "enum: " * join("`" .* string.(p["enum"]) .* "`", ", ")
    elseif haskey(p, "const")
        "`\"$(p["const"])\"`"
    elseif haskey(p, "oneOf")
        "oneOf"
    elseif haskey(p, "type")
        t = p["type"]
        isa(t, AbstractVector) ? join(t, " or ") : "`$t`"
    else
        ""
    end
end

function _format_constraints(p)
    parts = String[]
    haskey(p, "minimum")           && push!(parts, "min=$(p["minimum"])")
    haskey(p, "maximum")           && push!(parts, "max=$(p["maximum"])")
    haskey(p, "exclusiveMinimum")  && push!(parts, "> $(p["exclusiveMinimum"])")
    haskey(p, "minItems")          && push!(parts, "minItems=$(p["minItems"])")
    haskey(p, "additionalProperties") && p["additionalProperties"] == false &&
        push!(parts, "strict (no extra fields)")
    join(parts, "; ")
end

println(io, "## `system`\n")
describe_object(schema["properties"]["system"], "system")

println(io, "## `force_field`\n")
describe_object(schema["properties"]["force_field"], "force_field")

println(io, "## `protocol` stages\n")
println(io, "Each stage is one of two shapes (oneOf):\n")
for (i, variant) in enumerate(schema["properties"]["protocol"]["items"]["oneOf"])
    kind = get(variant["properties"]["kind"], "const", "?")
    println(io, "### Stage kind: `", kind, "`\n")
    describe_object(variant)
end

println(io, "## `observables`\n")
describe_object(schema["properties"]["observables"]["items"], "observable")

println(io, "## Hard rules\n")
println(io, """
- The LLM never invents force-field parameters. The `protein`, `water`, and
  `ligand` fields are restricted to the enums above; mappings from paper-stated
  names happen at extraction time and are logged as warnings.
- Numeric fields carry units in their names (`temperature_K`, `dt_fs`,
  `duration_ns`, `pressure_bar`, `friction_ps`, `k_kj_mol_nm2`,
  `tolerance_kj_mol_nm`). The renderer is the only code that converts; the
  LLM never does unit math.
- Provenance is required for every numeric field that came from the paper.
  The `provenance` object is keyed by JSONPath-ish strings (e.g.
  `"protocol[2].temperature_K"`).
""")

mkpath(dirname(OUT_PATH))
write(OUT_PATH, String(take!(io)))
println(stderr, "wrote: ", OUT_PATH, " (", filesize(OUT_PATH), " bytes)")
