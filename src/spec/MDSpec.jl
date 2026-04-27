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
    type::Symbol              # :user_supplied | :pdb_id | :pdb_fetch | :smiles | :protein_ligand
    topology::Union{Nothing,String}
    coordinates::Union{Nothing,String}
    pdb_id::Union{Nothing,String}
    ligand_smiles::Union{Nothing,String}
end

SystemSource(; type=:user_supplied, topology=nothing, coordinates=nothing,
              pdb_id=nothing, ligand_smiles=nothing) =
    SystemSource(type, topology, coordinates, pdb_id, ligand_smiles)

struct LipidBilayer
    composition::Symbol            # :POPC | :POPE | :DPPC | :mixed_POPC_chol
    n_lipids::Int                  # total lipid count (both leaflets)
    chol_mol_fraction::Float64     # 0.0–0.5
end

LipidBilayer(; composition=:POPC, n_lipids=128, chol_mol_fraction=0.0) =
    LipidBilayer(composition, n_lipids, chol_mol_fraction)

const LIPID_FF_ALLOWLIST = (:charmm36_lipid, :lipid21, :slipids)
const LIPID_COMPOSITION_ALLOWLIST = (:POPC, :POPE, :DPPC, :mixed_POPC_chol)

struct SolventSpec
    model::Symbol             # :TIP3P | :TIP4P_EW | :SPC_E | :implicit_GBSA | :vacuum
    ions_NaCl_mM::Float64     # 0.0 = none
    membrane::Union{Nothing,LipidBilayer}    # nothing for non-membrane systems
end

SolventSpec(; model=:TIP3P, ions_NaCl_mM=0.0, membrane=nothing) =
    SolventSpec(model, ions_NaCl_mM, membrane)

"""
    ProtonationSpec

Constant-pH MD scaffolding (v2 IR; no runtime execution in v1.x). Used
to tag a system as titrating: which residues can change protonation
state, what pH to sample at, and how often to attempt state transitions.

The renderer emits an import for the chosen reference implementation
(`openmm-constph-py`) and raises `NotImplementedError` with a clear
remediation hint. The IR shape is stable so user-facing transcripts
collected today don't break when a real implementation lands.
"""
struct ProtonationSpec
    pH::Float64                              # solvent pH; 0–14
    titrating_residues::Vector{String}       # selectors, e.g. ["resid 35", "resname HIS"]
    transition_attempt_per_ps::Float64        # 0 = disabled (state held)
    salt_concentration_M::Float64            # background ions for the implicit titrant
end

ProtonationSpec(; pH=7.0, titrating_residues=String[],
                  transition_attempt_per_ps=0.0,
                  salt_concentration_M=0.15) =
    ProtonationSpec(pH, titrating_residues, transition_attempt_per_ps, salt_concentration_M)

struct SystemSpec
    source::SystemSource
    n_atoms_estimate::Int
    has_ligand::Bool
    solvent::SolventSpec
    protonation::Union{Nothing,ProtonationSpec}    # nothing for non-titrating systems
end

SystemSpec(source::SystemSource, n_atoms_estimate::Int, has_ligand::Bool,
           solvent::SolventSpec) =
    SystemSpec(source, n_atoms_estimate, has_ligand, solvent, nothing)

# -----------------------------------------------------------------------------
# Force field

# Allowlist — never let the LLM invent FF names. Mapping from "Amber99",
# "ff14SB", etc. happens at extraction time, not render time, and is logged.
const PROTEIN_FF_ALLOWLIST = (
    :amber14sb, :amber99sb_ildn, :amber03, :charmm36m, :opls_aam,
    # Coarse-grained (v2 IR scaffolding; renderer stub raises) —
    # the Martini ecosystem ships incompatible toolchains, so we
    # commit to the IR shape now and defer the renderer to v2.
    :martini3, :martini2_2,
)
const CG_PROTEIN_FF = (:martini3, :martini2_2)
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
    lipid::Union{Nothing,Symbol}     # nothing for non-membrane systems
end

ForceFieldSpec(; protein=:amber14sb, water=:TIP3P, ligand=:user_supplied,
                lipid=nothing) =
    ForceFieldSpec(protein, water, ligand, lipid)

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

"""
    REMDStage <: Stage

Replica-exchange molecular dynamics. Spawns `length(temperature_ladder_K)`
replicas, each at a different temperature, and attempts swaps between
adjacent replicas every `exchange_attempt_period_ps` picoseconds. Requires
`openmmtools.multistate` at script-runtime.

The temperature ladder should be exponentially spaced over the range of
interest (e.g. 300, 320, 342, 365, ... K) so adjacent-replica energy
overlap stays usable. The validation gate enforces strict monotonicity.
"""
struct REMDStage <: Stage
    temperature_ladder_K::Vector{Float64}
    duration_per_replica_ns::Float64
    exchange_attempt_period_ps::Float64
    ensemble::Symbol              # :NVT | :NPT
    pressure_bar::Union{Nothing,Float64}
    dt_fs::Float64
    thermostat::Symbol
    friction_ps::Float64
    constraints::Symbol
