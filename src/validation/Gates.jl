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
            r = record_error!(r, "schema validation failed: $(result)")
        end
    catch err
        r = record_error!(r, "could not parse spec JSON: $(err)")
    end
    r
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
    for (i, s) in enumerate(spec.protocol)
        s isa DynamicsStage || continue
        if s.constraints == :none && s.dt_fs > 1.0
            r = record_warning!(r,
                "stage $i: dt=$(s.dt_fs) fs without constraints risks integrator instability; consider :h_bonds")
        end
        if s.constraints in (:h_bonds, :all_bonds) && s.dt_fs > 4.0
            r = record_warning!(r,
                "stage $i: dt=$(s.dt_fs) fs is aggressive even with constraints")
        end
        if s.dt_fs > 5.0
            r = record_error!(r, "stage $i: dt=$(s.dt_fs) fs exceeds the 5 fs hard cap")
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
    if spec.system.has_ligand && spec.force_field.ligand == :user_supplied &&
       spec.system.source.topology === nothing
        r = record_error!(r,
            "system has a ligand and ligand_ff=user_supplied, but system.source.topology is null. " *
            "v0 requires user-supplied topology for ligand systems (BYO-topology gate).")
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
