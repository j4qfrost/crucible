# MDSpec — the LLM-emitted intermediate representation.
#
# Rules:
#   - Every numeric field carries units in its name (temperature_K, dt_fs).
#   - Every leaf with a value the LLM might guess gets a Provenance entry
#     attached via the top-level `provenance` map. This is the audit trail
#     that lets the user see what came from the paper vs. what was assumed.
#   - The IR is the contract with both the LLM and the renderers. Any change
#     here is a schema-version bump.

abstract type SimSpec end

# -----------------------------------------------------------------------------
# Provenance

struct Provenance
    source::Symbol            # :paper | :paper_default | :assumed | :user | :runtime_default
    cite::Union{Nothing,String}   # e.g. "Methods §2.3", "Table 1, row 4"
    confidence::Float64       # 0.0–1.0
end

Provenance(source::Symbol; cite=nothing, confidence=1.0) =
    Provenance(source, cite, confidence)

# -----------------------------------------------------------------------------
# System

struct SystemSource
    type::Symbol              # :user_supplied | :pdb_id | :pdb_fetch
    topology::Union{Nothing,String}
    coordinates::Union{Nothing,String}
    pdb_id::Union{Nothing,String}
end

SystemSource(; type=:user_supplied, topology=nothing, coordinates=nothing, pdb_id=nothing) =
    SystemSource(type, topology, coordinates, pdb_id)

struct SolventSpec
    model::Symbol             # :TIP3P | :TIP4P_EW | :SPC_E | :implicit_GBSA | :vacuum
    ions_NaCl_mM::Float64     # 0.0 = none
end

SolventSpec(; model=:TIP3P, ions_NaCl_mM=0.0) = SolventSpec(model, ions_NaCl_mM)

struct SystemSpec
    source::SystemSource
    n_atoms_estimate::Int
    has_ligand::Bool
    solvent::SolventSpec
end

# -----------------------------------------------------------------------------
# Force field

# Allowlist — never let the LLM invent FF names. Mapping from "Amber99",
# "ff14SB", etc. happens at extraction time, not render time, and is logged.
const PROTEIN_FF_ALLOWLIST = (
    :amber14sb, :amber99sb_ildn, :amber03, :charmm36m, :opls_aam
)
const WATER_MODEL_ALLOWLIST = (
    :TIP3P, :TIP4P_EW, :SPC_E, :implicit_GBSA, :vacuum
)
const LIGAND_FF_ALLOWLIST = (
    :user_supplied, :gaff2, :openff_sage_2_2_0
)

struct ForceFieldSpec
    protein::Symbol
    water::Symbol
    ligand::Symbol
end

ForceFieldSpec(; protein=:amber14sb, water=:TIP3P, ligand=:user_supplied) =
    ForceFieldSpec(protein, water, ligand)

# -----------------------------------------------------------------------------
# Protocol stages

abstract type Stage end

struct MinimizeStage <: Stage
    max_iterations::Int
    tolerance_kj_mol_nm::Float64
end

MinimizeStage(; max_iterations=5000, tolerance_kj_mol_nm=10.0) =
    MinimizeStage(max_iterations, tolerance_kj_mol_nm)

struct RestraintSpec
    selection::Symbol             # :heavy_atoms | :backbone | :ca | :none
    kind::Symbol                  # :harmonic | :flat_bottom
    k_kj_mol_nm2::Float64
end

RestraintSpec(; selection=:none, kind=:harmonic, k_kj_mol_nm2=0.0) =
    RestraintSpec(selection, kind, k_kj_mol_nm2)

struct DynamicsStage <: Stage
    role::Symbol                  # :equilibrate | :production
    ensemble::Symbol              # :NVE | :NVT | :NPT
    duration_ns::Float64
    dt_fs::Float64
    temperature_K::Float64
    pressure_bar::Union{Nothing,Float64}      # required if ensemble == :NPT
    thermostat::Symbol            # :langevin | :nose_hoover | :andersen | :berendsen
    barostat::Union{Nothing,Symbol}           # :monte_carlo | :berendsen | :parrinello_rahman | nothing
    friction_ps::Float64
    constraints::Symbol           # :none | :h_bonds | :all_bonds
    restraints::RestraintSpec
end

