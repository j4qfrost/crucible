# Critical-moment detection for completed runs.
#
# Walks observable CSVs in a workdir + emits a list of "events" that
# are typically interesting for a reviewer / student. Heuristic, not
# definitive — the doc emphasizes that real interpretation needs the
# actual trajectory.
#
# Detection rules:
#   * energy spike     — |z| > 3 against rolling mean (window = 50 frames)
#   * rmsd jump        — frame-to-frame Δ > 3 × global std
#   * distance crossing — value crosses a threshold (default 0.6 nm:
#                          covalent → nonbonded transition for ligand work)
#   * hbond drop       — running-mean drop ≥ 50% over 10 frames
#   * rg expansion     — same as rmsd jump, but on Rg
#
# Trade-off: the thresholds are scientifically meaningful for typical
# protein-MD systems but arbitrary in absolute terms. A user with a
# different system (e.g. a small molecule in vacuum) should re-tune
# via flags. Default behavior errs on "more events, false positives
# OK" because missing a critical moment is the worse failure mode for
# a learning audience.

struct CrucibleEvent
    kind::Symbol            # :energy_spike | :rmsd_jump | :distance_crossing | :hbond_drop | :rg_expansion
    observable::String      # which CSV
    frame::Int              # 1-based row index in the CSV
    value::Float64          # the value at the event
    description::String     # one-line human summary
end

"""
    detect_events(workdir; rmsd_z=3.0, energy_z=3.0,
                  distance_threshold_nm=0.6,
                  hbond_drop_pct=0.5) -> Vector{CrucibleEvent}

Walk every observable CSV in the workdir + return critical moments.
The result is sorted by (observable, frame) so the timeline is
reviewable left-to-right per observable.
"""
function detect_events(workdir::AbstractString;
                       rmsd_z::Real=3.0,
                       energy_z::Real=3.0,
                       distance_threshold_nm::Real=0.6,
                       hbond_drop_pct::Real=0.5,
                       rg_z::Real=3.0)::Vector{CrucibleEvent}
    isdir(workdir) || error("detect_events: workdir not a directory: $(workdir)")
    events = CrucibleEvent[]

    # Each CSV has a known shape — see Observables.jl + the renderer's
    # _emit_observables. The observable's filename uniquely identifies
    # its kind.
    rmsd_path = joinpath(workdir, "rmsd.csv")
    if isfile(rmsd_path)
        idx, vals = read_observable_csv(rmsd_path)
        for ev in _detect_jumps(idx, vals, rmsd_z, "rmsd_nm")
            push!(events, CrucibleEvent(:rmsd_jump, "rmsd.csv",
                                        ev.frame, ev.value,
                                        "RMSD jump: |Δ|=$(round(ev.delta; digits=3)) nm at frame $(ev.frame) (z=$(round(ev.zscore; digits=2)))"))
        end
    end

    rg_path = joinpath(workdir, "rg.csv")
    if isfile(rg_path)
        idx, vals = read_observable_csv(rg_path)
        for ev in _detect_jumps(idx, vals, rg_z, "rg_nm")
            push!(events, CrucibleEvent(:rg_expansion, "rg.csv",
                                        ev.frame, ev.value,
                                        "Rg expansion/contraction: |Δ|=$(round(ev.delta; digits=3)) nm at frame $(ev.frame) (z=$(round(ev.zscore; digits=2)))"))
        end
    end

    # Distance time-series — flag every threshold crossing.
    dist_path = joinpath(workdir, "distance.csv")
    if isfile(dist_path)
        idx, vals = read_observable_csv(dist_path)
        for k in 2:length(vals)
            crossed_up   = vals[k-1] <  distance_threshold_nm && vals[k] >= distance_threshold_nm
            crossed_down = vals[k-1] >= distance_threshold_nm && vals[k] <  distance_threshold_nm
            if crossed_up
                push!(events, CrucibleEvent(:distance_crossing, "distance.csv",
                                            idx[k], vals[k],
                                            "Distance crossed $(distance_threshold_nm) nm upward (frame $(idx[k]); often = unbinding event)"))
            elseif crossed_down
                push!(events, CrucibleEvent(:distance_crossing, "distance.csv",
                                            idx[k], vals[k],
                                            "Distance crossed $(distance_threshold_nm) nm downward (frame $(idx[k]); often = (re)binding event)"))
            end
        end
    end

    # H-bond drops via 10-frame running window.
    hb_path = joinpath(workdir, "hbonds.csv")
    if isfile(hb_path)
        idx, vals = read_observable_csv(hb_path)
        win = 10
        if length(vals) > 2 * win
            for k in (win + 1):(length(vals) - win)
                before = sum(@view vals[k - win:k - 1]) / win
                after  = sum(@view vals[k:k + win - 1]) / win
                if before > 0 && (before - after) / before >= hbond_drop_pct
                    push!(events, CrucibleEvent(:hbond_drop, "hbonds.csv",
                                                idx[k], vals[k],
                                                "H-bond count dropped $(round(100 * (before - after) / before; digits=1))% (window mean $(round(before; digits=1)) → $(round(after; digits=1)) at frame $(idx[k]))"))
                    # Don't double-flag adjacent frames in the same drop.
                    break
                end
            end
        end
    end

    # Energy spikes from the per-stage StateDataReporter logs. Format
    # is OpenMM's CSV header + numeric rows; we extract Total Energy.
    for f in readdir(workdir; join=true)
        endswith(f, ".log") || continue
        spikes = _detect_energy_spikes(f, energy_z)
        for ev in spikes
            push!(events, CrucibleEvent(:energy_spike, basename(f),
                                        ev.frame, ev.value,
                                        "Energy spike in $(basename(f)): $(round(ev.value; digits=1)) kJ/mol at step $(ev.frame) (z=$(round(ev.zscore; digits=2)))"))
        end
    end

    sort!(events; by = e -> (e.observable, e.frame))
    events
