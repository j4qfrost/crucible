# KineticsBackend — sketch implementation for reaction-network simulations
# via Catalyst.jl + DifferentialEquations.jl. Stub at v0.5: satisfies the
# SimBackend contract so the Router and validation pipeline accept the
# backend, but `prepare`/`preview_run`/`run!` throw NotImplementedError.
#
# When this lands for real:
#   * `render_script(spec) -> Catalyst.@reaction_network DSL + ODEProblem
#     + solve(...) calls
#   * `run!` evaluates the rendered script in-process (Catalyst is lighter
#     than Molly so direct invocation is fine)
#   * Observables: timeseries of species amounts → CSV.

struct KineticsBackend <: SimBackend
    name::Symbol
end

KineticsBackend() = KineticsBackend(:kinetics)

backend_name(b::KineticsBackend) = b.name

function supported_features(::KineticsBackend)::Set{Symbol}
    Set([:ode_integrator, :reaction_network])
end

function validate_spec(::KineticsBackend, spec::KineticsSpec)::ValidationReport
    r = ValidationReport()
    if isempty(spec.species)
        r = record_error!(r, "KineticsBackend: at least one species is required")
    end
    if isempty(spec.reactions)
        r = record_error!(r, "KineticsBackend: at least one reaction is required")
    end
    if spec.duration_s <= 0
        r = record_error!(r, "KineticsBackend: duration_s must be > 0")
    end
    return r
end

function estimate_resources(::KineticsBackend, spec::KineticsSpec)::ResourceEstimate
    ResourceEstimate(length(spec.species), spec.duration_s, :kinetics,
        "ODE solve scales with stiffness × duration; typically CPU-only and seconds-fast")
end

function prepare(::KineticsBackend, ::KineticsSpec, ::AbstractString)::PreparedJob
    error("KineticsBackend.prepare is a v0.5 stub — Catalyst.jl integration is the next milestone")
end

function preview_run(::KineticsBackend, ::PreparedJob; n_steps::Int=100)::PreviewReport
    PreviewReport(false, false, nothing, nothing,
        ["KineticsBackend preview_run is a stub — see Catalyst.jl integration ticket"])
end

function run!(::KineticsBackend, job::PreparedJob; on_progress=identity)::SimResult
    SimResult(job, false, String[], "KineticsBackend.run! is a stub at v0.5")
end

function collect_artifacts(::KineticsBackend, ::SimResult)::Vector{SimArtifact}
    SimArtifact[]
end
