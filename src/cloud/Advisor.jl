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
    vram_gb::Float64                # advertised VRAM per GPU
    fits_system::Bool               # rough heuristic on n_atoms vs vram
    gcp_instance::String
    gcp_command::String
    aws_instance::String
    aws_command::String
    azure_instance::String
    azure_command::String
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
    total_ns = 0.0
    n_replicas = 1
    for s in spec.protocol
        if s isa DynamicsStage
            total_ns += s.duration_ns
        elseif s isa FEPStage
            total_ns += length(s.lambda_windows) * s.duration_per_window_ns
        elseif s isa REMDStage
            # Each replica does duration_per_replica_ns of MD; total compute
            # is K * duration. Multi-GPU drops wall-clock for the eligible
            # candidates (handled below).
            total_ns += length(s.temperature_ladder_K) * s.duration_per_replica_ns
            n_replicas = max(n_replicas, length(s.temperature_ladder_K))
        elseif s isa MetadynamicsStage
            total_ns += s.duration_ns
        end
    end
    total_ns = max(total_ns + 0.5, 0.5)   # +0.5 ns equilibration overhead

    candidates = CloudCandidate[]
    for (gpu, t) in bench["gpu"]
        ns_per_day_base = Float64(t["ns_per_day_baseline"])
        scale = baseline_atoms / max(n_atoms, baseline_atoms / 4)
        ns_per_day = ns_per_day_base * backend_mult * scale
        gpu_count = max(1, Int(get(t, "default_gpu_count", 1)))
        parallelism = gpu_count >= n_replicas ? n_replicas : gpu_count
        eff_factor = parallelism * Float64(get(t, "multi_gpu_factor", 1.0))
        runtime_hours = (total_ns / max(ns_per_day, 1e-9)) * 24 / max(eff_factor, 1.0)
        cost = runtime_hours * Float64(t["on_demand_usd_per_hour"])
        vram_gb = Float64(get(t, "vram_gb", 0.0))
        # Memory headroom heuristic: solvated protein-MD typically needs
        # ~150 bytes/atom in OpenMM (positions + velocities + forces +
        # neighbor lists at single precision). FEP doubles it (alchemical
        # context); REMD doesn't compound (each replica is on its own
        # process). Below 0.5 GB headroom, we flag.
        bytes_per_atom = 150
        # FEP needs roughly 2× per-replica memory (alchemical context).
        if any(s -> isa(s, FEPStage), spec.protocol)
            bytes_per_atom *= 2
        end
        est_gb = (n_atoms * bytes_per_atom) / 1024^3
        # Need ~25% margin for cuFFT/PME plans, neighbor-list growth, etc.
        fits = vram_gb == 0.0 || est_gb * 1.25 < vram_gb
        push!(candidates, CloudCandidate(
            gpu, ns_per_day, runtime_hours, cost, vram_gb, fits,
            String(t["gcp_instance"]), String(t["gcp_command"]),
            String(t["aws_instance"]), String(t["aws_command"]),
            String(get(t, "azure_instance", "(no Azure entry)")),
            String(get(t, "azure_command",  "(no Azure entry)")),
        ))
    end

    sort!(candidates; by = c -> c.on_demand_usd)

    # Pick the cheapest CLOUD candidate that finishes within budget AND
    # fits in VRAM. Local-rig entries (on_demand_usd_per_hour == 0) are
    # kept in the candidates list for visibility but excluded from
    # `chosen` because the advisor's stated purpose is cloud sizing —
    # the user already knows whether they have local hardware.
    is_cloud(c) = c.on_demand_usd > 0 || any(s -> startswith(c.gpu, s), ("T4","L4","A10G","A100","H100","V100"))
    cloud_candidates = filter(is_cloud, candidates)
    chosen = nothing
    reason = ""
    for c in cloud_candidates
        if c.runtime_hours <= budget_hours && c.fits_system
            chosen = c
            reason = "smallest cloud GPU that fits the $(budget_hours)-hour budget and the system VRAM"
            break
        end
    end
    if chosen === nothing
        fitting = filter(c -> c.fits_system, cloud_candidates)
        if !isempty(fitting)
            chosen = argmin(c -> c.runtime_hours, fitting)
            reason = "no in-budget cloud GPU fits VRAM; recommending the fastest fitting option"
        elseif !isempty(cloud_candidates)
            chosen = argmin(c -> c.runtime_hours, cloud_candidates)
            reason = "no cloud GPU finishes in $(budget_hours) h budget; recommending the fastest option"
        elseif !isempty(candidates)
            chosen = argmin(c -> c.runtime_hours, candidates)
            reason = "no cloud GPUs available; recommending the fastest local rig"
        end
    end
    warnings = String[]
    requires_confirm = false
    # Surface a separate "local rig" recommendation when one is competitive.
    local_candidates = filter(c -> c.on_demand_usd == 0.0 && c.fits_system, candidates)
    if !isempty(local_candidates)
        best_local = argmin(c -> c.runtime_hours, local_candidates)
        push!(warnings,
            "local rig option: $(best_local.gpu) finishes in " *
            "$(round(best_local.runtime_hours; digits=2)) h at \$0 cost " *
            "(if you have access to it)")
    end
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
    if n_replicas > 1
        push!(warnings,
            "spec requires $(n_replicas) parallel replicas; multi-GPU instances " *
            "(a2-highgpu-Ng on GCP, p4d.24xlarge on AWS) will finish in roughly " *
            "1/$(n_replicas) the wall-clock at proportional cost")
    end
    if chosen !== nothing && !chosen.fits_system && chosen.vram_gb > 0
        push!(warnings,
            "chosen GPU $(chosen.gpu) has $(chosen.vram_gb) GB VRAM but the spec's " *
            "$(n_atoms)-atom system is likely to exceed it (rough estimate at " *
            "150 bytes/atom + 25% margin); consider a larger GPU class")
        requires_confirm = true
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
        write(io, "<details><summary>Azure command</summary><pre>", c.azure_command, "</pre></details>")
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
    write(io, "<tr><th>GPU</th><th>ns/day</th><th>runtime</th><th>cost</th><th>VRAM</th><th>fits?</th></tr>")
    for c in rec.candidates
        fits = c.vram_gb == 0.0 ? "—" : (c.fits_system ? "✓" : "✗")
        write(io, "<tr><td>", c.gpu, "</td><td>",
                  Printf.@sprintf("%.0f", c.ns_per_day), "</td><td>",
                  _fmt_hours(c.runtime_hours), "</td><td>\$",
                  Printf.@sprintf("%.2f", c.on_demand_usd), "</td><td>",
                  c.vram_gb == 0.0 ? "—" : Printf.@sprintf("%.0f GB", c.vram_gb),
                  "</td><td>", fits, "</td></tr>")
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
