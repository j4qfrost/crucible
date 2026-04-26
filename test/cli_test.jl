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

@testset "CLI advise --format json" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    original_stdout = stdout
    rd, wr = redirect_stdout()
    try
        rc = CLI.main(String["advise", fixture, "--format", "json"])
        @test rc == 0 || rc == 3
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    out = read(rd, String)
    import JSON3
    obj = JSON3.read(out)
    @test haskey(obj, :chosen)
    @test haskey(obj, :candidates)
    @test haskey(obj, :requires_confirmation)
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

@testset "CLI info" begin
    original_stdout = stdout
    rd, wr = redirect_stdout()
    try
        rc = CLI.main(String["info"])
        @test rc == 0
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    out = read(rd, String)
    @test occursin("Backends:", out)
    @test occursin("MollyBackend", out)
    @test occursin("OpenMMBackend", out)
    @test occursin("Validation gates: 1) schema", out)
end

@testset "CLI unknown subcommand" begin
    rc = CLI.main(String["unknownsubcommand"])
    @test rc == 2
end

@testset "CLI help text lists every dispatched subcommand" begin
    # Each subcommand mentioned in HELP_TEXT must actually dispatch — i.e.
    # NOT return rc=2 (the "unknown subcommand" code). We invoke each with
    # nonsense args; we just want to confirm dispatch happens (any other
    # rc, or an error message, is fine).
    help = CLI.HELP_TEXT
    # Extract subcommand tokens from "  crucible <name> ..." lines
    subcmds = String[]
    for line in eachline(IOBuffer(help))
        m = match(r"^\s+crucible\s+(\w+)", line)
        m === nothing && continue
        push!(subcmds, String(m.captures[1]))
    end
    @test length(subcmds) >= 7

    for cmd in subcmds
        # Use a pipe to swallow any output noise
        original_stdout = stdout
        original_stderr = stderr
        rd_out, wr_out = redirect_stdout()
        rd_err, wr_err = redirect_stderr()
        rc = -1
        try
            rc = CLI.main(String[cmd])
        catch
            rc = -2
        finally
            redirect_stdout(original_stdout)
            redirect_stderr(original_stderr)
            close(wr_out); close(wr_err)
        end
        @test rc != 2  # 2 = unknown subcommand
    end
end
