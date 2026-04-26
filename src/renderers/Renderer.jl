# Output renderers display Crucible artifacts to the user. v0 ships a Pluto
# renderer (in-notebook tables/plots) and a notebook exporter (writes a
# standalone .jl Pluto file the user can re-open later).

abstract type Renderer end

"""
    render(renderer, target) -> Any

Polymorphic on what's being rendered:
  - render(::PlutoRenderer, ::MDSpec) → HTML for in-notebook display
  - render(::PlutoRenderer, ::ValidationReport) → HTML
  - render(::PlutoRenderer, ::SimResult) → HTML with plot
  - render(::NotebookRenderer, ::MDSpec; out::String) → writes a .jl file
"""
function render(r::Renderer, target)
    error("render($(typeof(r)), $(typeof(target))) not implemented")
end
