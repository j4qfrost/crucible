using Test
using Crucible

@testset "LigandParameterizer abstract interface" begin
    # The bare abstract type doesn't implement parameterize
    struct DummyParameterizer <: LigandParameterizer end
    @test_throws ErrorException parameterize(DummyParameterizer(), "CCO", "/tmp")
end

@testset "OpenFFParameterizer is a v1 stub" begin
    p = OpenFFParameterizer()
    @test p.sage_version == "2.2.0"

    # Stub should throw a helpful error explaining how to unblock
    err = try
        parameterize(p, "CCO", mktempdir())
        nothing
    catch e
        e
    end
    @test err !== nothing
    @test occursin("v1 stub", err.msg)
    @test occursin("openff-toolkit", err.msg)
end

@testset "ParameterizedLigand carries the contract fields" begin
    pl = ParameterizedLigand("CCO", "/tmp/ethanol.parm7", "/tmp/ethanol.rst7",
                             :openff_sage_2_2_0, Dict{String,Any}())
    @test pl.smiles == "CCO"
    @test pl.forcefield_name == :openff_sage_2_2_0
    @test endswith(pl.topology_path, ".parm7")
    @test endswith(pl.coordinates_path, ".rst7")
end
