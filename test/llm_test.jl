using Test
using Crucible

@testset "RecordedProvider deterministic round-trip" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    @assert isfile(fixture)
    p = RecordedProvider(fixture)
    paper = ingest(NotesAdapter(),
        read(joinpath(@__DIR__, "fixtures", "sample_md_methods.txt"), String))

    result = transpile(p, paper.body_text)
    @test result.spec !== nothing
    @test result.provider_name == :recorded

    # The recorded fixture is the kinase MD spec — verify expected paper-derived
    # values landed in the IR. These mirror what AnthropicProvider should emit
    # from the same Methods text.
    spec = result.spec
    @test spec.force_field.protein == :amber14sb
    @test spec.force_field.water == :TIP3P

    # Find the production stage and verify temperature
    prod_stages = [s for s in spec.protocol if s isa Crucible.DynamicsStage && s.role == :production]
    @test !isempty(prod_stages)
    @test prod_stages[1].temperature_K == 300.0
    @test prod_stages[1].dt_fs == 2.0

    # End-to-end: validate against a real backend
    backends = [OpenMMBackend(), MollyBackend()]
    choice = Crucible.route_backend(spec; available=backends)
    @test Crucible.backend_name(choice.backend) == :openmm   # solvated + ligand
    report = Crucible.run_validation(result.spec_json, spec, choice.backend)
    @test report.ok
end

@testset "AnthropicProvider no-op without API key" begin
    delete!(ENV, "ANTHROPIC_API_KEY")
    p = AnthropicProvider()
    result = transpile(p, "any paper text")
    @test result.spec === nothing
    @test occursin("ANTHROPIC_API_KEY not set", result.raw_response)
end

@testset "live Anthropic smoke (opt-in)" begin
    if get(ENV, "CRUCIBLE_RUN_ANTHROPIC", "0") != "1" || !haskey(ENV, "ANTHROPIC_API_KEY")
        @info "skipping live Anthropic smoke; set CRUCIBLE_RUN_ANTHROPIC=1 + ANTHROPIC_API_KEY"
        @test true
        return
    end
    methods_txt = read(joinpath(@__DIR__, "fixtures", "sample_md_methods.txt"), String)
    p = AnthropicProvider()
    result = transpile(p, methods_txt)
    @test result.spec !== nothing
    spec = result.spec
    # Methods explicitly state ff14SB + TIP3P + 300 K + 2 fs + NPT + 100 ns
    @test spec.force_field.protein == :amber14sb
    @test spec.force_field.water == :TIP3P
    @test any(s isa Crucible.DynamicsStage && s.temperature_K == 300.0 for s in spec.protocol)
    @test any(s isa Crucible.DynamicsStage && s.dt_fs == 2.0 for s in spec.protocol)
end

@testset "TranscriptStore append + count" begin
    db_path = tempname() * ".duckdb"
    store = open_transcript_store(path=db_path)
    @test transcript_count(store) == 0

    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    p = RecordedProvider(fixture)
    paper = ingest(NotesAdapter(), "test methods text")
    result = transpile(p, paper.body_text)

    backends = [OpenMMBackend(), MollyBackend()]
    choice = Crucible.route_backend(result.spec; available=backends)
    report = Crucible.run_validation(result.spec_json, result.spec, choice.backend)

    id = log_transcript(store, paper, result; validation=report)
    @test id !== nothing
    @test transcript_count(store) == 1

    # Append a second
    log_transcript(store, paper, result; validation=report)
    @test transcript_count(store) == 2

    # JSONL export
    jsonl_path = tempname() * ".jsonl"
    n_exported = export_transcripts_jsonl(store, jsonl_path)
    @test n_exported == 2
    @test isfile(jsonl_path)
    lines = readlines(jsonl_path)
    @test length(lines) == 2
    # Each line must parse as JSON
    import JSON3
    for line in lines
        obj = JSON3.read(line)
        @test haskey(obj, :paper_text)
        @test haskey(obj, :spec_json)
        @test haskey(obj, :validation_ok)
    end
    rm(jsonl_path; force=true)

    close_transcript_store(store)
    @test isfile(db_path)
    rm(db_path; force=true)
end
