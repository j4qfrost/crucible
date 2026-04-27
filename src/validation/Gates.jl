# Validation pipeline.
#
# Five gates, in order:
#   1. Schema       — JSON Schema validation against schema.json
#   2. Semantic     — Julia rules the schema cannot express
#   3. Loadability  — backend can load topology + coords (lives in backend.validate_spec)
#   4. Preview run  — short integration smoke (lives in backend.preview_run)
#   5. User confirm — Pluto UI gate
#
# This file owns gates 1 and 2. Gate 3 calls into the backend; gate 4 is the
# backend's preview_run; gate 5 is the UI. Sequencing is non-negotiable: if
# gate N fails, gate N+1 does not run.

const _SCHEMA_PATH = joinpath(@__DIR__, "..", "spec", "schema.json")

function _load_schema()
    JSONSchema.Schema(JSON3.read(read(_SCHEMA_PATH, String), Dict))
end

# Lazy-init schema once per process — JSONSchema parsing isn't free.
const _SCHEMA = Ref{Union{Nothing,JSONSchema.Schema}}(nothing)
function _schema()
    if _SCHEMA[] === nothing
        _SCHEMA[] = _load_schema()
    end
    _SCHEMA[]
end

# -----------------------------------------------------------------------------
# Gate 1 — JSON Schema

"""
    gate_schema(spec_json::AbstractString) -> ValidationReport

Validate the wire-format JSON against schema.json. Catches the LLM emitting
unknown fields, bad enums, out-of-range numerics, or missing required keys.
"""
function gate_schema(spec_json::AbstractString)::ValidationReport
    r = ValidationReport()
    try
        obj = JSON3.read(spec_json, Dict)
        result = JSONSchema.validate(_schema(), obj)
        if result !== nothing
            r = record_error!(r, _humanize_schema_error(result))
        end
    catch err
        r = record_error!(r, "could not parse spec JSON: $(err)")
    end
    r
end

# JSONSchema's raw error string is structurally precise but pretty cryptic
# at first glance. This translator catches the common shapes (enum mismatch,
# missing required, additionalProperties) and emits a one-sentence rewrite.
# Falls back to the raw string for anything we don't recognize yet.
function _humanize_schema_error(err)::String
    s = string(err)
    # JSONSchema.jl reports paths like "Object[\"field\"]" with quoted keys
    if (m = match(r"value at path (\S+) is invalid: (.+)", s)) !== nothing
        path = String(m.captures[1])
        detail = String(m.captures[2])
        # Common detail patterns
        if (em = match(r"value (\S+) is not in enum (\[.+?\])", detail)) !== nothing
            got = String(em.captures[1])
            allowed = String(em.captures[2])
            return "schema error at $(path): value $(got) is not one of $(allowed)"
        end
        if occursin("required", lowercase(detail))
            return "schema error at $(path): required field is missing or null"
        end
        if occursin("additionalProperties", detail) ||
           occursin("additional properties", lowercase(detail))
            return "schema error at $(path): unknown field (additional properties not allowed at this level)"
        end
        return "schema error at $(path): $(detail)"
    end
    "schema validation failed: $(s)"
end

# -----------------------------------------------------------------------------
# Gate 2 — Semantic rules
#
# Things the schema cannot express. Each rule is its own function so they are
# independently testable and easy to add/remove.

function gate_semantic(spec::MDSpec)::ValidationReport
    r = ValidationReport()
    for rule in (
        _rule_npt_requires_barostat,
        _rule_constraints_timestep,
        _rule_implicit_solvent_no_barostat,
        _rule_production_after_equilibration,
        _rule_ligand_topology_required,
        _rule_temperature_sane,
        _rule_npt_pressure_required,
        _rule_vacuum_no_ions,
        _rule_langevin_friction_nonzero,
        _rule_nve_timestep,
        _rule_smiles_source_coherence,
        _rule_fep_lambda_monotonic,
        _rule_remd_ladder_monotonic,
        _rule_metadynamics_cv_atoms,
        _rule_membrane_coherence,
        _rule_protonation_coherence,
        _rule_coarse_grain_coherence,
    )
        r = rule(spec, r)
    end
    r
end

