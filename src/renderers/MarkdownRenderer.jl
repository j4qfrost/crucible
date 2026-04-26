# MarkdownRenderer — produce GitHub-flavored Markdown summaries of an MDSpec
# (and validation report). Useful for CLI output, PR descriptions, README
# examples, and the PR body when the verification routine opens a follow-up.

struct MarkdownRenderer <: Renderer end

function render(::MarkdownRenderer, spec::MDSpec)::String
    io = IOBuffer()
    print(io, "# MDSpec ", spec.schema_version, "\n\n")
    print(io, "## System\n\n")
    src = spec.system.source
    print(io, "- **Source:** `", String(src.type), "`")
    if src.coordinates !== nothing
        print(io, " (`", src.coordinates, "`)")
    end
    if src.pdb_id !== nothing
        print(io, " — PDB `", src.pdb_id, "`")
    end
    print(io, "\n")
    print(io, "- **Atoms (est):** ", spec.system.n_atoms_estimate, "\n")
    print(io, "- **Has ligand:** ", spec.system.has_ligand ? "yes" : "no", "\n")
    print(io, "- **Solvent:** ", String(spec.system.solvent.model),
              ", NaCl ", spec.system.solvent.ions_NaCl_mM, " mM\n\n")

    print(io, "## Force field\n\n")
    print(io, "| component | value |\n|-----------|-------|\n")
    print(io, "| protein | `", String(spec.force_field.protein), "` |\n")
    print(io, "| water   | `", String(spec.force_field.water),   "` |\n")
    print(io, "| ligand  | `", String(spec.force_field.ligand),  "` |\n\n")

    print(io, "## Protocol\n\n")
    print(io, "| # | stage | details |\n|---|-------|---------|\n")
    for (i, s) in enumerate(spec.protocol)
        print(io, "| ", i, " | ", _stage_label(s), " | ", _stage_details(s), " |\n")
    end
    print(io, "\n")

    if !isempty(spec.observables)
        print(io, "## Observables\n\n")
        for o in spec.observables
            print(io, "- `", String(o.type), "` on `", o.selection,
                      "` (stride ", o.stride_ps, " ps)\n")
        end
        print(io, "\n")
    end

    if !isempty(spec.warnings)
        print(io, "## Warnings\n\n")
        for w in spec.warnings
            print(io, "- ⚠ ", w, "\n")
        end
        print(io, "\n")
    end

    if !isempty(spec.provenance)
        n_paper = count(p -> p.source == :paper, values(spec.provenance))
        n_assumed = count(p -> p.source in (:assumed, :paper_default), values(spec.provenance))
        print(io, "## Provenance\n\n")
        print(io, "- ", n_paper, " value(s) from paper\n")
        print(io, "- ", n_assumed, " value(s) defaulted/assumed\n\n")
    end

    if !isempty(spec.notes)
        print(io, "## Notes\n\n", spec.notes, "\n")
    end
    String(take!(io))
end

_stage_label(::MinimizeStage) = "minimize"
_stage_label(s::DynamicsStage) = string(String(s.role), " (", String(s.ensemble), ")")

_stage_details(s::MinimizeStage) =
    string("max_iter=", s.max_iterations, ", tol=", s.tolerance_kj_mol_nm, " kJ/mol/nm")

function _stage_details(s::DynamicsStage)
    parts = String[]
    push!(parts, string(s.duration_ns, " ns @ ", s.dt_fs, " fs"))
    push!(parts, string("T=", s.temperature_K, " K"))
    if s.ensemble == :NPT
        push!(parts, string("P=", s.pressure_bar, " bar (", String(something(s.barostat, :none)), ")"))
    end
    push!(parts, string("γ=", s.friction_ps, " ps⁻¹"))
    push!(parts, string("constraints=", String(s.constraints)))
    if s.restraints.selection != :none
        push!(parts, string("restraints=", String(s.restraints.selection),
                            " k=", s.restraints.k_kj_mol_nm2, " kJ/mol/nm²"))
    end
    join(parts, "; ")
end

function render(::MarkdownRenderer, r::ValidationReport)::String
    io = IOBuffer()
    print(io, "## Validation\n\n")
    print(io, r.ok ? "✅ **ok**\n\n" : "❌ **failed**\n\n")
    if !isempty(r.errors)
        print(io, "### Errors\n\n")
        for e in r.errors; print(io, "- ", e, "\n"); end
        print(io, "\n")
    end
    if !isempty(r.warnings)
        print(io, "### Warnings\n\n")
        for w in r.warnings; print(io, "- ", w, "\n"); end
        print(io, "\n")
    end
    String(take!(io))
end
