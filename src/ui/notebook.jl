### A Pluto.jl notebook ###
# v0.20.0

using Markdown
using InteractiveUtils

# ╔═╡ 11111111-1111-1111-1111-111111111111
begin
    using Pkg
    Pkg.activate(joinpath(@__DIR__, "..", ".."))
    using Crucible
    using PlutoUI
    using HypertextLiteral
end

# ╔═╡ 22222222-2222-2222-2222-222222222222
md"""
# crucible

Drop in a paper, get a runnable molecular-dynamics simulation. The pipeline
is gated — production runs only fire after Gates 1–4 pass and you click the
final button.

**Schema:** v0.3.0 (5 stage types: minimize / dynamics / FEP / REMD / metadynamics; 8 observable types incl. SASA / distance / hbonds)

**Sources supported:** `:user_supplied`, `:pdb_id`, `:pdb_fetch`,
`:smiles` (pure ligand → OpenFFParameterizer), `:protein_ligand` (PDBFixer + SMIRNOFF).

**Solvent:** explicit (TIP3P / TIP4P_EW / SPC_E), implicit (GBSA), vacuum,
or **lipid bilayer** (POPC / POPE / DPPC / mixed_POPC_chol; auto-emits
`MonteCarloMembraneBarostat` for NPT).
"""

# ╔═╡ 33333333-3333-3333-3333-333333333333
md"## 1. Source paper"

# ╔═╡ 44444444-4444-4444-4444-444444444444
@bind source_kind Select(
    ["notes" => "paste notes", "pdf" => "local PDF", "arxiv" => "arXiv ID", "biorxiv" => "bioRxiv DOI"];
    default = "notes",
)

# ╔═╡ 55555555-5555-5555-5555-555555555555
@bind source_value TextField((80, 8); default = "Paste paper text or methods section here.")

# ╔═╡ 66666666-6666-6666-6666-666666666666
paper = let
    adapter = source_kind == "pdf"     ? PDFAdapter()    :
              source_kind == "arxiv"   ? ArxivAdapter()  :
              source_kind == "biorxiv" ? BioRxivAdapter() :
                                         NotesAdapter()
    try
        ingest(adapter, source_value)
    catch err
        @info "ingest failed; falling back to notes" error=err
        ingest(NotesAdapter(), source_value)
    end
end

# ╔═╡ 77777777-7777-7777-7777-777777777777
md"""## 2. Transpile

Pick a provider, then click `transpile`. `recorded` replays a fixture (no
API call); `anthropic` needs `ANTHROPIC_API_KEY`; `local` hits an
OpenAI-compatible endpoint at `http://localhost:8000/v1` (override via
`CRUCIBLE_LOCAL_ENDPOINT`).
"""

# ╔═╡ 77777777-aaaa-7777-7777-777777777777
@bind provider_kind Select(
    ["recorded" => "recorded fixture (offline)",
     "anthropic" => "anthropic (Claude)",
     "local"     => "local (vLLM / Ollama / llama.cpp)"];
    default = "recorded",
)

# ╔═╡ 88888888-8888-8888-8888-888888888888
@bind transpile_button CounterButton("transpile paper → MDSpec")

# ╔═╡ 99999999-9999-9999-9999-999999999999
result = let
    transpile_button   # depend on the button so we don't auto-fire on every paper edit
    provider = if provider_kind == "anthropic"
        AnthropicProvider()
    elseif provider_kind == "local"
        LocalProvider()
    else
        # Recorded — use the bundled fixture by default.
        fixture = joinpath(@__DIR__, "..", "..", "test", "fixtures",
                           "recorded_anthropic_spec.json")
        RecordedProvider(fixture)
    end
    transpile(provider, paper.body_text)
end

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
md"""
**Provider:** $(result.provider_name) / $(result.model)

**Cost estimate:** \$$(round(result.cost_estimate_usd; digits=4))

$(result.spec === nothing ? "_No spec was produced. " * result.raw_response * "_" : "")
"""

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
md"## 3. Validate (Gates 1–3: schema, semantic, loadability)"

