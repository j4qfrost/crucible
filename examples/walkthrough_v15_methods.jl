### A Pluto.jl notebook ###
# v0.20.0

using Markdown
using InteractiveUtils

# This Pluto notebook can also be loaded into the Pluto runtime via
#   julia --project -e 'using Pluto; Pluto.run(notebook="examples/walkthrough_v15_methods.jl")'

# This Pluto notebook uses @bind for interactivity. When running outside of
# the Pluto notebook, the following 'mock version' of @bind gives bound
# variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ 11111111-1111-1111-1111-111111111111
using Crucible

# ╔═╡ 11111111-1111-1111-1111-111111111112
using PlutoUI

# ╔═╡ 22222222-2222-2222-2222-222222222222
md"""
# crucible — v1.5 enhanced sampling tour

Pick a sampling method, see the IR, validate, render, get a cloud
recommendation, and run lint + coverage. Everything is offline — no LLM
key, no Python, no GPU. The renderer's output is a real OpenMM script
you could pipe into `python` once the optional deps are installed.

**Methods covered:** vanilla MD · SMILES → MD · protein-ligand FEP ·
T-REMD · membrane (POPC) · metadynamics
"""

# ╔═╡ 33333333-3333-3333-3333-333333333333
md"## 1. Pick a method"

# ╔═╡ 44444444-4444-4444-4444-444444444444
@bind method_name Select(
    [String(n) => String(n) for n in list_templates()];
    default = "protein_ligand_fep",
)

# ╔═╡ 55555555-5555-5555-5555-555555555555
spec = get_template(Symbol(method_name))

# ╔═╡ 66666666-6666-6666-6666-666666666666
md"""
**Notes:** $(spec.notes)

**Required features:** `$(join(sort(collect(Crucible.required_features(spec))), "`, `"))`
"""

# ╔═╡ 77777777-7777-7777-7777-777777777777
md"## 2. Validate (gates 1–3)"

# ╔═╡ 88888888-8888-8888-8888-888888888888
backends = [OpenMMBackend(), MollyBackend()]

# ╔═╡ 99999999-9999-9999-9999-999999999999
choice = route_backend(spec; available = backends)

# ╔═╡ aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
report = Crucible.run_validation(Crucible.spec_to_json(spec), spec, choice.backend)

# ╔═╡ bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
md"""
**Backend:** `$(Crucible.backend_name(choice.backend))` — $(choice.reason)

**Validation:** $(report.ok ? "✅ ok" : "❌ failed")

$(isempty(report.errors) ? "" : "Errors:\n" * join(("- " * e for e in report.errors), "\n"))

$(isempty(report.warnings) ? "" : "Warnings:\n" * join(("- " * w for w in report.warnings), "\n"))
"""

# ╔═╡ cccccccc-cccc-cccc-cccc-cccccccccccc
md"## 3. Spec preview"

# ╔═╡ dddddddd-dddd-dddd-dddd-dddddddddddd
HTML(Crucible.render(PlutoRenderer(), spec))

# ╔═╡ eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
md"## 4. Lint + provenance coverage"

# ╔═╡ ffffffff-ffff-ffff-ffff-ffffffffffff
lint_report = lint(spec)

# ╔═╡ a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1
Markdown.parse(Crucible.render(MarkdownRenderer(), lint_report))

# ╔═╡ a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2
md"## 5. Cloud sizing"

# ╔═╡ a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3
@bind budget_hours Slider(1:48; default = 12, show_value = true)

# ╔═╡ a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4
rec = Crucible.advise(spec; budget_hours = Float64(budget_hours),
                            backend_name = Crucible.backend_name(choice.backend))

# ╔═╡ a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5
HTML(Crucible.render(PlutoRenderer(), rec))

# ╔═╡ a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6
md"## 6. Rendered script"

# ╔═╡ a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7
script = Crucible.render_script(choice.backend, spec; output_dir = "/tmp/crucible-walkthrough")

# ╔═╡ a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
md"""
**Length:** $(length(script)) bytes
"""

# ╔═╡ a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
PlutoUI.with_terminal() do
    print(first(script, 2000))
    println()
    println("…(truncated; full output is $(length(script)) bytes)")
end

# ╔═╡ Cell order:
# ╠═11111111-1111-1111-1111-111111111111
# ╠═11111111-1111-1111-1111-111111111112
# ╟─22222222-2222-2222-2222-222222222222
# ╟─33333333-3333-3333-3333-333333333333
# ╠═44444444-4444-4444-4444-444444444444
# ╠═55555555-5555-5555-5555-555555555555
# ╟─66666666-6666-6666-6666-666666666666
# ╟─77777777-7777-7777-7777-777777777777
# ╠═88888888-8888-8888-8888-888888888888
# ╠═99999999-9999-9999-9999-999999999999
# ╠═aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
# ╟─bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
# ╟─cccccccc-cccc-cccc-cccc-cccccccccccc
# ╠═dddddddd-dddd-dddd-dddd-dddddddddddd
# ╟─eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee
# ╠═ffffffff-ffff-ffff-ffff-ffffffffffff
# ╠═a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1
# ╟─a2a2a2a2-a2a2-a2a2-a2a2-a2a2a2a2a2a2
# ╠═a3a3a3a3-a3a3-a3a3-a3a3-a3a3a3a3a3a3
# ╠═a4a4a4a4-a4a4-a4a4-a4a4-a4a4a4a4a4a4
# ╠═a5a5a5a5-a5a5-a5a5-a5a5-a5a5a5a5a5a5
# ╟─a6a6a6a6-a6a6-a6a6-a6a6-a6a6a6a6a6a6
# ╠═a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7
# ╟─a8a8a8a8-a8a8-a8a8-a8a8-a8a8a8a8a8a8
# ╠═a9a9a9a9-a9a9-a9a9-a9a9-a9a9a9a9a9a9
