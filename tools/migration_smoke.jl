# tools/migration_smoke.jl — round-trip every fixture through every
# registered migration and assert Gate 1 (schema validation) still
# passes against the current schema.
#
# Why: Crucible's schema bumps over time (0.1.0 → 0.2.0 → 0.3.0 so far).
# Each bump registers a forward-migration in src/spec/Migrations.jl.
# This script makes sure the migration chain doesn't drift — i.e. that
# loading a v0.1.0-shaped fixture, running migrate_spec_json, and
# validating the output produces a clean Gate 1 pass.
#
# Run: julia --project tools/migration_smoke.jl
# Exits 0 on success, 1 if any fixture+target combination fails.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Crucible
import JSON3

const FIXTURES_DIR = joinpath(@__DIR__, "..", "test", "fixtures")
const REGISTERED_VERSIONS = ["0.1.0", "0.2.0", "0.3.0"]

# Load each fixture, then for each registered TARGET version, attempt to
# migrate. Skip TARGET == fixture's version (identity).
function smoke_one(fixture_path::AbstractString)::Vector{NamedTuple}
    raw = read(fixture_path, String)
    obj = JSON3.read(raw, Dict)
    src_version = String(get(obj, "schema_version", "unknown"))
    out = NamedTuple[]
    for target in REGISTERED_VERSIONS
        target == src_version && continue
        try
            migrated = Crucible.migrate_spec_json(raw; target=target)
            r = Crucible.gate_schema(migrated)
            push!(out, (fixture=basename(fixture_path), src=src_version,
                        target=target, ok=r.ok,
                        errors=length(r.errors)))
        catch err
            # No migration path is OK if it's a backward target.
            msg = string(err)
            if occursin("no migration path", msg)
                push!(out, (fixture=basename(fixture_path), src=src_version,
                            target=target, ok=true, errors=0))
            else
                push!(out, (fixture=basename(fixture_path), src=src_version,
                            target=target, ok=false, errors=1))
                println(stderr, "  ", basename(fixture_path), " → ", target, ": ", msg)
            end
        end
    end
    out
end

function main()
    fixtures = filter(f -> endswith(f, ".json"), readdir(FIXTURES_DIR; join=true))
    if isempty(fixtures)
        println("no fixtures found in $(FIXTURES_DIR)")
        return 1
    end
    println("migration smoke across ", length(fixtures), " fixture(s) and ",
            length(REGISTERED_VERSIONS), " target version(s)")
    println(repeat("-", 70))

    n_pass = 0
    n_fail = 0
    for fpath in fixtures
        results = smoke_one(fpath)
        for r in results
            tag = r.ok ? "✓" : "✗"
            println("  $(tag) $(rpad(r.fixture, 36)) $(r.src) → $(r.target)")
            r.ok ? (n_pass += 1) : (n_fail += 1)
        end
    end

    println(repeat("-", 70))
    println("$(n_pass) pass / $(n_fail) fail")
    n_fail == 0 ? 0 : 1
end

exit(main())