# ╔═╡ cccccccc-cccc-cccc-cccc-cccccccccccc
backends = [OpenMMBackend(), MollyBackend()]

# ╔═╡ dddddddd-dddd-dddd-dddd-dddddddddddd
choice = result.spec === nothing ? nothing : route_backend(result.spec; available = backends)

# ╔═╡ eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
report = (result.spec === nothing || choice === nothing) ? nothing :
         Crucible.run_validation(result.spec_json, result.spec, choice.backend)

# ╔═╡ ffffffff-ffff-ffff-ffff-ffffffffffff
HTML(result.spec === nothing ? "" : Crucible.render(PlutoRenderer(), result.spec))

# ╔═╡ a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1
HTML(choice === nothing ? "" : Crucible.render(PlutoRenderer(), choice))

# ╔═╡ a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2
HTML(report === nothing ? "" : Crucible.render(PlutoRenderer(), report))

# ╔═╡ a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3
md"## 4. Cloud sizing"

# ╔═╡ a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4
@bind budget_hours Slider(1:24; default = 6, show_value = true)

# ╔═╡ a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5
recommendation = (result.spec === nothing || choice === nothing) ? nothing :
                 Crucible.advise(result.spec; budget_hours = budget_hours,
                                              backend_name = Crucible.backend_name(choice.backend))

# ╔═╡ a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6
HTML(recommendation === nothing ? "" : Crucible.render(PlutoRenderer(), recommendation))

# ╔═╡ a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7
md"## 5. Render the backend script"

# ╔═╡ a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
prepared = let
    if result.spec === nothing || choice === nothing || (report !== nothing && !report.ok)
        nothing
    else
        workdir = mktempdir(prefix = "crucible-")
        Crucible.prepare(choice.backend, result.spec, workdir)
    end
end

# ╔═╡ a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
md"""
**Prepared:** $(prepared === nothing ? "_(awaiting valid spec)_" : prepared.script_path)
"""

# ╔═╡ b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1
md"""## 6. Preview (Gate 4 — short integration smoke)

Runs ~100 steps under `CRUCIBLE_PREVIEW_STEPS`; rejects if energies blow up,
NaN, or the process exits non-zero. Free gate before any GPU spend.
"""

# ╔═╡ b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2
@bind preview_button CounterButton("run preview (Gate 4)")

# ╔═╡ b3b3b3b3-b3b3-b3b3-b3b3-b3b3b3b3b3b3
preview_report = let
    preview_button
    if prepared === nothing || choice === nothing
        nothing
    else
        try
            Crucible.gate_preview(choice.backend, prepared; n_steps = 100)
        catch err
            ValidationReport(false, ["preview failed: $(err)"], String[])
        end
    end
end

# ╔═╡ b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4
HTML(preview_report === nothing ? "" : Crucible.render(PlutoRenderer(), preview_report))

# ╔═╡ b5b5b5b5-b5b5-b5b5-b5b5-b5b5b5b5b5b5
md"""## 7. Production run (Gate 5 — explicit confirmation)

The button below only fires a real run if **all** of the following hold:

* validation passed (Gates 1–3)
* preview passed (Gate 4)
* cloud advisor isn't asking for cost confirmation, OR you have an
  `ANTHROPIC_API_KEY`-style override set for cost
"""

# ╔═╡ b6b6b6b6-b6b6-b6b6-b6b6-b6b6b6b6b6b6
gate5_ok = prepared !== nothing &&
           report !== nothing && report.ok &&
           preview_report !== nothing && preview_report.ok &&
           (recommendation === nothing || !recommendation.requires_confirmation)

# ╔═╡ b7b7b7b7-b7b7-b7b7-b7b7-b7b7b7b7b7b7
@bind run_button CounterButton("run production")

