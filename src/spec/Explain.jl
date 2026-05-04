# Human-readable summary of an MDSpec.
#
# Lifted from src/cli/CLI.jl in v1.36 so non-CLI callers (notably
# src/atproto/HekatePublisher.jl) can reuse the same prose without
# pulling in CLI's argparse + Dates surface area.
#
# Public-but-underscored on purpose: the prose isn't a stable API
# contract — it is meant for human consumption (CLI `explain`,
# atproto review-session record bodies). If a programmatic caller
# needs structured output, hit MDSpec directly.

function _explain_spec(spec::MDSpec)::String
    io = IOBuffer()
    src = spec.system.source
    print(io, "This MDSpec describes a ")
    if src.type == :smiles
        print(io, "pure-ligand simulation of `$(src.ligand_smiles)` ")
    elseif src.type == :protein_ligand
        print(io, "protein-ligand simulation of PDB `$(src.pdb_id)` with ligand `$(src.ligand_smiles)` ")
    elseif src.type in (:pdb_id, :pdb_fetch)
        print(io, "simulation of PDB `$(src.pdb_id)` (PDBFixer auto-built) ")
    else
        print(io, "simulation of a user-supplied system ")
    end
    sol = spec.system.solvent
    if sol.membrane !== nothing
        print(io, "embedded in a $(String(sol.membrane.composition)) bilayer ($(sol.membrane.n_lipids) lipids) ")
    end
    if sol.model == :vacuum
        print(io, "in vacuum")
    elseif sol.model == :implicit_GBSA
        print(io, "in implicit GBSA solvent")
    else
        print(io, "in $(String(sol.model)) water with $(sol.ions_NaCl_mM) mM NaCl")
    end
    print(io, ".\n\n")
    is_cg = spec.force_field.protein in (:martini3, :martini2_2)
    print(io, "Force field: $(String(spec.force_field.protein))")
    is_cg && print(io, " (coarse-grained — runtime requires martinize2)")
    spec.force_field.water != :vacuum && print(io, " + $(String(spec.force_field.water))")
    spec.force_field.lipid !== nothing && print(io, " + $(String(spec.force_field.lipid))")
    spec.force_field.ligand != :user_supplied && print(io, " + $(String(spec.force_field.ligand)) for the ligand")
    print(io, ".\n\n")
    print(io, "Protocol ($(length(spec.protocol)) stages):\n")
    for (i, s) in enumerate(spec.protocol)
        print(io, "  $(i). $(_stage_one_liner(s))\n")
    end
    if !isempty(spec.observables)
        print(io, "\nObservables: ", join((String(o.type) for o in spec.observables), ", "), ".\n")
    end
    if spec.system.protonation !== nothing
        print(io, "\nConstant-pH MD at pH $(spec.system.protonation.pH) ",
              "(titrating: $(join(spec.system.protonation.titrating_residues, ", "))).\n")
    end
    if !isempty(spec.warnings)
        print(io, "\n⚠ Warnings:\n")
        for w in spec.warnings; print(io, "  - $(w)\n"); end
    end
    String(take!(io))
end

_stage_one_liner(s::MinimizeStage) =
    "Minimize ($(s.max_iterations) iterations to tol=$(s.tolerance_kj_mol_nm) kJ/mol/nm)."

function _stage_one_liner(s::DynamicsStage)
    role = s.role == :production ? "Production" : "Equilibrate"
    base = "$(role) $(String(s.ensemble)) for $(s.duration_ns) ns at $(s.temperature_K) K"
    if s.ensemble == :NPT
        base *= ", $(s.pressure_bar) bar"
    end
    if s.restraints.selection != :none
        base *= " with $(String(s.restraints.selection)) restraints (k=$(s.restraints.k_kj_mol_nm2))"
    end
    base * "."
end

function _stage_one_liner(s::FEPStage)
    "Alchemical $(String(s.kind)) FEP across $(length(s.lambda_windows)) λ windows " *
    "× $(s.duration_per_window_ns) ns each, target=`$(s.target_selection)`."
end

function _stage_one_liner(s::REMDStage)
    "Replica-exchange MD: $(length(s.temperature_ladder_K)) replicas " *
    "$(round(first(s.temperature_ladder_K); digits=1))–" *
    "$(round(last(s.temperature_ladder_K); digits=1)) K, " *
    "$(s.duration_per_replica_ns) ns per replica, " *
    "exchange every $(s.exchange_attempt_period_ps) ps."
end

function _stage_one_liner(s::MetadynamicsStage)
    cv_summary = join((cv.name * " (" * String(cv.kind) * ")" for cv in s.cvs), ", ")
    extra = s.well_tempered ? " (well-tempered, γ=$(s.bias_factor))" : ""
    "Metadynamics for $(s.duration_ns) ns biasing $(cv_summary)$(extra)."
end
