# KineticsSpec — alternate SimSpec subtype for reaction-network / enzyme
# kinetics simulations (Catalyst.jl + DifferentialEquations.jl backends).
#
# Sketch only at v0.5: the type and the schema are real, but no backend
# implements the contract yet. Lives here as proof that the SimBackend
# abstraction is fit for purpose beyond molecular dynamics — the same
# Router, validation gates, advisor, and CLI work for kinetics with no
# changes once a backend ships.

struct Reaction
    name::String
    reactants::Vector{Tuple{String,Int}}    # (species_name, stoichiometry)
    products::Vector{Tuple{String,Int}}
    rate_constant::Float64                  # in mass-action units
    rate_units::Symbol                      # :per_second | :per_M_s | :per_M2_s
end

struct Species
    name::String
    initial_amount::Float64                 # in mol or M depending on rate_units
end

struct KineticsSpec <: SimSpec
    schema_version::String
    species::Vector{Species}
    reactions::Vector{Reaction}
    duration_s::Float64
    output_stride_s::Float64
    provenance::Dict{String,Provenance}
    warnings::Vector{String}
    notes::String
end

KineticsSpec(;
    schema_version="0.1.0",
    species,
    reactions,
    duration_s,
    output_stride_s=1e-3,
    provenance=Dict{String,Provenance}(),
    warnings=String[],
    notes="",
) = KineticsSpec(schema_version, species, reactions, duration_s, output_stride_s,
                 provenance, warnings, notes)

# Required-features hook so the Router can dispatch correctly.
function required_features(spec::KineticsSpec)::Set{Symbol}
    Set([:ode_integrator, :reaction_network])
end