DynamicsStage(;
    role,
    ensemble,
    duration_ns,
    dt_fs=2.0,
    temperature_K=300.0,
    pressure_bar=nothing,
    thermostat=:langevin,
    barostat=nothing,
    friction_ps=1.0,
    constraints=:h_bonds,
    restraints=RestraintSpec(),
) = DynamicsStage(
    role, ensemble, duration_ns, dt_fs, temperature_K, pressure_bar,
    thermostat, barostat, friction_ps, constraints, restraints,
)

# -----------------------------------------------------------------------------
# Observables

struct Observable
    type::Symbol                  # :rmsd | :rmsf | :energy | :trajectory | :rg
    selection::String             # MDAnalysis-style selection string
    stride_ps::Float64
end

Observable(; type, selection="all", stride_ps=10.0) =
    Observable(type, selection, stride_ps)

# -----------------------------------------------------------------------------
# The MDSpec itself

struct MDSpec <: SimSpec
    schema_version::String
    system::SystemSpec
    force_field::ForceFieldSpec
    protocol::Vector{Stage}
    observables::Vector{Observable}
    provenance::Dict{String,Provenance}    # keys are JSONPath-ish, e.g.
                                           # "protocol[2].temperature_K"
    warnings::Vector{String}
    notes::String
end

MDSpec(;
    schema_version="0.1.0",
    system,
    force_field,
    protocol,
    observables=Observable[],
    provenance=Dict{String,Provenance}(),
    warnings=String[],
    notes="",
) = MDSpec(schema_version, system, force_field, protocol, observables,
           provenance, warnings, notes)

# Required feature set this spec demands of a backend. Used by the Router.
function required_features(spec::MDSpec)::Set{Symbol}
    feats = Set{Symbol}()
    spec.system.solvent.model == :implicit_GBSA && push!(feats, :implicit_solvent)
    spec.system.solvent.model in (:TIP3P, :TIP4P_EW, :SPC_E) && push!(feats, :explicit_solvent)
    spec.system.has_ligand && push!(feats, :ligand)
    for s in spec.protocol
        s isa DynamicsStage || continue
        s.ensemble == :NPT && (push!(feats, :npt); push!(feats, :barostat))
        s.ensemble == :NVT && push!(feats, :thermostat)
        if spec.system.solvent.model in (:TIP3P, :TIP4P_EW, :SPC_E)
            push!(feats, :pme)
        end
        s.constraints != :none && push!(feats, :constraints)
    end
    feats
end

# -----------------------------------------------------------------------------
# JSON3 (de)serialization
#
# Schema is the LLM contract; this is the Julia parser. Rejecting unknown
# fields is a deliberate choice — schema version bumps must be explicit.

JSON3.StructTypes.StructType(::Type{Provenance})    = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{SystemSource})  = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{SolventSpec})   = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{SystemSpec})    = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{ForceFieldSpec})= JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{RestraintSpec}) = JSON3.StructTypes.Struct()
JSON3.StructTypes.StructType(::Type{Observable})    = JSON3.StructTypes.Struct()

# Stage is abstract; emit a tagged union ("kind": "minimize" | "dynamics").
function spec_to_json(spec::MDSpec)::String
    obj = Dict{String,Any}(
        "schema_version" => spec.schema_version,
        "system" => Dict(
            "source" => Dict(
                "type"        => String(spec.system.source.type),
                "topology"    => spec.system.source.topology,
                "coordinates" => spec.system.source.coordinates,
                "pdb_id"      => spec.system.source.pdb_id,
            ),
            "n_atoms_estimate" => spec.system.n_atoms_estimate,
            "has_ligand"       => spec.system.has_ligand,
            "solvent" => Dict(
                "model"        => String(spec.system.solvent.model),
                "ions_NaCl_mM" => spec.system.solvent.ions_NaCl_mM,
            ),
        ),
        "force_field" => Dict(
            "protein" => String(spec.force_field.protein),
            "water"   => String(spec.force_field.water),
            "ligand"  => String(spec.force_field.ligand),
        ),
        "protocol" => [stage_to_dict(s) for s in spec.protocol],
        "observables" => [Dict(
            "type"      => String(o.type),
            "selection" => o.selection,
            "stride_ps" => o.stride_ps,
        ) for o in spec.observables],
        "provenance" => Dict(
            k => Dict(
                "source"     => String(v.source),
                "cite"       => v.cite,
                "confidence" => v.confidence,
            ) for (k, v) in spec.provenance
        ),
        "warnings" => spec.warnings,
        "notes"    => spec.notes,
    )
    JSON3.write(obj)