function _rule_npt_requires_barostat(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.ensemble == :NPT && s.barostat === nothing
            r = record_error!(r, "stage $i: NPT ensemble requires a barostat (got nothing)")
        end
    end
    r
end

function _rule_constraints_timestep(spec::MDSpec, r::ValidationReport)
    # Coarse-grained dynamics (Martini etc.) routinely run at 20-25 fs;
    # the atomistic 5 fs hard cap doesn't apply.
    is_cg = spec.force_field.protein in CG_PROTEIN_FF
    cap_fs = is_cg ? 30.0 : 5.0
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if !is_cg && s.constraints == :none && s.dt_fs > 1.0
            r = record_warning!(r,
                "stage $i: dt=$(s.dt_fs) fs without constraints risks integrator instability; consider :h_bonds")
        end
        if !is_cg && s.constraints in (:h_bonds, :all_bonds) && s.dt_fs > 4.0
            r = record_warning!(r,
                "stage $i: dt=$(s.dt_fs) fs is aggressive even with constraints")
        end
        if s.dt_fs > cap_fs
            r = record_error!(r, "stage $i: dt=$(s.dt_fs) fs exceeds the $(cap_fs) fs hard cap")
        end
    end
    r
end

function _rule_implicit_solvent_no_barostat(spec::MDSpec, r::ValidationReport)
    if spec.system.solvent.model == :implicit_GBSA
        for (i, s) in enumerate(spec.protocol)
            s isa DynamicsStage || continue
            if s.ensemble == :NPT
                r = record_error!(r,
                    "stage $i: NPT is incoherent with implicit solvent (no volume to vary)")
            end
        end
    end
    r
end

function _rule_production_after_equilibration(spec::MDSpec, r::ValidationReport)
    seen_equilibration = false
    for (i, s) in enumerate(spec.protocol)
        if s isa DynamicsStage
            if s.role == :equilibrate
                seen_equilibration = true
            elseif s.role == :production && !seen_equilibration
                r = record_warning!(r,
                    "stage $i: production stage has no preceding equilibration; results may be biased by initial conditions")
            end
        end
    end
    r
end

function _rule_ligand_topology_required(spec::MDSpec, r::ValidationReport)
    src = spec.system.source
    # SMILES-based sources generate the topology at prepare-time / runtime —
    # no user-supplied topology required.
    if src.type in (:smiles, :protein_ligand)
        return r
    end
    if spec.system.has_ligand && spec.force_field.ligand == :user_supplied &&
       src.topology === nothing
        r = record_error!(r,
            "system has a ligand and ligand_ff=user_supplied, but system.source.topology is null. " *
            "Either supply a topology, or switch source.type to :smiles / :protein_ligand " *
            "and force_field.ligand to :openff_sage_2_2_0.")
    end
    r
end

function _rule_temperature_sane(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.temperature_K < 50
            r = record_warning!(r, "stage $i: temperature=$(s.temperature_K) K is below the typical biological range; verify this is intentional")
        elseif s.temperature_K > 500
            r = record_warning!(r, "stage $i: temperature=$(s.temperature_K) K is high; verify this is intentional (REMD?)")
        end
    end
    r
end

function _rule_npt_pressure_required(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.ensemble == :NPT && s.pressure_bar === nothing
            r = record_error!(r, "stage $i: NPT ensemble requires pressure_bar to be set")
        end
    end
    r
end

function _rule_vacuum_no_ions(spec::MDSpec, r::ValidationReport)
    if spec.system.solvent.model == :vacuum && spec.system.solvent.ions_NaCl_mM > 0
        r = record_error!(r,
            "system.solvent: ions_NaCl_mM=$(spec.system.solvent.ions_NaCl_mM) is incoherent with model=:vacuum (no medium for ion concentration)")
    end
    r
end

function _rule_langevin_friction_nonzero(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.thermostat == :langevin && s.friction_ps == 0
            r = record_warning!(r,
                "stage $i: langevin thermostat with friction_ps=0 is degenerate (no coupling); consider 1.0 ps^-1")
        end
    end
    r
end

function _rule_coarse_grain_coherence(spec::MDSpec, r::ValidationReport)
    is_cg = spec.force_field.protein in CG_PROTEIN_FF
    is_cg || return r
    if spec.system.solvent.model in (:TIP3P, :TIP4P_EW, :SPC_E)
        r = record_error!(r,
            "force_field.protein=:$(spec.force_field.protein) is coarse-grained; " *
            "atomistic water model :$(spec.system.solvent.model) is incoherent. " *
            "Use :vacuum for Martini (Martini's polarizable water is supplied by the topology)")
    end
    if spec.force_field.lipid !== nothing
        r = record_warning!(r,
            "Martini protein FF + atomistic lipid FF $(spec.force_field.lipid) is unusual; " *
            "Martini bilayers are typically supplied as user_supplied topology")
    end
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.dt_fs < 10.0
            r = record_warning!(r,
                "stage $i: Martini typically uses 20–25 fs timesteps; got $(s.dt_fs) fs " *
                "(coarse-grained dynamics are stable at much larger steps than atomistic)")
            break   # one warning is enough
        end
    end
    r
end

function _rule_protonation_coherence(spec::MDSpec, r::ValidationReport)
    p = spec.system.protonation
    p === nothing && return r
    if isempty(p.titrating_residues)
        r = record_error!(r,
            "system.protonation set but titrating_residues is empty — list at least one " *
            "selector (e.g. [\"resname HIS\", \"resid 35\"])")
    end
    if spec.system.solvent.model in (:vacuum, :implicit_GBSA)
        r = record_warning!(r,
            "constant-pH MD with solvent.model=:$(spec.system.solvent.model); the standard " *
            "openmm-constph implementation assumes explicit water — verify your reference impl")
    end
    # Constant-pH currently doesn't compose with membrane-anisotropic barostat
    # (no published implementation handles both). Warn loudly.
    if spec.system.solvent.membrane !== nothing
        r = record_warning!(r,
            "constant-pH MD + membrane bilayer is unsupported by openmm-constph and " *
            "would require a custom integrator")
    end
    r
end

function _rule_membrane_coherence(spec::MDSpec, r::ValidationReport)
    mem = spec.system.solvent.membrane
    mem === nothing && return r
    if spec.force_field.lipid === nothing
        r = record_error!(r,
            "system.solvent.membrane is set but force_field.lipid is null — pick one of " *
            "(:charmm36_lipid, :lipid21, :slipids)")
    end
    if spec.system.solvent.model in (:vacuum, :implicit_GBSA)
        r = record_error!(r,
            "membrane systems require explicit water (TIP3P / TIP4P_EW / SPC_E); " *
            "got solvent.model=:$(spec.system.solvent.model)")
    end
    if mem.composition == :mixed_POPC_chol && mem.chol_mol_fraction <= 0
        r = record_error!(r,
            "system.solvent.membrane.composition=:mixed_POPC_chol requires chol_mol_fraction > 0")
    end
    if mem.composition != :mixed_POPC_chol && mem.chol_mol_fraction > 0
        r = record_warning!(r,
            "system.solvent.membrane.chol_mol_fraction=$(mem.chol_mol_fraction) is ignored when " *
            "composition=$(mem.composition); switch to :mixed_POPC_chol to honor it")
    end
    # Membrane systems should use anisotropic NPT coupling (semi-isotropic
    # — XY coupled, Z independent). Crucible's renderer handles this; warn
    # if the user picked NVT for production (rare for membranes).
    for (i, s) in enumerate(spec.protocol)
        if s isa DynamicsStage && s.role == :production && s.ensemble == :NVT
            r = record_warning!(r,
                "stage $i: production NVT in a membrane system is unusual; " *
                "membranes typically run NPT with anisotropic coupling to relax box dimensions")
            break
        end
    end
    r
end

function _rule_remd_ladder_monotonic(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa REMDStage || continue
        T = s.temperature_ladder_K
        if length(T) < 2
            r = record_error!(r, "stage $i: REMD requires ≥2 temperatures (got $(length(T)))")
            continue
        end
        for k in 2:length(T)
            if T[k] <= T[k-1]
                r = record_error!(r,
                    "stage $i: REMD temperature_ladder_K must be strictly increasing; rung $(k-1)→$k drops or repeats")
                break
            end
        end
        if any(t -> t < 50 || t > 1000, T)
            r = record_warning!(r,
                "stage $i: REMD ladder includes temperatures outside the typical 50–1000 K range")
        end
        if s.ensemble == :NPT && s.pressure_bar === nothing
            r = record_error!(r, "stage $i: REMD NPT ensemble requires pressure_bar to be set")
        end
        # Check exchange acceptance heuristic — energy gap scales as
        # sqrt(N) * (T_{k+1}-T_k); we just warn if any rung is >1.3x of the
        # previous, which usually gives <20% acceptance for proteins.
        for k in 2:length(T)
            ratio = T[k] / T[k-1]
            if ratio > 1.3
                r = record_warning!(r,
                    "stage $i: REMD rung $(k-1)→$k has T-ratio $(round(ratio; digits=2))x (>1.3); " *
                    "exchange acceptance likely low for systems above ~5k atoms")
                break
            end
        end
    end
    r
end

function _rule_metadynamics_cv_atoms(spec::MDSpec, r::ValidationReport)
    cv_atom_counts = Dict(:distance => 2, :angle => 3, :dihedral => 4)
    for (i, s) in enumerate(spec.protocol)
        s isa MetadynamicsStage || continue
        if isempty(s.cvs)
            r = record_error!(r, "stage $i: metadynamics requires ≥1 collective variable")
            continue
        end
        for (j, cv) in enumerate(s.cvs)
            if cv.kind == :rmsd && (cv.reference === nothing || isempty(cv.reference))
                r = record_error!(r,
                    "stage $i: metadynamics CV[$j] kind=:rmsd requires a reference PDB path")
            end
            if haskey(cv_atom_counts, cv.kind)
                # Best-effort count: number of comma-separated atom groups.
                ngroups = count(==(','), cv.selection) + 1
                if ngroups != cv_atom_counts[cv.kind]
                    r = record_warning!(r,
                        "stage $i: metadynamics CV[$j] kind=:$(cv.kind) typically needs " *
                        "$(cv_atom_counts[cv.kind]) atom groups in selection (got selection " *
                        "with $(ngroups) comma-separated entries)")
                end
            end
        end
        if s.well_tempered && s.bias_factor <= 1.0
            r = record_error!(r,
                "stage $i: well_tempered=true requires bias_factor > 1.0 (got $(s.bias_factor))")
        end
        if s.ensemble == :NPT && s.pressure_bar === nothing
            r = record_error!(r, "stage $i: metadynamics NPT ensemble requires pressure_bar")
        end
    end
    r
end

function _rule_fep_lambda_monotonic(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa FEPStage || continue
        λs = s.lambda_windows
        if length(λs) < 2
            r = record_error!(r, "stage $i: FEP requires ≥2 lambda windows (got $(length(λs)))")
            continue
        end
        if first(λs) != 0.0 || last(λs) != 1.0
            r = record_warning!(r,
                "stage $i: FEP lambda windows should bracket [0.0, 1.0]; got [$(first(λs)), $(last(λs))]")
        end
        for k in 2:length(λs)
            if λs[k] <= λs[k-1]
                r = record_error!(r,
                    "stage $i: FEP lambda windows must be strictly monotonic; window $(k-1)→$k drops or repeats")
                break
            end
        end
        if any(λ -> λ < 0.0 || λ > 1.0, λs)
            r = record_error!(r, "stage $i: FEP lambda values must lie in [0, 1]")
        end
        if s.ensemble == :NPT && s.pressure_bar === nothing
            r = record_error!(r, "stage $i: FEP NPT ensemble requires pressure_bar to be set")
        end
    end
    r
end

function _rule_smiles_source_coherence(spec::MDSpec, r::ValidationReport)
    src = spec.system.source
    src.type in (:smiles, :protein_ligand) || return r
    if src.ligand_smiles === nothing || isempty(src.ligand_smiles)
        r = record_error!(r,
            "system.source.type=$(src.type) requires a non-empty ligand_smiles")
    end
    if spec.force_field.ligand == :user_supplied
        r = record_error!(r,
            "system.source.type=$(src.type) requires force_field.ligand to be a real " *
            "parameterizer (e.g. :openff_sage_2_2_0); :user_supplied is incoherent here")
    end
    if src.type == :protein_ligand && (src.pdb_id === nothing || length(src.pdb_id) < 4)
        r = record_error!(r,
            "system.source.type=:protein_ligand requires a 4-character pdb_id")
    end
    r
end

function _rule_nve_timestep(spec::MDSpec, r::ValidationReport)
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.ensemble == :NVE && s.dt_fs > 1.0
            r = record_warning!(r,
                "stage $i: dt=$(s.dt_fs) fs in NVE ensemble risks energy drift; production NVE typically uses 0.5-1.0 fs")
        end
    end
    r
end

# -----------------------------------------------------------------------------
# Gate 3 — Loadability (delegates to backend)

function gate_loadability(b::SimBackend, spec::MDSpec)::ValidationReport
    validate_spec(b, spec)
end

# -----------------------------------------------------------------------------
# Gate 4 — Preview run
#
# Runs an abbreviated version of the script (CRUCIBLE_PREVIEW_STEPS clamps
# every dynamics stage). Asserts: process exited cleanly, last log lines
# contain finite energies. Reject before allocating GPU time.

function gate_preview(b::SimBackend, job::PreparedJob; n_steps::Int=100)::ValidationReport
    r = ValidationReport()
    report = preview_run(b, job; n_steps=n_steps)
    if !report.energies_finite
        r = record_error!(r, "preview run produced non-finite energies (NaN or blowup)")
    end
    if !report.ok
        r = record_error!(r, "preview run failed; messages: $(join(report.messages, "; "))")
    end
    for m in report.messages
        r = record_warning!(r, m)
    end
    r
end

# -----------------------------------------------------------------------------
# Composed pipeline

"""
    run_validation(spec_json, spec, backend) -> ValidationReport

Run gates 1-3 in sequence. If a gate fails, later gates do not run — their
findings are not present in the returned report.
"""
function run_validation(spec_json::AbstractString,
                        spec::MDSpec,
                        backend::SimBackend)::ValidationReport
    r1 = gate_schema(spec_json)
    r1.ok || return r1
    r2 = gate_semantic(spec)
    r2.ok || return _merge(r1, r2)
    r3 = gate_loadability(backend, spec)
    _merge(_merge(r1, r2), r3)
end

function _merge(a::ValidationReport, b::ValidationReport)::ValidationReport
    ValidationReport(a.ok && b.ok, vcat(a.errors, b.errors), vcat(a.warnings, b.warnings))
end
