# Backend interface — locks plugin extensibility in from day one.
#
# v0 ships MollyBackend + OpenMMBackend. Future modalities (kinetics ODEs,
# PBPK compartments, Catalyst.jl reaction networks) implement this same
# contract with their own SimSpec subtype.

abstract type SimBackend end

# A prepared, on-disk job. Backends hold whatever they need (workdir, the
# rendered script path, a serialized OpenMM System, etc.).
struct PreparedJob
    backend_name::Symbol
    workdir::String
    script_path::String
    metadata::Dict{String,Any}
end

struct ResourceEstimate
    n_atoms::Int
    total_ns::Float64
    backend_name::Symbol
    notes::String
end

struct PreviewReport
    ok::Bool
    energies_finite::Bool
    temperature_drift_K::Union{Nothing,Float64}
    max_force_kj_mol_nm::Union{Nothing,Float64}
    messages::Vector{String}
end

struct SimResult
    job::PreparedJob
    success::Bool
    artifacts::Vector{String}     # paths
    log::String
end

struct SimArtifact
    path::String
    kind::Symbol                  # :trajectory | :timeseries | :checkpoint | :log
    description::String
end

struct ValidationReport
    ok::Bool
    errors::Vector{String}
    warnings::Vector{String}
end

ValidationReport() = ValidationReport(true, String[], String[])

function record_error!(r::ValidationReport, msg::AbstractString)
    push!(r.errors, msg)
    return ValidationReport(false, r.errors, r.warnings)
end

function record_warning!(r::ValidationReport, msg::AbstractString)
    push!(r.warnings, msg)
    return r
end

# -----------------------------------------------------------------------------
# Required interface — backends must implement these. We provide stubs that
# throw informative errors so missing methods surface immediately rather than
# manifesting as a no-method dispatch error deep in the pipeline.

backend_name(b::SimBackend) = error("backend_name not implemented for $(typeof(b))")

supported_features(b::SimBackend)::Set{Symbol} =
    error("supported_features not implemented for $(typeof(b))")

function validate_spec(b::SimBackend, ::SimSpec)::ValidationReport
    error("validate_spec not implemented for $(typeof(b))")
end

function estimate_resources(b::SimBackend, ::SimSpec)::ResourceEstimate
    error("estimate_resources not implemented for $(typeof(b))")
end

function prepare(b::SimBackend, ::SimSpec, workdir::AbstractString)::PreparedJob
    error("prepare not implemented for $(typeof(b))")
end

function preview_run(b::SimBackend, ::PreparedJob; n_steps::Int=100)::PreviewReport
    error("preview_run not implemented for $(typeof(b))")
end

function run!(b::SimBackend, ::PreparedJob; on_progress=identity)::SimResult
    error("run! not implemented for $(typeof(b))")
end

function collect_artifacts(b::SimBackend, ::SimResult)::Vector{SimArtifact}
    error("collect_artifacts not implemented for $(typeof(b))")
end