# ╔═╡ b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8
production = let
    run_button   # depend ONLY on the button — never auto-fires
    # Reactive guard: if any gate before us is unhealthy, return nothing.
    # This is the Gate 5 contract: even with the button clicked, we still
    # check the upstream state.
    if !gate5_ok
        nothing
    else
        Crucible.run!(choice.backend, prepared)
    end
end

# ╔═╡ b9b9b9b9-b9b9-b9b9-b9b9-b9b9b9b9b9b9
md"""
**Production status:** $(production === nothing ? (gate5_ok ? "_click run when ready_" : "_blocked: upstream gate failed_") :
production.success ? "✅ run completed; artifacts in `$(production.job.workdir)`" :
"❌ run failed; see log")
"""

# ╔═╡ ba1a1a1a-a1a1-a1a1-a1a1-a1a1a1a1a1a1
md"## 8. Transcript log (option-3 flywheel)"

# ╔═╡ ba2a2a2a-a2a2-a2a2-a2a2-a2a2a2a2a2a2
@bind log_button CounterButton("log this session to ~/.local/share/crucible/transcripts.duckdb")

# ╔═╡ ba3a3a3a-a3a3-a3a3-a3a3-a3a3a3a3a3a3
log_status = let
    log_button
    if result.spec === nothing
        "no spec to log"
    else
        try
            store = open_transcript_store()
            id = log_transcript(store, paper, result; validation = report)
            n = transcript_count(store)
            close_transcript_store(store)
            "logged $(id); store now contains $(n) transcripts"
        catch err
            "log failed: $(err)"
        end
    end
end

# ╔═╡ ba4a4a4a-a4a4-a4a4-a4a4-a4a4a4a4a4a4
md"""**$(log_status)**"""

# ╔═╡ Cell order:
# ╠═11111111-1111-1111-1111-111111111111
# ╟─22222222-2222-2222-2222-222222222222
# ╟─33333333-3333-3333-3333-333333333333
# ╠═44444444-4444-4444-4444-444444444444
# ╠═55555555-5555-5555-5555-555555555555
# ╠═66666666-6666-6666-6666-666666666666
# ╟─77777777-7777-7777-7777-777777777777
# ╠═88888888-8888-8888-8888-888888888888
# ╠═99999999-9999-9999-9999-999999999999
# ╟─aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# ╟─bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
# ╠═cccccccc-cccc-cccc-cccc-cccccccccccc
# ╠═dddddddd-dddd-dddd-dddd-dddddddddddd
# ╠═eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
# ╠═ffffffff-ffff-ffff-ffff-ffffffffffff
# ╠═a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1
# ╠═a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2
# ╟─a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3
# ╠═a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4
# ╠═a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5
# ╠═a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6
# ╟─a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7
# ╠═a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
# ╟─a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
# ╟─b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1
# ╠═b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2
# ╠═b3b3b3b3-b3b3-b3b3-b3b3-b3b3b3b3b3b3
# ╠═b4b4b4b4-b4b4-b4b4-b4b4-b4b4b4b4b4b4
# ╟─b5b5b5b5-b5b5-b5b5-b5b5-b5b5b5b5b5b5
# ╠═b6b6b6b6-b6b6-b6b6-b6b6-b6b6b6b6b6b6
# ╠═b7b7b7b7-b7b7-b7b7-b7b7-b7b7b7b7b7b7
# ╠═b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8
# ╟─b9b9b9b9-b9b9-b9b9-b9b9-b9b9b9b9b9b9
# ╟─ba1a1a1a-a1a1-a1a1-a1a1-a1a1a1a1a1a1
# ╠═ba2a2a2a-a2a2-a2a2-a2a2-a2a2a2a2a2a2
# ╠═ba3a3a3a-a3a3-a3a3-a3a3-a3a3a3a3a3a3
# ╟─ba4a4a4a-a4a4-a4a4-a4a4-a4a4a4a4a4a4
