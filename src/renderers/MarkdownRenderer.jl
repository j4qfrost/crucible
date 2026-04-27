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
_stage_label(s::FEPStage) = string("FEP (", String(s.kind), ")")
_stage_label(s::REMDStage) = string("REMD (", length(s.temperature_ladder_K), " replicas)")
_stage_label(::MetadynamicsStage) = "metadynamics"

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

function _stage_details(s::FEPStage)
    parts = String[
        string(length(s.lambda_windows), " λ windows × ", s.duration_per_window_ns, " ns"),
        string("target=`", s.target_selection, "`"),
        string(String(s.ensemble), ", T=", s.temperature_K, " K"),
    ]
    s.ensemble == :NPT && push!(parts, string("P=", s.pressure_bar, " bar"))
    join(parts, "; ")
end

function _stage_details(s::REMDStage)
    parts = String[
        string(round(first(s.temperature_ladder_K); digits=1), "–",
               round(last(s.temperature_ladder_K); digits=1), " K ladder"),
        string(s.duration_per_replica_ns, " ns per replica"),
        string("exchange every ", s.exchange_attempt_period_ps, " ps"),
        string(String(s.ensemble), " @ ", s.dt_fs, " fs"),
    ]
    join(parts, "; ")
end

function _stage_details(s::MetadynamicsStage)
    cv_names = join((cv.name * ":" * String(cv.kind) for cv in s.cvs), ", ")
    parts = String[
        string(length(s.cvs), " CV(s): ", cv_names),
        string(s.duration_ns, " ns @ ", s.dt_fs, " fs"),
        string("bias=", s.bias_height_kj_mol, " kJ/mol every ",
               s.bias_deposit_period_ps, " ps"),
    ]
    s.well_tempered && push!(parts, string("well-tempered γ=", s.bias_factor))
    join(parts, "; ")
end

function render(::MarkdownRenderer, d::SpecDiff)::String
    io = IOBuffer()
    if isempty(d)
        print(io, "## Spec diff\n\nNo differences.\n")
        return String(take!(io))
    end
    print(io, "## Spec diff (", length(d), " differences)\n\n")
    if !isempty(d.changed)
        print(io, "### Changed\n\n")
        print(io, "| field | before | after |\n|-------|--------|-------|\n")
        for (k, va, vb) in d.changed
            print(io, "| `", k, "` | `", _short(va), "` | `", _short(vb), "` |\n")
        end
        print(io, "\n")
    end
    if !isempty(d.only_in_a)
        print(io, "### Only in A (removed)\n\n")
        for (k, v) in d.only_in_a; print(io, "- `", k, "`: ", _short(v), "\n"); end
        print(io, "\n")
    end
    if !isempty(d.only_in_b)
        print(io, "### Only in B (added)\n\n")
        for (k, v) in d.only_in_b; print(io, "- `", k, "`: ", _short(v), "\n"); end
        print(io, "\n")
    end
    String(take!(io))
end

_short(x) = string(x)
_short(x::Nothing) = "—"
_short(x::AbstractString) = length(x) > 60 ? string(SubString(x, 1, 57), "…") : x

function render(::MarkdownRenderer, c::CoverageReport)::String
    io = IOBuffer()
    score = coverage_score(c)
    pct = c.total_numeric_fields == 0 ? 0.0 :
          100.0 * c.fields_with_provenance / c.total_numeric_fields
    print(io, "## Provenance coverage\n\n")
    print(io, "- **Quality score:** `", round(score; digits=3), "`",
              " (1.0 = all paper-cited, 0.0 = nothing)\n")
    print(io, "- **Coverage:** ", c.fields_with_provenance, " / ",
              c.total_numeric_fields, " (", round(pct; digits=1), "%)\n\n")
    if !isempty(c.by_source)
        print(io, "| source | count |\n|--------|-------|\n")
        for (src, n) in sort(collect(c.by_source); by = x -> -x[2])
            print(io, "| `", String(src), "` | ", n, " |\n")
        end
        print(io, "\n")
    end
    if !isempty(c.missing_paths)
        print(io, "### Missing provenance (", length(c.missing_paths), ")\n\n")
        for p in c.missing_paths
            print(io, "- `", p, "`\n")
        end
        print(io, "\n")
    end
    String(take!(io))
end

function render(::MarkdownRenderer, r::LintReport)::String
    io = IOBuffer()
    print(io, "## Lint\n\n")
    if isempty(r)
        print(io, "✅ no advisories\n\n")
    else
        print(io, "| severity | rule | path | message |\n")
        print(io, "|----------|------|------|---------|\n")
        for f in r.findings
            sev = f.severity == :warn ? "⚠ warn" :
                  f.severity == :advisory ? "💡 advisory" : "ℹ info"
            print(io, "| ", sev, " | `", String(f.rule), "` | `", f.path,
                      "` | ", f.message, " |\n")
        end
        print(io, "\n")
    end
    print(io, render(MarkdownRenderer(), r.coverage))
    String(take!(io))
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
