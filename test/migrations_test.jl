using Test
using Crucible

@testset "migrate_spec_json identity for current version" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    json = read(fixture, String)
    out = migrate_spec_json(json; target="0.1.0")
    @test out == json
end

@testset "migrate_spec_json registers + applies a v0.1.0 -> v0.2.0 transform" begin
    # Don't pollute the global table for other tests — this is a synthetic
    # demonstration migration that we unregister afterwards.
    register_migration!("0.1.0", "0.2.0", function(d)
        d["test_marker"] = "migrated"
        d
    end)
    try
        fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
        json = read(fixture, String)
        out = migrate_spec_json(json; target="0.2.0")
        import JSON3
        obj = JSON3.read(out, Dict)
        @test obj["schema_version"] == "0.2.0"
        @test obj["test_marker"] == "migrated"
    finally
        delete!(Crucible._MIGRATIONS, ("0.1.0", "0.2.0"))
    end
end

@testset "migrate_spec_json errors when no path exists" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    json = read(fixture, String)
    @test_throws ErrorException migrate_spec_json(json; target="9.9.9")
end
