# NotebookRenderer — exports the current MDSpec + rendered backend script
# into a standalone Pluto notebook the user can email or check into a repo.

struct NotebookRenderer <: Renderer end

function render(::NotebookRenderer, spec::MDSpec; out::AbstractString,
                backend_script::AbstractString="",
                backend_name_str::AbstractString="openmm")
    spec_json = spec_to_json(spec)
    open(out, "w") do io
        write(io, "### A Pluto.jl notebook ###\n# v0.20.0\n\nusing Markdown\nusing InteractiveUtils\n\n")
        # cell 1: title
        write(io, _cell("md\"\"\"# Crucible exported simulation\n\n", "Generated from MDSpec \$$(spec.schema_version)\$.\"\"\"\n"))
        # cell 2: spec JSON
        write(io, _cell("spec_json = raw\"\"\"\n", spec_json, "\n\"\"\"\n"))
        # cell 3: rendered backend script
        write(io, _cell("# Rendered ", backend_name_str, " script:\nbackend_script = raw\"\"\"\n",
                        backend_script, "\n\"\"\"\n"))
        # cell 4: regenerate instructions
        write(io, _cell("md\"\"\"## How to run\n\n",
                        "1. Save `backend_script` to a file.\n",
                        "2. Run it with `python script.py` (OpenMM) or `julia --project script.jl` (Molly).\n",
                        "3. To regenerate from a paper, open the source notebook in Crucible.\"\"\"\n"))
    end
    out
end

function _cell(parts...)
    body = join(parts, "")
    "# ╔═╡ $(string(uuid4()))\n$(body)\n\n"
end