end

REMDStage(;
    temperature_ladder_K,
    duration_per_replica_ns=0.5,
    exchange_attempt_period_ps=1.0,
    ensemble=:NVT,
    pressure_bar=nothing,
    dt_fs=2.0,
    thermostat=:langevin,
    friction_ps=1.0,
    constraints=:h_bonds,
) = REMDStage(temperature_ladder_K, duration_per_replica_ns,
              exchange_attempt_period_ps, ensemble, pressure_bar, dt_fs,
              thermostat, friction_ps, constraints)

"""
    MetadynamicsStage <: Stage

Metadynamics with one or more collective variables (CVs). Bias deposits
gaussians on the CV-space potential at `bias_deposit_period_ps` cadence.
Requires `openmm-plumed` at script-runtime; the renderer emits a PLUMED
script block which `openmm-plumed` evaluates as an OpenMM Force.

CV kinds (`Crucible.CollectiveVariable`):
  - `:distance`   selects two atom groups (or atoms); unit nm
  - `:angle`      selects three atom groups; unit rad
  - `:dihedral`   selects four atom groups; unit rad
  - `:rmsd`       reference structure path + selection; unit nm
"""
struct CollectiveVariable
    kind::Symbol                  # :distance | :angle | :dihedral | :rmsd
    name::String                  # PLUMED label, e.g. "d1"
    selection::String             # OpenMM-style atom selection
    reference::Union{Nothing,String} # path to reference PDB for :rmsd
    sigma::Float64                # gaussian width in CV units
end

CollectiveVariable(; kind, name, selection, reference=nothing, sigma=0.1) =
    CollectiveVariable(kind, name, selection, reference, sigma)

struct MetadynamicsStage <: Stage
    cvs::Vector{CollectiveVariable}
    bias_height_kj_mol::Float64
    bias_deposit_period_ps::Float64
    duration_ns::Float64
    well_tempered::Bool
    bias_factor::Float64          # well-tempered γ (1.0 = standard MD)
    ensemble::Symbol
    temperature_K::Float64
    pressure_bar::Union{Nothing,Float64}
    dt_fs::Float64
    thermostat::Symbol
    friction_ps::Float64
    constraints::Symbol
end

MetadynamicsStage(;
    cvs,
    bias_height_kj_mol=1.0,
    bias_deposit_period_ps=1.0,
    duration_ns=10.0,
    well_tempered=true,
    bias_factor=10.0,
    ensemble=:NVT,
    temperature_K=300.0,
    pressure_bar=nothing,
    dt_fs=2.0,
    thermostat=:langevin,
    friction_ps=1.0,
    constraints=:h_bonds,
) = MetadynamicsStage(cvs, bias_height_kj_mol, bias_deposit_period_ps,
                     duration_ns, well_tempered, bias_factor, ensemble,
                     temperature_K, pressure_bar, dt_fs, thermostat,
                     friction_ps, constraints)

"""
    FEPStage <: Stage

Alchemical free-energy stage. The stage runs `length(lambda_windows)` short
MD windows, each at a different λ value scaling the alchemical interactions,
and emits per-window samples for MBAR analysis. Requires `openmmtools` at
script-runtime (the renderer is environment-agnostic).

The renderer treats `target_selection` as the alchemical region (typically
a ligand). `kind` distinguishes:
  - `:decouple`  — turn off intermolecular interactions (binding free energy)
  - `:annihilate` — turn off all interactions including intramolecular (solvation)
"""
struct FEPStage <: Stage
    kind::Symbol                  # :decouple | :annihilate
    target_selection::String      # OpenMM-style atom selection, e.g. "resname LIG"
    lambda_windows::Vector{Float64}
    duration_per_window_ns::Float64
    ensemble::Symbol              # :NVT | :NPT
    temperature_K::Float64
    pressure_bar::Union{Nothing,Float64}
    dt_fs::Float64
    thermostat::Symbol
    friction_ps::Float64
    constraints::Symbol
end

