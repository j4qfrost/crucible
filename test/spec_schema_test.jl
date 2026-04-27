using Test
using Crucible
import JSON3

@testset "spec / schema" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    json_str = read(fixture, String)

    # Round-trip parse
    spec = Crucible.spec_from_json(json_str)
    @test spec isa MDSpec
    @test spec.schema_version == "0.3.0"
    @test spec.system.has_ligand == true
    @test length(spec.protocol) == 4
    @test spec.protocol[1] isa Crucible.MinimizeStage
    @test spec.protocol[2] isa Crucible.DynamicsStage
    @test spec.protocol[2].ensemble == :NVT
    @test spec.protocol[3].ensemble == :NPT
    @test spec.protocol[3].barostat == :monte_carlo
    @test spec.protocol[4].role == :production

    # Required features
    feats = Crucible.required_features(spec)
    @test :npt in feats
    @test :pme in feats
    @test :ligand in feats

    # Re-emit and re-parse — schema-stable round trip
    json2 = Crucible.spec_to_json(spec)
    spec2 = Crucible.spec_from_json(json2)
    @test spec2.protocol[2].temperature_K == spec.protocol[2].temperature_K
    @test spec2.system.solvent.ions_NaCl_mM == 150.0
end

@testset "schema gate (Gate 1)" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    good = read(fixture, String)
    r = Crucible.gate_schema(good)
    @test r.ok
    @test isempty(r.errors)

    # Mutate to a bad enum
    obj = JSON3.read(good, Dict)
    obj["force_field"]["water"] = "NotARealModel"
    bad = JSON3.write(obj)
    r2 = Crucible.gate_schema(bad)
    @test !r2.ok
    @test !isempty(r2.errors)

    # Mutate to a missing required field
    obj2 = JSON3.read(good, Dict)
    delete!(obj2, "force_field")
    bad2 = JSON3.write(obj2)
    r3 = Crucible.gate_schema(bad2)
    @test !r3.ok

    # Conditional rule: NPT requires a barostat
    obj4 = JSON3.read(good, Dict)
    npt_idx = findfirst(s -> get(s, "ensemble", nothing) == "NPT", obj4["protocol"])
    if npt_idx !== nothing
        obj4["protocol"][npt_idx]["barostat"] = nothing
        bad4 = JSON3.write(obj4)
        r4 = Crucible.gate_schema(bad4)
        @test !r4.ok
    end

    # Conditional rule: NVE forbids a barostat
    obj5 = JSON3.read(good, Dict)
    obj5["protocol"][2]["ensemble"] = "NVE"
    obj5["protocol"][2]["barostat"] = "monte_carlo"
    bad5 = JSON3.write(obj5)
    r5 = Crucible.gate_schema(bad5)
    @test !r5.ok
end
