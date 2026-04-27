# PlutoRenderer — produce HTML strings that Pluto displays inline.
#
# Kept dependency-free: we don't pull in HypertextLiteral or PlutoUI at the
# package level. The notebook itself imports those for interactivity; this
# renderer just produces strings/HTML for show().

struct PlutoRenderer <: Renderer end

# MDSpec: provenance table + protocol summary
function render(::PlutoRenderer, spec::MDSpec)::String
    io = IOBuffer()
    write(io, "<div style=\"font-family: monospace; font-size: 12px;\">")
    write(io, "<h3>MDSpec ", spec.schema_version, "</h3>")

    write(io, "<h4>System</h4><ul>")
    write(io, "<li>source: ", String(spec.system.source.type),
              spec.system.source.coordinates === nothing ? "" :
              " (coords: $(spec.system.source.coordinates))", "</li>")
    write(io, "<li>n_atoms (est): ", spec.system.n_atoms_estimate, "</li>")
    write(io, "<li>has_ligand: ", spec.system.has_ligand, "</li>")
    write(io, "<li>solvent: ", String(spec.system.solvent.model),
              ", NaCl: ", spec.system.solvent.ions_NaCl_mM, " mM</li>")
    write(io, "</ul>")

    write(io, "<h4>Force field</h4><ul>")
    write(io, "<li>protein: ", String(spec.force_field.protein), "</li>")
    write(io, "<li>water: ",   String(spec.force_field.water),   "</li>")
    write(io, "<li>ligand: ",  String(spec.force_field.ligand),  "</li>")
    write(io, "</ul>")

    write(io, "<h4>Protocol</h4><ol>")
    for s in spec.protocol
        write(io, "<li>", _stage_summary(s), "</li>")
    end
    write(io, "</ol>")

    if !isempty(spec.observables)
        write(io, "<h4>Observables</h4><ul>")
        for o in spec.observables
            write(io, "<li>", String(o.type), " on '", o.selection,
                      "' every ", o.stride_ps, " ps</li>")
        end
        write(io, "</ul>")
    end

    if !isempty(spec.warnings)
        write(io, "<h4 style=\"color: #b65;\">Warnings</h4><ul>")
        for w in spec.warnings
            write(io, "<li>", w, "</li>")
        end
        write(io, "</ul>")
    end

    if !isempty(spec.provenance)
        write(io, "<h4>Provenance (top 12)</h4>")
        write(io, "<table border=\"1\" cellpadding=\"3\" style=\"border-collapse: collapse;\">")
        write(io, "<tr><th>field</th><th>source</th><th>cite</th><th>conf.</th></tr>")
        n = 0
        for (k, v) in spec.provenance
            n += 1; n > 12 && break
            write(io, "<tr><td>", k, "</td><td>", String(v.source), "</td><td>",
                      v.cite === nothing ? "—" : v.cite, "</td><td>",
                      Printf.@sprintf("%.2f", v.confidence), "</td></tr>")
        end
        write(io, "</table>")
        if length(spec.provenance) > 12
            write(io, "<p>… and ", length(spec.provenance) - 12, " more</p>")
        end
    end

    write(io, "</div>")
    String(take!(io))
end

function _stage_summary(s::MinimizeStage)
    string("minimize: max_iter=", s.max_iterations,
           ", tol=", s.tolerance_kj_mol_nm, " kJ/mol/nm")
end

function _stage_summary(s::DynamicsStage)
    base = string(String(s.role), " (", String(s.ensemble), "): ",
                  s.duration_ns, " ns @ ", s.dt_fs, " fs, T=",
                  s.temperature_K, " K")
    s.ensemble == :NPT ? string(base, ", P=", s.pressure_bar, " bar (", String(something(s.barostat, :none)), ")") : base
end

function _stage_summary(s::FEPStage)
    string("FEP (", String(s.kind), "): ",
           length(s.lambda_windows), " λ × ",
           s.duration_per_window_ns, " ns, target=", s.target_selection,
           ", ", String(s.ensemble), " @ ", s.temperature_K, " K")
end

function _stage_summary(s::REMDStage)
    string("REMD: ", length(s.temperature_ladder_K), " replicas (",
           round(first(s.temperature_ladder_K); digits=1), "–",
           round(last(s.temperature_ladder_K); digits=1), " K), ",
           s.duration_per_replica_ns, " ns each, exchange every ",
           s.exchange_attempt_period_ps, " ps")
end

function _stage_summary(s::MetadynamicsStage)
    cv_summary = join((cv.name * ":" * String(cv.kind) for cv in s.cvs), ", ")
    string("metadynamics: ", length(s.cvs), " CV(s) [", cv_summary, "], ",
           s.duration_ns, " ns @ T=", s.temperature_K, " K",
           s.well_tempered ? " (well-tempered γ=$(s.bias_factor))" : "")
end

# ValidationReport
function render(::PlutoRenderer, r::ValidationReport)::String
    io = IOBuffer()
    color = r.ok ? "#3a3" : "#b22"
    label = r.ok ? "validation passed" : "validation FAILED"
    write(io, "<div style=\"font-family: monospace; font-size: 12px;\">")
    write(io, "<h4 style=\"color: ", color, ";\">", label, "</h4>")
    if !isempty(r.errors)
        write(io, "<h5>Errors</h5><ul>")
        for e in r.errors; write(io, "<li>", e, "</li>"); end
        write(io, "</ul>")
    end
    if !isempty(r.warnings)
        write(io, "<h5>Warnings</h5><ul>")
        for w in r.warnings; write(io, "<li>", w, "</li>"); end
        write(io, "</ul>")
    end
    write(io, "</div>")
    String(take!(io))
end

# BackendChoice
function render(::PlutoRenderer, c::BackendChoice)::String
    name = String(backend_name(c.backend))
    "<div><strong>Backend:</strong> $(name)<br><em>$(c.reason)</em></div>"
end