FEPStage(;
    kind=:decouple,
    target_selection,
    lambda_windows=[0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
    duration_per_window_ns=0.5,
    ensemble=:NPT,
    temperature_K=300.0,
    pressure_bar=1.0,
    dt_fs=2.0,
    thermostat=:langevin,
    friction_ps=1.0,
    constraints=:h_bonds,
) = FEPStage(kind, target_selection, lambda_windows, duration_per_window_ns,
             ensemble, temperature_K, pressure_bar, dt_fs, thermostat,
             friction_ps, constraints)

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
    schema_version="0.3.0",
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
    spec.system.solvent.membrane !== nothing && push!(feats, :membrane, :anisotropic_barostat)
    spec.system.protonation !== nothing && push!(feats, :constph, :titration)
    spec.system.has_ligand && push!(feats, :ligand)
    spec.force_field.protein in CG_PROTEIN_FF && push!(feats, :coarse_grain)
    for s in spec.protocol
        if s isa FEPStage
            push!(feats, :alchemy)
            s.ensemble == :NPT && (push!(feats, :npt); push!(feats, :barostat))
            continue
        end
        if s isa REMDStage
            push!(feats, :remd, :multi_replica)
            length(s.temperature_ladder_K) >= 4 && push!(feats, :multi_gpu_eligible)
            s.ensemble == :NPT && (push!(feats, :npt); push!(feats, :barostat))
            continue
        end
        if s isa MetadynamicsStage
            push!(feats, :metadynamics, :biased_sampling, :plumed)
            s.ensemble == :NPT && (push!(feats, :npt); push!(feats, :barostat))
            continue
        end
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
                "type"          => String(spec.system.source.type),
                "topology"      => spec.system.source.topology,
                "coordinates"   => spec.system.source.coordinates,
                "pdb_id"        => spec.system.source.pdb_id,
                "ligand_smiles" => spec.system.source.ligand_smiles,
            ),
            "n_atoms_estimate" => spec.system.n_atoms_estimate,
            "has_ligand"       => spec.system.has_ligand,
            "protonation"      => spec.system.protonation === nothing ?
                                  nothing :
                                  Dict(
                                      "pH"                       => spec.system.protonation.pH,
                                      "titrating_residues"       => spec.system.protonation.titrating_residues,
                                      "transition_attempt_per_ps" => spec.system.protonation.transition_attempt_per_ps,
                                      "salt_concentration_M"     => spec.system.protonation.salt_concentration_M,
                                  ),
            "solvent" => Dict(
                "model"        => String(spec.system.solvent.model),
                "ions_NaCl_mM" => spec.system.solvent.ions_NaCl_mM,
                "membrane"     => spec.system.solvent.membrane === nothing ?
                                  nothing :
                                  Dict(
                                      "composition"        => String(spec.system.solvent.membrane.composition),
                                      "n_lipids"           => spec.system.solvent.membrane.n_lipids,
                                      "chol_mol_fraction"  => spec.system.solvent.membrane.chol_mol_fraction,
                                  ),
            ),
        ),
        "force_field" => Dict(
            "protein" => String(spec.force_field.protein),
            "water"   => String(spec.force_field.water),
            "ligand"  => String(spec.force_field.ligand),
            "lipid"   => spec.force_field.lipid === nothing ? nothing :
                         String(spec.force_field.lipid),
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

function stage_to_dict(s::REMDStage)
    Dict(
        "kind"                       => "remd",
        "temperature_ladder_K"       => s.temperature_ladder_K,
        "duration_per_replica_ns"    => s.duration_per_replica_ns,
        "exchange_attempt_period_ps" => s.exchange_attempt_period_ps,
        "ensemble"                   => String(s.ensemble),
        "pressure_bar"               => s.pressure_bar,
        "dt_fs"                      => s.dt_fs,
        "thermostat"                 => String(s.thermostat),
        "friction_ps"                => s.friction_ps,
        "constraints"                => String(s.constraints),
    )
end

function stage_to_dict(s::MetadynamicsStage)
    Dict(
        "kind"                   => "metadynamics",
        "cvs" => [Dict(
            "kind"      => String(cv.kind),
            "name"      => cv.name,
            "selection" => cv.selection,
            "reference" => cv.reference,
            "sigma"     => cv.sigma,
        ) for cv in s.cvs],
        "bias_height_kj_mol"     => s.bias_height_kj_mol,
        "bias_deposit_period_ps" => s.bias_deposit_period_ps,
        "duration_ns"            => s.duration_ns,
        "well_tempered"          => s.well_tempered,
        "bias_factor"            => s.bias_factor,
        "ensemble"               => String(s.ensemble),
        "temperature_K"          => s.temperature_K,
        "pressure_bar"           => s.pressure_bar,
        "dt_fs"                  => s.dt_fs,
        "thermostat"             => String(s.thermostat),
        "friction_ps"            => s.friction_ps,
        "constraints"            => String(s.constraints),
    )
end

function stage_to_dict(s::FEPStage)
    Dict(
        "kind"                   => "free_energy",
        "fep_kind"               => String(s.kind),
        "target_selection"       => s.target_selection,
        "lambda_windows"         => s.lambda_windows,
        "duration_per_window_ns" => s.duration_per_window_ns,
        "ensemble"               => String(s.ensemble),
        "temperature_K"          => s.temperature_K,
        "pressure_bar"           => s.pressure_bar,
        "dt_fs"                  => s.dt_fs,
        "thermostat"             => String(s.thermostat),
        "friction_ps"            => s.friction_ps,
        "constraints"            => String(s.constraints),
    )
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
            type          = Symbol(src.type),
            topology      = get(src, :topology, nothing),
            coordinates   = get(src, :coordinates, nothing),
            pdb_id        = get(src, :pdb_id, nothing),
            ligand_smiles = get(src, :ligand_smiles, nothing),
        ),
        obj.system.n_atoms_estimate,
        obj.system.has_ligand,
        SolventSpec(
            model        = Symbol(obj.system.solvent.model),
            ions_NaCl_mM = obj.system.solvent.ions_NaCl_mM,
            membrane     = let m = get(obj.system.solvent, :membrane, nothing)
                m === nothing ? nothing : LipidBilayer(
                    composition       = Symbol(m.composition),
                    n_lipids          = Int(m.n_lipids),
                    chol_mol_fraction = Float64(m.chol_mol_fraction),
                )
            end,
        ),
        let p = get(obj.system, :protonation, nothing)
            p === nothing ? nothing : ProtonationSpec(
                pH = Float64(p.pH),
                titrating_residues = String[String(s) for s in p.titrating_residues],
                transition_attempt_per_ps = Float64(p.transition_attempt_per_ps),
                salt_concentration_M = Float64(p.salt_concentration_M),
            )
        end,
    )
    ff = ForceFieldSpec(
        protein = Symbol(obj.force_field.protein),
        water   = Symbol(obj.force_field.water),
        ligand  = Symbol(obj.force_field.ligand),
        lipid   = let l = get(obj.force_field, :lipid, nothing)
            l === nothing ? nothing : Symbol(l)
        end,
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
    elseif String(s.kind) == "remd"
        REMDStage(
            temperature_ladder_K       = Float64[Float64(x) for x in s.temperature_ladder_K],
            duration_per_replica_ns    = Float64(s.duration_per_replica_ns),
            exchange_attempt_period_ps = Float64(s.exchange_attempt_period_ps),
            ensemble                   = Symbol(s.ensemble),
            pressure_bar               = s.pressure_bar === nothing ? nothing : Float64(s.pressure_bar),
            dt_fs                      = Float64(s.dt_fs),
            thermostat                 = Symbol(s.thermostat),
            friction_ps                = Float64(s.friction_ps),
            constraints                = Symbol(s.constraints),
        )
    elseif String(s.kind) == "metadynamics"
        MetadynamicsStage(
            cvs = CollectiveVariable[
                CollectiveVariable(
                    kind      = Symbol(cv.kind),
                    name      = String(cv.name),
                    selection = String(cv.selection),
                    reference = get(cv, :reference, nothing) === nothing ?
                                nothing : String(cv.reference),
                    sigma     = Float64(cv.sigma),
                ) for cv in s.cvs
            ],
            bias_height_kj_mol     = Float64(s.bias_height_kj_mol),
            bias_deposit_period_ps = Float64(s.bias_deposit_period_ps),
            duration_ns            = Float64(s.duration_ns),
            well_tempered          = Bool(s.well_tempered),
            bias_factor            = Float64(s.bias_factor),
            ensemble               = Symbol(s.ensemble),
            temperature_K          = Float64(s.temperature_K),
            pressure_bar           = s.pressure_bar === nothing ? nothing : Float64(s.pressure_bar),
            dt_fs                  = Float64(s.dt_fs),
            thermostat             = Symbol(s.thermostat),
            friction_ps            = Float64(s.friction_ps),
            constraints            = Symbol(s.constraints),
        )
    elseif String(s.kind) == "free_energy"
        FEPStage(
            kind                   = Symbol(s.fep_kind),
            target_selection       = String(s.target_selection),
            lambda_windows         = Float64[Float64(x) for x in s.lambda_windows],
            duration_per_window_ns = Float64(s.duration_per_window_ns),
            ensemble               = Symbol(s.ensemble),
            temperature_K          = Float64(s.temperature_K),
            pressure_bar           = s.pressure_bar === nothing ? nothing : Float64(s.pressure_bar),
            dt_fs                  = Float64(s.dt_fs),
            thermostat             = Symbol(s.thermostat),
            friction_ps            = Float64(s.friction_ps),
            constraints            = Symbol(s.constraints),
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