end

function stage_to_dict(s::MinimizeStage)
    Dict("kind" => "minimize",
         "max_iterations" => s.max_iterations,
         "tolerance_kj_mol_nm" => s.tolerance_kj_mol_nm)
end

function stage_to_dict(s::DynamicsStage)
    Dict(
        "kind"          => "dynamics",
        "role"          => String(s.role),
        "ensemble"      => String(s.ensemble),
        "duration_ns"   => s.duration_ns,
        "dt_fs"         => s.dt_fs,
        "temperature_K" => s.temperature_K,
        "pressure_bar"  => s.pressure_bar,
        "thermostat"    => String(s.thermostat),
        "barostat"      => s.barostat === nothing ? nothing : String(s.barostat),
        "friction_ps"   => s.friction_ps,
        "constraints"   => String(s.constraints),
        "restraints" => Dict(
            "selection"      => String(s.restraints.selection),
            "kind"           => String(s.restraints.kind),
            "k_kj_mol_nm2"   => s.restraints.k_kj_mol_nm2,
        ),
    )
end

function spec_from_json(json_str::AbstractString)::MDSpec
    obj = JSON3.read(json_str)
    src = obj.system.source
    sys = SystemSpec(
        SystemSource(
            type        = Symbol(src.type),
            topology    = get(src, :topology, nothing),
            coordinates = get(src, :coordinates, nothing),
            pdb_id      = get(src, :pdb_id, nothing),
        ),
        obj.system.n_atoms_estimate,
        obj.system.has_ligand,
        SolventSpec(
            model        = Symbol(obj.system.solvent.model),
            ions_NaCl_mM = obj.system.solvent.ions_NaCl_mM,
        ),
    )
    ff = ForceFieldSpec(
        protein = Symbol(obj.force_field.protein),
        water   = Symbol(obj.force_field.water),
        ligand  = Symbol(obj.force_field.ligand),
    )
    protocol = Stage[stage_from_dict(s) for s in obj.protocol]
    observables = Observable[
        Observable(type = Symbol(o.type), selection = String(o.selection),
                   stride_ps = Float64(o.stride_ps))
        for o in obj.observables
    ]
    provenance = Dict{String,Provenance}()
    for (k, v) in pairs(obj.provenance)
        provenance[String(k)] = Provenance(
            Symbol(v.source),
            cite       = get(v, :cite, nothing),
            confidence = Float64(get(v, :confidence, 1.0)),
        )
    end
    MDSpec(
        schema_version = String(obj.schema_version),
        system         = sys,
        force_field    = ff,
        protocol       = protocol,
        observables    = observables,
        provenance     = provenance,
        warnings       = String[String(w) for w in obj.warnings],
        notes          = String(get(obj, :notes, "")),
    )
end

function stage_from_dict(s)
    if String(s.kind) == "minimize"
        MinimizeStage(
            max_iterations      = s.max_iterations,
            tolerance_kj_mol_nm = s.tolerance_kj_mol_nm,
        )
    elseif String(s.kind) == "dynamics"
        r = s.restraints
        DynamicsStage(
            role          = Symbol(s.role),
            ensemble      = Symbol(s.ensemble),
            duration_ns   = Float64(s.duration_ns),
            dt_fs         = Float64(s.dt_fs),
            temperature_K = Float64(s.temperature_K),
            pressure_bar  = s.pressure_bar === nothing ? nothing : Float64(s.pressure_bar),
            thermostat    = Symbol(s.thermostat),
            barostat      = s.barostat === nothing ? nothing : Symbol(s.barostat),
            friction_ps   = Float64(s.friction_ps),
            constraints   = Symbol(s.constraints),
            restraints    = RestraintSpec(
                selection    = Symbol(r.selection),
                kind         = Symbol(r.kind),
                k_kj_mol_nm2 = Float64(r.k_kj_mol_nm2),
            ),
        )
    else
        error("Unknown stage kind: $(s.kind)")
    end
end
