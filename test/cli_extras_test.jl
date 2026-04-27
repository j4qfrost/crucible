using Test
using Crucible

# Re-include CLI without `using` (the file is also pulled in by cli_test;
# Julia warns about module replacement which is harmless but noisy).
isdefined(Main, :CLI) || include(joinpath(@__DIR__, "..", "src", "cli", "CLI.jl"))

@testset "cmd_fmt pretty-prints a spec" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    original_stdout = stdout
    rd, wr = redirect_stdout()
    rc = nothing
    try
        rc = CLI.main(String["fmt", fixture])
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    @test rc == 0
    out = read(rd, String)
    # Pretty output has newlines + indentation that the compact form lacks
    @test count('\n', out) > 5
    parsed = Crucible.spec_from_json(out)
    @test parsed.schema_version == "0.2.0"
end

@testset "cmd_fmt --in-place writes back" begin
    src = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    tmp = tempname() * ".json"
    cp(src, tmp)
    try
        original_stderr = stderr
        rd_e, wr_e = redirect_stderr()
        rc = nothing
        try
            rc = CLI.main(String["fmt", tmp, "--in-place"])
        finally
            redirect_stderr(original_stderr)
            close(wr_e)
        end
        @test rc == 0
        body = read(tmp, String)
        @test count('\n', body) > 5
        @test Crucible.gate_schema(body).ok
    finally
        rm(tmp; force=true)
    end
end

@testset "cmd_trajstat reports counts on a synthetic workdir" begin
    workdir = mktempdir(prefix="crucible-trajstat-")
    try
        write(joinpath(workdir, "spec.json"),
              Crucible.spec_to_json(Crucible.get_template(:vanilla)))
        write(joinpath(workdir, "stage_traj.dcd"), "fakebytes")
        write(joinpath(workdir, "stage.log"), "Energy: -100\n")
        write(joinpath(workdir, "rmsd.csv"), "frame,rmsd\n")
        write(joinpath(workdir, "run_openmm.py"), "# script\n")

        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["trajstat", workdir])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        out = read(rd, String)
        @test occursin("trajectory:", out)
        @test occursin("timeseries:", out)
        @test occursin("spec:", out)
        @test occursin("script:", out)
        @test occursin("stage_traj.dcd", out)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_trajstat returns rc=1 on a bad path" begin
    original_stderr = stderr
    rd_e, wr_e = redirect_stderr()
    rc = nothing
    try
        rc = CLI.main(String["trajstat", "/nonexistent/path/qqq"])
    finally
        redirect_stderr(original_stderr)
        close(wr_e)
    end
    @test rc == 1
end
