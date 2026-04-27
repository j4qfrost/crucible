# Picks a backend from the spec's required features.
#
# Policy in v0:
#   - If spec demands explicit solvent + ligand → OpenMM (no exceptions).
#   - If spec is small/CG/implicit and OpenMM is unavailable → Molly.
#   - If both are available, default to OpenMM and surface the choice + reason
#     in the Pluto UI. Molly is selected when the user explicitly asks for
#     :autodiff features or when the spec is small enough that Molly is
#     genuinely competitive.

struct BackendChoice
    backend::SimBackend
    reason::String
end

"""
    route_backend(spec; available, prefer=:auto) -> BackendChoice

`available` is a vector of backend instances the caller has constructed.
`prefer` is `:auto` (default), `:molly`, or `:openmm`.
"""
function route_backend(spec::MDSpec;
                       available::Vector{<:SimBackend},
                       prefer::Symbol=:auto)::BackendChoice
    isempty(available) && error("route_backend: no backends available")
    needed = required_features(spec)

    by_name = Dict{Symbol,SimBackend}(backend_name(b) => b for b in available)

    if prefer == :molly && haskey(by_name, :molly)
        feats = supported_features(by_name[:molly])
        if needed ⊆ feats
            return BackendChoice(by_name[:molly], "user requested Molly and feature set is supported")
        else
            missing = setdiff(needed, feats)
            error("Molly cannot satisfy required features: $(collect(missing))")
        end
    elseif prefer == :openmm && haskey(by_name, :openmm)
        return BackendChoice(by_name[:openmm], "user requested OpenMM")
    end

    # auto: prefer OpenMM for anything resembling a real protein-ligand system,
    # any v1+ enhanced-sampling stage type, or membrane.
    has_explicit_solvent = :pme in needed
    has_ligand           = :ligand in needed
    needs_openmm_only    = any(f -> f in needed,
                               [:alchemy, :remd, :metadynamics, :membrane,
                                :biased_sampling, :multi_replica, :plumed])

    if needs_openmm_only && haskey(by_name, :openmm)
        return BackendChoice(by_name[:openmm],
            "spec requires v1+ feature ($(intersect(needed, [:alchemy, :remd, :metadynamics, :membrane])) " *
            "— OpenMM-only). Routing to OpenMM.")
    end

    if (has_explicit_solvent || has_ligand) && haskey(by_name, :openmm)
        return BackendChoice(by_name[:openmm],
            "spec requires explicit solvent and/or ligand — routing to OpenMM (workhorse)")
    end

    if haskey(by_name, :molly)
        feats = supported_features(by_name[:molly])
        if needed ⊆ feats
            return BackendChoice(by_name[:molly],
                "spec is small/CG/implicit — routing to Molly (Julia-native)")
        end
    end

    if haskey(by_name, :openmm)
        return BackendChoice(by_name[:openmm],
            "Molly does not support all required features; falling back to OpenMM")
    end

    error("No backend can satisfy the spec's required features: $(collect(needed))")
end
