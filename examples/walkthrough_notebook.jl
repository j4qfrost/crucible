### A Pluto.jl notebook ###
# v0.20.0
#
# A guided Pluto walkthrough that mirrors examples/walkthrough.jl.
# Open with: julia --project -e 'using Pluto; Pluto.run(notebook="examples/walkthrough_notebook.jl")'

using Markdown
using InteractiveUtils

# ╔═╡ 11111111-1111-1111-1111-aaaaaaaaaaaa
begin
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."))
    using Crucible
    using PlutoUI
    using HypertextLiteral
end

# ╔═╡ 22222222-2222-2222-2222-aaaaaaaaaaaa
md"""
# crucible — guided walkthrough

This notebook demonstrates the full crucible pipeline against the
`sample_md_methods.txt` fixture, using the **RecordedProvider** so no
API key is required.

It mirrors `examples/walkthrough.jl` but with reactive cells —
edit the source paper, see everything downstream re-render.
"""

# ╔═╡ 33333333-3333-3333-3333-aaaaaaaaaaaa
md"## 1. Source paper"

# ╔═╡ 44444444-4444-4444-4444-aaaaaaaaaaaa
methods_text = read(joinpath(@__DIR__, "..", "test", "fixtures", "sample_md_methods.txt"), String)

# ╔═╡ 55555555-5555-5555-5555-aaaaaaaaaaaa
@bind paper_text TextField((80, 12); default = methods_text)

# ╔═╡ 66666666-6666-6666-6666-aaaaaaaaaaaa
paper = ingest(NotesAdapter(), paper_text)

# ╔═╡ 77777777-7777-7777-7777-aaaaaaaaaaaa
md"## 2. Transpile (RecordedProvider)"

# ╔═╡ 88888888-8888-8888-8888-aaaaaaaaaaaa
fixture = joinpath(@__DIR__, "..", "test", "fixtures", "recorded_anthropic_spec.json")

# ╔═╡ 99999999-9999-9999-9999-aaaaaaaaaaaa
result = transpile(RecordedProvider(fixture), paper.body_text)

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
md"""
**Provider:** `$(result.provider_name)`
**Spec extracted:** $(result.spec === nothing ? "❌ none" : "✅")
"""

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-aaaaaaaaaaaa
md"## 3. Validate + route"

# ╔═╡ cccccccc-cccc-cccc-cccc-aaaaaaaaaaaa
backends = [OpenMMBackend(), MollyBackend()]

# ╔═╡ dddddddd-dddd-dddd-dddd-aaaaaaaaaaaa
choice = result.spec === nothing ? nothing : route_backend(result.spec; available=backends)

# ╔═╡ eeeeeeee-eeee-eeee-eeee-aaaaaaaaaaaa
report = (result.spec === nothing || choice === nothing) ? nothing :
         Crucible.run_validation(result.spec_json, result.spec, choice.backend)

# ╔═╡ ffffffff-ffff-ffff-ffff-aaaaaaaaaaaa
HTML(result.spec === nothing ? "" : Crucible.render(MarkdownRenderer(), result.spec) |> Markdown.parse |> sprint ∘ show)

# ╔═╡ a1a1a1a1-a1a1-a1a1-a1a1-aaaaaaaaaaaa
HTML(report === nothing ? "" : Crucible.render(PlutoRenderer(), report))

# ╔═╡ a2a2a2a2-a2a2-a2a2-a2a2-aaaaaaaaaaaa
md"## 4. Cloud sizing"

# ╔═╡ a3a3a3a3-a3a3-a3a3-a3a3-aaaaaaaaaaaa
@bind budget_hours Slider(1:24; default = 6, show_value = true)

# ╔═╡ a4a4a4a4-a4a4-a4a4-a4a4-aaaaaaaaaaaa
rec = (result.spec === nothing || choice === nothing) ? nothing :
      Crucible.advise(result.spec; budget_hours = budget_hours,
                                   backend_name = Crucible.backend_name(choice.backend))

# ╔═╡ a5a5a5a5-a5a5-a5a5-a5a5-aaaaaaaaaaaa
HTML(rec === nothing ? "" : Crucible.render(PlutoRenderer(), rec))

# ╔═╡ a6a6a6a6-a6a6-a6a6-a6a6-aaaaaaaaaaaa
md"## 5. Render the backend script (in-memory; no execution)"

# ╔═╡ a7a7a7a7-a7a7-a7a7-a7a7-aaaaaaaaaaaa
prepared_path = if result.spec === nothing || choice === nothing
    nothing
else
    workdir = mktempdir(prefix = "crucible-walkthrough-nb-")
    Crucible.prepare(choice.backend, result.spec, workdir).script_path
end

# ╔═╡ a8a8a8a8-a8a8-a8a8-a8a8-aaaaaaaaaaaa
md"""
**Script:** $(prepared_path === nothing ? "_(awaiting valid spec)_" : "`" * prepared_path * "`")

To execute it, run:

```
python <script>      # OpenMM
julia --project <script>   # Molly
```
"""

# ╔═╡ Cell order:
# ╠═11111111-1111-1111-1111-aaaaaaaaaaaa
# ╟─22222222-2222-2222-2222-aaaaaaaaaaaa
# ╟─33333333-3333-3333-3333-aaaaaaaaaaaa
# ╠═44444444-4444-4444-4444-aaaaaaaaaaaa
# ╠═55555555-5555-5555-5555-aaaaaaaaaaaa
# ╠═66666666-6666-6666-6666-aaaaaaaaaaaa
# ╟─77777777-7777-7777-7777-aaaaaaaaaaaa
# ╠═88888888-8888-8888-8888-aaaaaaaaaaaa
# ╠═99999999-9999-9999-9999-aaaaaaaaaaaa
# ╟─aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# ╟─bbbbbbbb-bbbb-bbbb-bbbb-aaaaaaaaaaaa
# ╠═cccccccc-cccc-cccc-cccc-aaaaaaaaaaaa
# ╠═dddddddd-dddd-dddd-dddd-aaaaaaaaaaaa
# ╠═eeeeeeee-eeee-eeee-eeee-aaaaaaaaaaaa
# ╠═ffffffff-ffff-ffff-ffff-aaaaaaaaaaaa
# ╠═a1a1a1a1-a1a1-a1a1-a1a1-aaaaaaaaaaaa
# ╟─a2a2a2a2-a2a2-a2a2-a2a2-aaaaaaaaaaaa
# ╠═a3a3a3a3-a3a3-a3a3-a3a3-aaaaaaaaaaaa
# ╠═a4a4a4a4-a4a4-a4a4-a4a4-aaaaaaaaaaaa
# ╠═a5a5a5a5-a5a5-a5a5-a5a5-aaaaaaaaaaaa
# ╟─a6a6a6a6-a6a6-a6a6-a6a6-aaaaaaaaaaaa
# ╠═a7a7a7a7-a7a7-a7a7-a7a7-aaaaaaaaaaaa
# ╟─a8a8a8a8-a8a8-a8a8-a8a8-aaaaaaaaaaaa
