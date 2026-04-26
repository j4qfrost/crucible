# examples/walkthrough.jl
#
# End-to-end walkthrough of the crucible pipeline. Uses RecordedProvider
# (no API key needed) so this script is reproducible offline.
#
# Run from the repo root:
#   julia --project examples/walkthrough.jl
#
# Steps mirror src/ui/notebook.jl:
#   1. Source paper       (NotesAdapter on a Methods excerpt)
#   2. Transpile          (RecordedProvider replays a fixture MDSpec)
#   3. Validate           (Gates 1–3: schema, semantic, loadability)
#   4. Backend choice     (Router picks OpenMM or Molly from spec features)
#   5. Cloud sizing       (Advisor recommends a GPU + cost estimate)
#   6. Render             (prepare() writes the runnable script to disk)
#   7. Transcript log     (append session to ~/.local/share/crucible/transcripts.duckdb)

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Crucible

println("=" ^ 70)
println("crucible walkthrough — RecordedProvider, no API call")
println("=" ^ 70)

# -- Step 1: Source paper -----------------------------------------------------
methods_text = read(joinpath(@__DIR__, "..", "test", "fixtures", "sample_md_methods.txt"), String)
paper = ingest(NotesAdapter(), methods_text)
println("\n[1] Paper ingested:")
println("    kind=$(paper.source_kind), bytes=$(length(paper.body_text))")

# -- Step 2: Transpile (recorded) --------------------------------------------
fixture = joinpath(@__DIR__, "..", "test", "fixtures", "recorded_anthropic_spec.json")
provider = RecordedProvider(fixture)
result = transpile(provider, paper.body_text)
println("\n[2] Transpiled via $(result.provider_name):")
println("    spec extracted = $(result.spec !== nothing)")

if result.spec === nothing
    @error "transpile failed" raw=result.raw_response
    exit(1)
end

# -- Step 3: Validate (Gates 1–3) --------------------------------------------
backends = [OpenMMBackend(), MollyBackend()]
choice = route_backend(result.spec; available=backends)
report = Crucible.run_validation(result.spec_json, result.spec, choice.backend)
println("\n[3] Validation:")
println("    backend = $(Crucible.backend_name(choice.backend))")
println("    reason  = $(choice.reason)")
println("    ok      = $(report.ok)")
for w in report.warnings; println("    warn:   $(w)"); end
for e in report.errors;   println("    error:  $(e)"); end

# -- Step 4: Cloud sizing ----------------------------------------------------
rec = Crucible.advise(result.spec; budget_hours=6.0,
                                  backend_name=Crucible.backend_name(choice.backend))
println("\n[4] Cloud sizing:")
if rec.chosen !== nothing
    c = rec.chosen
    println("    chosen  = $(c.gpu) ($(round(c.runtime_hours, digits=1)) h, \$$(round(c.on_demand_usd, digits=2)))")
    println("    reason  = $(rec.chosen_reason)")
end
for w in rec.warnings; println("    warn:   $(w)"); end

# -- Step 5: Render -----------------------------------------------------------
workdir = mktempdir(prefix="crucible-walkthrough-")
job = Crucible.prepare(choice.backend, result.spec, workdir)
println("\n[5] Rendered:")
println("    script   = $(job.script_path)")
println("    bytes    = $(job.metadata["script_size_bytes"])")
println("    workdir  = $(job.workdir)")

# -- Step 6: Transcript log ---------------------------------------------------
log_path = joinpath(tempdir(), "crucible-walkthrough-transcripts.duckdb")
isfile(log_path) && rm(log_path)
store = open_transcript_store(path=log_path)
id = log_transcript(store, paper, result; validation=report)
n = transcript_count(store)
close_transcript_store(store)
println("\n[6] Transcript logged:")
println("    id      = $(id)")
println("    db      = $(log_path)")
println("    count   = $(n)")

println("\n" * "=" ^ 70)
println("walkthrough complete; no external services were contacted.")
println("=" ^ 70)