end

# Detect frame-to-frame jumps with z-score above threshold.
function _detect_jumps(idx::Vector{Int}, vals::Vector{Float64},
                       z_threshold::Real, _label::String)
    out = NamedTuple[]
    length(vals) < 3 && return out
    deltas = [abs(vals[k] - vals[k - 1]) for k in 2:length(vals)]
    μ  = sum(deltas) / length(deltas)
    σ² = sum((d - μ)^2 for d in deltas) / max(length(deltas) - 1, 1)
    σ  = sqrt(σ²)
    σ == 0 && return out
    for k in 2:length(vals)
        delta = abs(vals[k] - vals[k - 1])
        z = (delta - μ) / σ
        z > z_threshold || continue
        push!(out, (frame = idx[k], value = vals[k],
                    delta = vals[k] - vals[k - 1], zscore = z))
    end
    out
end

# Energy spike on OpenMM StateDataReporter log. Header maps roughly:
#   "Step","Time (ps)","Potential Energy (kJ/mole)","Kinetic Energy (kJ/mole)",
#   "Total Energy (kJ/mole)","Temperature (K)","Box Volume (nm^3)"
# We pull "Total Energy" if present, else "Potential Energy".
function _detect_energy_spikes(log_path::AbstractString, z_threshold::Real)
    out = NamedTuple[]
    isfile(log_path) || return out
    lines = readlines(log_path)
    isempty(lines) && return out
    # First non-comment line is the header.
    header_idx = findfirst(l -> !startswith(l, "#") && occursin(",", l), lines)
    header_idx === nothing && return out
    header = split(strip(lines[header_idx], ['#', ' ', '\t']), ",")
    header = [strip(h, ['"', ' ']) for h in header]
    target = findfirst(h -> occursin("Total Energy", h), header)
    target === nothing && (target = findfirst(h -> occursin("Potential Energy", h), header))
    target === nothing && return out
    step_col = findfirst(h -> occursin("Step", h), header)
    energies = Float64[]
    steps = Int[]
    for line in lines[(header_idx + 1):end]
        startswith(line, "#") && continue
        parts = split(line, ",")
        length(parts) >= target || continue
        try
            push!(energies, parse(Float64, strip(parts[target])))
            push!(steps,    step_col === nothing ? length(energies) : parse(Int, strip(parts[step_col])))
        catch
            continue
        end
    end
    length(energies) < 50 && return out
    # Use a 50-frame rolling-window mean; flag anything > z_threshold * std.
    win = 50
    for k in (win + 1):length(energies)
        local_window = @view energies[k - win:k - 1]
        μ  = sum(local_window) / win
        σ² = sum((x - μ)^2 for x in local_window) / max(win - 1, 1)
        σ  = sqrt(σ²)
        σ == 0 && continue
        z = (energies[k] - μ) / σ
        if abs(z) > z_threshold
            push!(out, (frame = steps[k], value = energies[k], zscore = z))
        end
    end
    out
end
