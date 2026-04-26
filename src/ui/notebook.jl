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

Drop in a paper, get a runnable molecular-dynamics simulation.
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
md"## 2. Transpile (Anthropic)"

# ╔═╡ 88888888-8888-8888-8888-888888888888
@bind transpile_button Button("transpile paper → MDSpec")

# ╔═╡ 99999999-9999-9999-9999-999999999999
result = let
    transpile_button   # take a dependency on the button
    provider = AnthropicProvider()
    transpile(provider, paper.body_text)
end

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
md"""
**Provider:** $(result.provider_name) / $(result.model)

**Cost estimate:** \$$(round(result.cost_estimate_usd; digits=4))

$(result.spec === nothing ? "_No spec was produced. " * result.raw_response * "_" : "")
"""

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
md"## 3. Validate"

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
md"## 5. Render & run"

# ╔═╡ a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
@bind render_button Button("render backend script")

# ╔═╡ a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
prepared = let
    render_button   # depend on button
    if result.spec === nothing || choice === nothing || (report !== nothing && !report.ok)
        nothing
    else
        workdir = mktempdir(prefix = "crucible-")
        Crucible.prepare(choice.backend, result.spec, workdir)
    end
end

# ╔═╡ b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1
md"""
**Prepared:** $(prepared === nothing ? "_(awaiting valid spec)_" : prepared.script_path)

To run, gate 4 (preview) and gate 5 (you, here) come next. v0 emits the script for you to run manually:

- OpenMM: `python <script>`
- Molly: `julia --project <script>`
"""

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
# ╠═a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
# ╟─b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1
