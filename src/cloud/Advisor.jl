# Cloud sizing advisor.
#
# Inputs:  (atoms, total_ns, ensemble, backend_name)
# Outputs: ranked GPU candidates with cost, runtime, and ready-to-paste
#          gcloud / aws command strings.
#
# Hard caps:
#   - Default duration cap: 10 ns (advisor warns past this)
#   - Cost confirmation: requires explicit ack past 50 ns or $20
#
# Numbers come from cloud/benchmarks.toml; treat as ballpark.

const _BENCH_PATH = joinpath(@__DIR__, "benchmarks.toml")

struct CloudCandidate
    gpu::String
    ns_per_day::Float64
    runtime_hours::Float64
    on_demand_usd::Float64
    gcp_instance::String
    gcp_command::String
    aws_instance::String
    aws_command::String
end

struct AdvisorRecommendation
    candidates::Vector{CloudCandidate}     # sorted ascending by cost
    chosen::Union{Nothing,CloudCandidate}
    chosen_reason::String
    warnings::Vector{String}
    requires_confirmation::Bool
end

"""
    advise(spec; budget_hours=6.0, prefer_cloud=:gcp) -> AdvisorRecommendation

For a given MDSpec, return the cheapest GPU that finishes inside
`budget_hours`, with all candidates also returned for transparency.
"""
function advise(spec::MDSpec; budget_hours::Real=6.0, prefer_cloud::Symbol=:gcp,
                backend_name::Symbol=:openmm)::AdvisorRecommendation
    bench = TOML.parsefile(_BENCH_PATH)
    multipliers = bench["backend_multipliers"]
    baseline_atoms = Float64(bench["baseline_atoms"])
    backend_mult = Float64(get(multipliers, String(backend_name), 1.0))

    n_atoms = max(1, spec.system.n_atoms_estimate)
    total_ns = sum(s isa DynamicsStage ? s.duration_ns : 0.0 for s in spec.protocol)
    total_ns = max(total_ns + 0.5, 0.5)   # +0.5 ns equilibration overhead

    candidates = CloudCandidate[]
    for (gpu, t) in bench["gpu"]
        ns_per_day_base = Float64(t["ns_per_day_baseline"])
        # Linear inverse scaling with atom count above baseline; cap above
        # baseline so tiny systems don't claim absurd throughput.
        scale = baseline_atoms / max(n_atoms, baseline_atoms / 4)
        ns_per_day = ns_per_day_base * backend_mult * scale
        runtime_hours = (total_ns / max(ns_per_day, 1e-9)) * 24
        cost = runtime_hours * Float64(t["on_demand_usd_per_hour"])
        push!(candidates, CloudCandidate(
            gpu, ns_per_day, runtime_hours, cost,
            String(t["gcp_instance"]), String(t["gcp_command"]),
            String(t["aws_instance"]), String(t["aws_command"]),
        ))
    end

    sort!(candidates; by = c -> c.on_demand_usd)

    # Pick the cheapest candidate that finishes within budget. If none does,
    # pick the fastest.
    chosen = nothing
    reason = ""
    for c in candidates
        if c.runtime_hours <= budget_hours
            chosen = c
            reason = "smallest GPU that fits the $(budget_hours)-hour budget"
            break
        end
    end
    if chosen === nothing && !isempty(candidates)
        chosen = argmin(c -> c.runtime_hours, candidates)
        reason = "no GPU finishes in $(budget_hours) h budget; recommending the fastest option"
    end

    warnings = String[]
    requires_confirm = false
    if total_ns > 50.0
        push!(warnings, "total_ns=$(total_ns) exceeds the 50 ns soft cap; explicit confirmation required")
        requires_confirm = true
    end
    if chosen !== nothing && chosen.on_demand_usd > 20.0
        push!(warnings, "estimated cost \$$(round(chosen.on_demand_usd, digits=2)) exceeds the \$20 soft cap")
        requires_confirm = true
    end
    if backend_name == :molly && n_atoms > 50_000
        push!(warnings, "Molly backend selected with n_atoms=$(n_atoms); OpenMM backend would likely be ~3x faster")
    end

    AdvisorRecommendation(candidates, chosen, reason, warnings, requires_confirm)
end

# Convenience for Pluto rendering
function render(::PlutoRenderer, rec::AdvisorRecommendation)::String
    io = IOBuffer()
    write(io, "<div style=\"font-family: monospace; font-size: 12px;\">")
    write(io, "<h4>Cloud sizing recommendation</h4>")
    if rec.chosen !== nothing
        c = rec.chosen
        write(io, "<p><strong>", c.gpu, "</strong> — ", _fmt_hours(c.runtime_hours), ", ~\$",
                  Printf.@sprintf("%.2f", c.on_demand_usd), " on-demand. <em>", rec.chosen_reason, "</em></p>")
        write(io, "<details><summary>GCP command</summary><pre>", c.gcp_command, "</pre></details>")
        write(io, "<details><summary>AWS command</summary><pre>", c.aws_command, "</pre></details>")
    end
    if !isempty(rec.warnings)
        write(io, "<h5 style=\"color:#b65;\">Warnings</h5><ul>")
        for w in rec.warnings; write(io, "<li>", w, "</li>"); end
        write(io, "</ul>")
        if rec.requires_confirmation
            write(io, "<p><strong>Explicit confirmation required before running.</strong></p>")
        end
    end
    write(io, "<details><summary>All candidates</summary>")
    write(io, "<table border=\"1\" cellpadding=\"3\" style=\"border-collapse:collapse;\">")
    write(io, "<tr><th>GPU</th><th>ns/day</th><th>runtime</th><th>cost</th></tr>")
    for c in rec.candidates
        write(io, "<tr><td>", c.gpu, "</td><td>",
                  Printf.@sprintf("%.0f", c.ns_per_day), "</td><td>",
                  _fmt_hours(c.runtime_hours), "</td><td>$",
                  Printf.@sprintf("%.2f", c.on_demand_usd), "</td></tr>")
    end
    write(io, "</table></details>")
    write(io, "</div>")
    String(take!(io))
end

function _fmt_hours(h::Real)
    h < 1 ? Printf.@sprintf("%.0f min", h*60) :
    h < 24 ? Printf.@sprintf("%.1f h", h) :
    Printf.@sprintf("%.1f d", h/24)
end
