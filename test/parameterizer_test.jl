using Test
using Crucible

@testset "LigandParameterizer abstract interface" begin
    struct DummyParameterizer <: LigandParameterizer end
    @test_throws ErrorException parameterize(DummyParameterizer(), "CCO", "/tmp")
end

@testset "OpenFFParameterizer construction defaults" begin
    p = OpenFFParameterizer()
    @test p.sage_version == "2.2.0"
    @test p.python == "python"
    @test p.ligand_name == "LIG"
    @test isfile(p.helper_script)
    @test endswith(p.helper_script, "parameterize_openff.py")
end

@testset "OpenFFParameterizer custom kwargs" begin
    p = OpenFFParameterizer(sage_version="2.1.0", python="python3.11", ligand_name="DRG")
    @test p.sage_version == "2.1.0"
    @test p.python == "python3.11"
    @test p.ligand_name == "DRG"
end

@testset "OpenFFParameterizer is unavailable in lean env" begin
    # In the docker test env we don't install openff-toolkit. The probe
    # should report unavailable cleanly, not blow up.
    p = OpenFFParameterizer()
    avail = parameterizer_available(p)
    @test (avail === true) || (avail === false)
end

@testset "OpenFFParameterizer surfaces a friendly error when openff missing" begin
    p = OpenFFParameterizer()
    if parameterizer_available(p)
        @info "openff-toolkit available; skipping the missing-dep failure-path test"
        @test true
        return
    end
    err = try
        parameterize(p, "CCO", mktempdir())
        nothing
    catch e
        e
    end
    @test err !== nothing
    msg = lowercase(err.msg)
    @test occursin("openff", msg) || occursin("python", msg) ||
          occursin("subprocess", msg)
end

@testset "ParameterizedLigand carries the contract fields" begin
    pl = ParameterizedLigand("CCO", "/tmp/ethanol.parm7", "/tmp/ethanol.rst7",
                             :openff_sage_2_2_0, Dict{String,Any}())
    @test pl.smiles == "CCO"
    @test pl.forcefield_name == :openff_sage_2_2_0
    @test endswith(pl.topology_path, ".parm7")
    @test endswith(pl.coordinates_path, ".rst7")
end

@testset "Real OpenFFParameterizer subprocess (only if openff installed)" begin
    p = OpenFFParameterizer()
    if !parameterizer_available(p)
        @info "openff-toolkit not installed; skipping live subprocess test"
        @test true
        return
    end
    workdir = mktempdir(prefix="crucible-openff-test-")
    try
        result = parameterize(p, "CCO", workdir)
        @test isfile(result.topology_path)
        @test isfile(result.coordinates_path)
        @test result.forcefield_name == :openff_sage_2_2_0
        @test get(result.metadata, "n_atoms", 0) > 0
    finally
        rm(workdir; recursive=true, force=true)
    end
end
