using Test
using Crucible
import JSON3

@testset "migrate_spec_json identity for current version" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    json = read(fixture, String)
    out = migrate_spec_json(json; target="0.4.0")
    @test out == json
end

@testset "real 0.1.0 → 0.2.0 migration fills nullable v1+ fields" begin
    # An old-shape spec without ligand_smiles / membrane / lipid keys.
    obj = Dict{String,Any}(
        "schema_version" => "0.1.0",
        "system" => Dict(
            "source" => Dict("type" => "user_supplied",
                             "topology" => "x.parm7",
                             "coordinates" => "x.rst7",
                             "pdb_id" => nothing),
            "n_atoms_estimate" => 1000,
            "has_ligand" => false,
            "solvent" => Dict("model" => "TIP3P", "ions_NaCl_mM" => 150.0),
        ),
        "force_field" => Dict("protein" => "amber14sb",
                              "water"   => "TIP3P",
                              "ligand"  => "user_supplied"),
        "protocol" => [Dict("kind" => "minimize",
                            "max_iterations" => 100,
                            "tolerance_kj_mol_nm" => 10.0)],
        "observables" => Any[],
        "provenance"  => Dict{String,Any}(),
        "warnings"    => String[],
        "notes"       => "",
    )
    out = migrate_spec_json(JSON3.write(obj); target="0.2.0")
    migrated = JSON3.read(out, Dict)
    @test migrated["schema_version"] == "0.2.0"
    @test migrated["system"]["source"]["ligand_smiles"] === nothing
    @test migrated["system"]["solvent"]["membrane"] === nothing
    @test migrated["force_field"]["lipid"] === nothing
end

@testset "synthetic migration registration round-trips for unrelated versions" begin
    # Synthetic 0.4.0 → 9.9.0 transform — proves the registry mechanism
    # without colliding with the real 0.1.0 → 0.2.0 → 0.3.0 → 0.4.0
    # migration path that ships in src/spec/Migrations.jl.
    register_migration!("0.4.0", "9.9.0", function(d)
        d["test_marker"] = "migrated"
        d
    end)
    try
        fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
        json = read(fixture, String)
        out = migrate_spec_json(json; target="9.9.0")
        obj = JSON3.read(out, Dict)
        @test obj["schema_version"] == "9.9.0"
        @test obj["test_marker"] == "migrated"
    finally
        delete!(Crucible._MIGRATIONS, ("0.4.0", "9.9.0"))
    end
end

@testset "migrate_spec_json errors when no path exists" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    json = read(fixture, String)
    @test_throws ErrorException migrate_spec_json(json; target="0.0.1")
end
