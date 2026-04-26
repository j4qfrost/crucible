# WebRenderer — stub for the v1 Genie.jl path.
#
# Lives here to lock the interface so the rest of Crucible doesn't grow a
# Pluto-only assumption.

struct WebRenderer <: Renderer end

function render(::WebRenderer, ::MDSpec)
    error("WebRenderer is a v1 placeholder. The Genie.jl frontend lands after Pluto v0 ships.")
end
