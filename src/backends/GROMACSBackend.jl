# GROMACSBackend — scaffolding only.
#
# Phase A weeks 7-9 of docs/COMMERCIAL_VALIDATION_PLAN.md. Adds GROMACS as
# a recognized backend so the Router stops silently routing GROMACS-flavored
# requests to OpenMM, but does not yet emit a runnable .top/.mdp deck.
# Full design context: docs/GROMACS_SCOPING.md.
#
# Status of methods:
#   - supported_features  — implemented (MVP coverage map per the scoping doc)
#   - validate_spec       — implemented (rejects out-of-MVP specs with clear
#                           "use OpenMM" / "deferred" messages)
#   - estimate_resources  — implemented (delegates to a GROMACS-throughput
#                           heuristic; treat as ±50% until benchmarked)
#   - render_script       — NotImplementedError; the renderer body lands
#                           alongside the first pilot that asks for it
#   - prepare / preview_run / run! — NotImplementedError
#
# Why this scaffolding ships before the renderer body:
#   - The Router needs to know GROMACS is acknowledged-but-deferred so it
#     can route appropriately rather than falsely claiming GROMACS support
#     via OpenMM.
#   - Tier-2 cold emails (docs/CAMPAIGN_2026Q2.md) reference this file as
#     proof-of-scope; the path is committed even if the renderer isn't.
#   - When the body lands, no public-interface changes follow — pilots
#     consuming this Backend's IR contract today get bytes-stable upgrades.

struct GROMACSBackend <: SimBackend
    name::Symbol
end

GROMACSBackend() = GROMACSBackend(:gromacs)

backend_name(b::GROMACSBackend) = b.name

function supported_features(::GROMACSBackend)::Set{Symbol}
    # MVP coverage per docs/GROMACS_SCOPING.md — explicit-solvent atomistic
    # MD with the standard ensembles. FEP / metadynamics / CG / membranes
    # are deferred and will surface as validate_spec errors.
    Set([
        :nvt, :npt, :nve,
        :explicit_solvent,
        :constraints, :pme,
        :thermostat, :langevin,
        :barostat, :ligand,
    ])
end

function validate_spec(b::GROMACSBackend, spec::MDSpec)::ValidationReport
    r = ValidationReport()

    # Renderer body isn't shipped yet — this is the load-bearing rejection.
    r = record_error!(r,
        "GROMACSBackend: renderer not yet implemented. The IR is recognized; "
        * "the .top/.mdp emit is scoped in docs/GROMACS_SCOPING.md and will "
        * "land alongside the first pilot that asks for it. Use --backend openmm "
        * "for now.")

    # Below: structural rejections that will outlive the renderer-not-yet-impl
    # error. When the renderer ships, these stay; the line above goes away.

    for (i, s) in enumerate(spec.protocol)
        if s isa FEPStage
            r = record_error!(r,
                "GROMACSBackend: stage $i is FEPStage. GROMACS-FEP is its own "
                * "dialect (free-energy = yes, init-lambda, couple-lambdas) and "
                * "is deferred until concrete pilot demand. Route to OpenMMBackend.")
        elseif s isa REMDStage
            r = record_error!(r,
                "GROMACSBackend: stage $i is REMDStage. Phase 2 of the GROMACS "
                * "scoping (gmx mdrun -multidir). Not in MVP. Route to OpenMMBackend.")
        elseif s isa MetadynamicsStage
            r = record_error!(r,
                "GROMACSBackend: stage $i is MetadynamicsStage. GROMACS-PLUMED "
                * "requires a separate compile of GROMACS itself; deferred. "
                * "Route to OpenMMBackend.")
        end
    end

    if spec.system.solvent.membrane !== nothing
        r = record_error!(r,
            "GROMACSBackend: lipid bilayers are Phase 2 of the GROMACS scoping "
            * "(needs CHARMM-GUI deck wiring). Not in MVP. Route to OpenMMBackend.")
    end

    if spec.system.protonation !== nothing
        r = record_error!(r,
            "GROMACSBackend: constant-pH MD has multiple incompatible GROMACS "
            * "forks; deferred indefinitely. Route to OpenMMBackend.")
    end

    if spec.force_field.protein in (:martini3, :martini2_2)
        r = record_error!(r,
            "GROMACSBackend: coarse-grained Martini support requires martinize2 + "
            * "Martini-specific .itp files. Deferred. Route to MollyBackend (CG path) "
            * "or OpenMMBackend.")
    end

    feats = supported_features(b)
    needed = required_features(spec)
    missing_feats = setdiff(needed, feats)
    if !isempty(missing_feats)
        r = record_error!(r,
            "GROMACSBackend cannot satisfy required features in MVP: "
            * "$(collect(missing_feats)). See docs/GROMACS_SCOPING.md coverage map.")
    end
    r
end

function estimate_resources(::GROMACSBackend, spec::MDSpec)::ResourceEstimate
    total_ns = sum(s isa DynamicsStage ? s.duration_ns : 0.0 for s in spec.protocol)
    ResourceEstimate(spec.system.n_atoms_estimate, total_ns, :gromacs,
        "GROMACS throughput at typical 25-50k atom solvated proteins is similar to OpenMM "
        * "(~25-200 ns/day depending on GPU). Treat as ±50% pending benchmark.")
end

function render_script(::GROMACSBackend, spec::MDSpec;
                       output_dir::AbstractString)::String
    error("GROMACSBackend.render_script: renderer not yet implemented. "
          * "See docs/GROMACS_SCOPING.md for the MVP coverage map. "
          * "Use OpenMMBackend (--backend openmm) until the GROMACS body lands.")
end

function prepare(::GROMACSBackend, spec::MDSpec, workdir::String)::PreparedJob
    error("GROMACSBackend.prepare: scaffolding only — see docs/GROMACS_SCOPING.md.")
end

function preview_run(::GROMACSBackend, job::PreparedJob;
                     n_steps::Int=100)::PreviewReport
    error("GROMACSBackend.preview_run: scaffolding only — see docs/GROMACS_SCOPING.md.")
end

function run!(::GROMACSBackend, job::PreparedJob;
              on_progress=identity)::SimResult
    error("GROMACSBackend.run!: scaffolding only — see docs/GROMACS_SCOPING.md.")
end

function collect_artifacts(::GROMACSBackend, result::SimResult)::Vector{SimArtifact}
    SimArtifact[]
end
