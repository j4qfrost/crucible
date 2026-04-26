using Test
using Crucible

# CLI smoke tests — exercise the dispatcher directly without the bash wrapper.

include(joinpath(@__DIR__, "..", "src", "cli", "CLI.jl"))

@testset "CLI help" begin
    @test CLI.main(String["help"]) == 0
    @test CLI.main(String["--help"]) == 0
end

@testset "CLI transpile + validate via RecordedProvider" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    out_path = tempname() * ".json"
    rc = CLI.main(String["transpile", "notes", "ignored",
                          "--provider", "recorded:" * fixture,
                          "--out", out_path])
    @test rc == 0
    @test isfile(out_path)
    @test filesize(out_path) > 100

    rc = CLI.main(String["validate", out_path, "--backend", "openmm"])
    @test rc == 0
    rm(out_path; force=true)
end

@testset "CLI render to disk" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    spec_path = tempname() * ".json"
    cp(fixture, spec_path)
    out_path = tempname() * ".py"
    rc = CLI.main(String["render", spec_path, "--backend", "openmm", "--out", out_path])
    @test rc == 0
    @test isfile(out_path)
    txt = read(out_path, String)
    @test occursin("from openmm", txt)
    rm(spec_path; force=true)
    rm(out_path; force=true)
end

@testset "CLI advise" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    rc = CLI.main(String["advise", fixture, "--budget-hours", "6"])
    @test rc == 0 || rc == 3   # 3 means cost-confirmation required (acceptable for the kinase spec)
end

@testset "CLI summarize emits Markdown" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    # Capture stdout
    original_stdout = stdout
    rd, wr = redirect_stdout()
    try
        rc = CLI.main(String["summarize", fixture])
        @test rc == 0
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    out = read(rd, String)
    @test occursin("# MDSpec", out)
    @test occursin("## Force field", out)
    @test occursin("amber14sb", out)
end

@testset "CLI unknown subcommand" begin
    rc = CLI.main(String["unknownsubcommand"])
    @test rc == 2
end
