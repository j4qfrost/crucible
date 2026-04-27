# Provenance + lint utilities. The IR-first design means every numeric
# field that came from a paper SHOULD carry a Provenance entry. This file
# gives us the metrics + lint rules to track that, which directly feeds
# the option-3 fine-tune flywheel: high-coverage transcripts are higher-
# quality training pairs.
#
# Two layers:
#   * `provenance_coverage(spec)` — pure metric: fraction of numeric
#     fields that have a provenance entry, broken down by source.
#   * `lint(spec)` — advisory checks beyond Gates 1-3. Surfaces warnings
#     about quality, plausibility, and protocol shape that the schema
#     can't express. Never blocks; always returns a `LintReport`.

# -----------------------------------------------------------------------------
# Coverage

struct CoverageReport
    total_numeric_fields::Int
    fields_with_provenance::Int
    by_source::Dict{Symbol,Int}        # :paper, :paper_default, :assumed, :user, :runtime_default
    missing_paths::Vector{String}      # JSONPath-ish keys that lack provenance
end

CoverageReport() = CoverageReport(0, 0, Dict{Symbol,Int}(), String[])

"""
    provenance_coverage(spec::MDSpec) -> CoverageReport

For each numeric field that is allowed to carry provenance (the IR's
JSONPath-ish keys), check whether `spec.provenance` has an entry. Returns
counts + per-source breakdown + the list of missing paths so the user
can see what their LLM call dropped on the floor.

Coverage feeds quality scoring in the option-3 fine-tune flywheel:
training transcripts with high `paper`/`paper_default` ratios are higher
quality than ones dominated by `assumed`.
"""
function provenance_coverage(spec::MDSpec)::CoverageReport
    paths = _enumerate_provenance_keys(spec)
    by_source = Dict{Symbol,Int}()
    missing_paths = String[]
    n_with = 0
    for p in paths
        if haskey(spec.provenance, p)
            n_with += 1
            src = spec.provenance[p].source
            by_source[src] = get(by_source, src, 0) + 1
        else
            push!(missing_paths, p)
        end
    end
    CoverageReport(length(paths), n_with, by_source, missing_paths)
end

function _enumerate_provenance_keys(spec::MDSpec)::Vector{String}
    keys = String[]
    push!(keys, "system.n_atoms_estimate")
    push!(keys, "system.solvent.ions_NaCl_mM")
    if spec.system.solvent.membrane !== nothing
        push!(keys, "system.solvent.membrane.n_lipids")
        push!(keys, "system.solvent.membrane.chol_mol_fraction")
    end
    for (i, s) in enumerate(spec.protocol)
        if s isa MinimizeStage
            push!(keys, "protocol[$i].max_iterations")
            push!(keys, "protocol[$i].tolerance_kj_mol_nm")
        elseif s isa DynamicsStage
            push!(keys, "protocol[$i].duration_ns")
            push!(keys, "protocol[$i].dt_fs")
            push!(keys, "protocol[$i].temperature_K")
            push!(keys, "protocol[$i].friction_ps")
            s.pressure_bar !== nothing && push!(keys, "protocol[$i].pressure_bar")
            if s.restraints.selection != :none
                push!(keys, "protocol[$i].restraints.k_kj_mol_nm2")
            end
        elseif s isa FEPStage
            push!(keys, "protocol[$i].lambda_windows")
            push!(keys, "protocol[$i].duration_per_window_ns")
            push!(keys, "protocol[$i].temperature_K")
            push!(keys, "protocol[$i].dt_fs")
        elseif s isa REMDStage
            push!(keys, "protocol[$i].temperature_ladder_K")
            push!(keys, "protocol[$i].duration_per_replica_ns")
            push!(keys, "protocol[$i].exchange_attempt_period_ps")
        elseif s isa MetadynamicsStage
            push!(keys, "protocol[$i].bias_height_kj_mol")
            push!(keys, "protocol[$i].bias_deposit_period_ps")
            push!(keys, "protocol[$i].duration_ns")
            push!(keys, "protocol[$i].temperature_K")
            push!(keys, "protocol[$i].bias_factor")
            for (j, cv) in enumerate(s.cvs)
                push!(keys, "protocol[$i].cvs[$j].sigma")
            end
        end
    end
    for (k, o) in enumerate(spec.observables)
        push!(keys, "observables[$k].stride_ps")
    end
    keys
end

"""
    coverage_score(report::CoverageReport) -> Float64

Single 0-1 score. Weights `paper` highest, `paper_default` 0.7,
`assumed` 0.4, `runtime_default` 0.2, missing 0. Useful for sorting
transcripts by training-quality.
"""
function coverage_score(report::CoverageReport)::Float64
    report.total_numeric_fields == 0 && return 0.0
    weights = Dict(:paper => 1.0, :paper_default => 0.7, :user => 1.0,
                   :assumed => 0.4, :runtime_default => 0.2)
    s = 0.0
    for (src, n) in report.by_source
        s += n * get(weights, src, 0.0)
    end
    s / report.total_numeric_fields
end

# -----------------------------------------------------------------------------
# Lint

struct LintFinding
    severity::Symbol         # :info | :warn | :advisory
    rule::Symbol             # rule identifier
    path::String             # JSONPath-ish key the finding applies to
    message::String          # human-readable, ends with a remediation hint
end

