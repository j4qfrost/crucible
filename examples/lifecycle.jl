# examples/lifecycle.jl
#
# End-to-end demo of the option-3 fine-tune flywheel:
#
#   1. Ingest a paper (Methods text)
#   2. Transpile with RecordedProvider (stand-in for live Anthropic)
#   3. Log the LLM-emitted spec to TranscriptStore
#   4. Hand-edit the spec to "correct" a hallucinated value (simulating a
#      user who clicked through the Pluto UI and noticed the LLM defaulted
#      duration to the wrong value)
#   5. Diff the LLM spec vs the user-corrected spec — this is the per-session
#      training signal
#   6. Log the corrected spec
#   7. Export the whole transcript table to JSONL for sharing
#
# Run from the repo root:
#   julia --project examples/lifecycle.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Crucible

println("=" ^ 70)
println("crucible — option-3 flywheel lifecycle demo")
println("=" ^ 70)

# Use a temp DB so we don't clobber the user's real transcript store
db_path = tempname() * ".duckdb"
store = open_transcript_store(path=db_path)
println("\nopened transcript store at: ", db_path)

# Step 1+2: ingest + transpile
methods_text = read(joinpath(@__DIR__, "..", "test", "fixtures", "sample_md_methods.txt"), String)
paper = ingest(NotesAdapter(), methods_text)
fixture = joinpath(@__DIR__, "..", "test", "fixtures", "recorded_anthropic_spec.json")
provider = RecordedProvider(fixture)
result = transpile(provider, paper.body_text)
println("\n[2] transpiled (", result.provider_name, ")")

# Step 3: log the LLM's first-pass spec
backends = [OpenMMBackend(), MollyBackend()]
choice = route_backend(result.spec; available=backends)
report = Crucible.run_validation(result.spec_json, result.spec, choice.backend)
llm_id = log_transcript(store, paper, result; validation=report)
println("[3] logged LLM session: ", llm_id)

# Step 4: hand-edit the spec (simulate a user fix). The LLM may have
# defaulted duration_ns to something safe; the user pulls the real value
# from the paper (100 ns).
llm_spec = result.spec
new_proto = copy(llm_spec.protocol)
prod_idx = findlast(s -> s isa Crucible.DynamicsStage && s.role == :production, new_proto)
if prod_idx !== nothing
    s = new_proto[prod_idx]
    new_proto[prod_idx] = Crucible.DynamicsStage(
        role=s.role, ensemble=s.ensemble,
        duration_ns=100.0,             # user correction (was 10.0)
        dt_fs=s.dt_fs, temperature_K=s.temperature_K,
        pressure_bar=s.pressure_bar, thermostat=s.thermostat,
        barostat=s.barostat, friction_ps=s.friction_ps,
        constraints=s.constraints, restraints=s.restraints,
    )
end
user_spec = MDSpec(
    schema_version=llm_spec.schema_version,
    system=llm_spec.system, force_field=llm_spec.force_field,
    protocol=new_proto,
    observables=llm_spec.observables,
    provenance=llm_spec.provenance,
    warnings=llm_spec.warnings,
    notes=llm_spec.notes * " | edited by user (lifecycle demo)",
)
println("\n[4] hand-edited spec: production duration -> 100 ns")

# Step 5: diff
d = diff_specs(llm_spec, user_spec)
println("\n[5] llm vs user diff:")
println(Crucible.render(MarkdownRenderer(), d))

# Step 6: log corrected spec as a separate transcript row
user_result = Crucible.TranspileResult(
    Crucible.spec_to_json(user_spec), user_spec,
    "user-corrected via lifecycle.jl",
    :user_corrected, "manual",
    0.0,
)
user_id = log_transcript(store, paper, user_result; validation=report)
println("[6] logged user-corrected session: ", user_id)
println("    transcript count: ", transcript_count(store))

# Step 7: export to JSONL for sharing
jsonl_path = tempname() * ".jsonl"
n = export_transcripts_jsonl(store, jsonl_path)
println("\n[7] exported ", n, " transcripts to: ", jsonl_path)
println("    head -1: ", strip(first(eachline(jsonl_path)))[1:120], "...")

close_transcript_store(store)

println("\n" * "=" ^ 70)
println("flywheel demo complete.")
println("training pair (paper -> llm_spec) is row 1 of the JSONL.")
println("training signal (llm_spec -> user_spec diff) is the diff above.")
println("=" ^ 70)

rm(db_path; force=true)
rm(jsonl_path; force=true)