struct LintReport
    findings::Vector{LintFinding}
    coverage::CoverageReport
end

LintReport() = LintReport(LintFinding[], CoverageReport())

Base.isempty(r::LintReport) = isempty(r.findings)
n_findings(r::LintReport) = length(r.findings)

function _record!(r::LintReport, severity, rule, path, msg)
    push!(r.findings, LintFinding(severity, rule, String(path), String(msg)))
    r
end

"""
    lint(spec::MDSpec) -> LintReport

Advisory analysis beyond Gates 1-3. Surfaces protocol-shape and quality
warnings the validator wouldn't catch (and shouldn't — these are
suggestions, not errors). Never blocks. Caller decides what to do with
the findings.

Rules:
  - `:short_production`     — production stage <1 ns
  - `:no_equilibration`     — production with no preceding equilibrate
  - `:trajectory_observable_no_stride`   — :trajectory observable with stride > duration
  - `:rmsd_no_trajectory`   — :rmsd / :rmsf / :rg observable but no :trajectory observable
  - `:provenance_low`       — < 50% of numeric fields have provenance entries
  - `:assumed_dominates`    — :assumed source > 50% of provenance entries
  - `:fep_short_window`     — FEP per-window < 0.1 ns
  - `:fep_few_windows`      — FEP < 5 lambda windows
  - `:remd_few_replicas`    — REMD with < 4 replicas
  - `:metad_no_well_tempered` — non-well-tempered metadynamics (rarely intended)
"""
function lint(spec::MDSpec)::LintReport
    cov = provenance_coverage(spec)
    report = LintReport(LintFinding[], cov)

    # Production-shape rules
    seen_equilibrate = false
    for (i, s) in enumerate(spec.protocol)
        if s isa DynamicsStage
            if s.role == :equilibrate
                seen_equilibrate = true
            elseif s.role == :production
                if !seen_equilibrate
                    _record!(report, :warn, :no_equilibration, "protocol[$i]",
                        "production stage with no preceding equilibrate stage; " *
                        "results may be biased by initial conditions")
                end
                if s.duration_ns < 1.0
                    _record!(report, :advisory, :short_production, "protocol[$i].duration_ns",
                        "production duration $(s.duration_ns) ns is very short; " *
                        "consider ≥1 ns for any non-toy result")
                end
            end
        end
    end

    # Observable-shape rules
    has_trajectory = any(o.type == :trajectory for o in spec.observables)
    needs_trajectory = any(o.type in (:rmsd, :rmsf, :rg) for o in spec.observables)
    if needs_trajectory && !has_trajectory
        _record!(report, :warn, :rmsd_no_trajectory, "observables",
            "computing rmsd / rmsf / rg requires a :trajectory observable; " *
            "post-run mdtraj analysis will skip without one")
    end
    total_duration = sum(s isa DynamicsStage ? s.duration_ns : 0.0 for s in spec.protocol)
    for (k, o) in enumerate(spec.observables)
        if o.type == :trajectory && o.stride_ps * 1e-3 > total_duration / 10
            _record!(report, :advisory, :trajectory_observable_no_stride,
                "observables[$k].stride_ps",
                "trajectory stride $(o.stride_ps) ps writes <10 frames over the " *
                "$(round(total_duration; digits=2)) ns total run; consider a smaller stride")
        end
    end

    # FEP / REMD / metad shape
    for (i, s) in enumerate(spec.protocol)
        if s isa FEPStage
            if length(s.lambda_windows) < 5
                _record!(report, :advisory, :fep_few_windows, "protocol[$i].lambda_windows",
                    "FEP with $(length(s.lambda_windows)) λ windows; ≥11 is typical for binding ΔG")
            end
            if s.duration_per_window_ns < 0.1
                _record!(report, :advisory, :fep_short_window,
                    "protocol[$i].duration_per_window_ns",
                    "FEP per-window $(s.duration_per_window_ns) ns; ≥0.5 ns recommended for convergence")
            end
        elseif s isa REMDStage
            if length(s.temperature_ladder_K) < 4
                _record!(report, :advisory, :remd_few_replicas,
                    "protocol[$i].temperature_ladder_K",
                    "REMD with $(length(s.temperature_ladder_K)) replicas; ≥4 typically needed for useful exchange statistics")
            end
        elseif s isa MetadynamicsStage
            if !s.well_tempered
                _record!(report, :advisory, :metad_no_well_tempered,
                    "protocol[$i].well_tempered",
                    "non-well-tempered metadynamics; well-tempered (γ>1) is the modern default for convergence")
            end
        end
    end

    # Provenance coverage
    if cov.total_numeric_fields > 0
        score = coverage_score(cov)
        if score < 0.5
            _record!(report, :warn, :provenance_low, "provenance",
                "provenance score $(round(score; digits=2)) (< 0.5); " *
                "$(length(cov.missing_paths)) of $(cov.total_numeric_fields) numeric fields lack a provenance entry")
        end
        n_assumed = get(cov.by_source, :assumed, 0)
        if cov.fields_with_provenance > 0 && n_assumed / cov.fields_with_provenance > 0.5
            _record!(report, :advisory, :assumed_dominates, "provenance",
                "$(n_assumed) of $(cov.fields_with_provenance) provenance entries are :assumed; " *
                "consider re-extracting with a stronger LLM or stricter prompt")
        end
    end

    report
end
