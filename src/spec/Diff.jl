# Spec diff — structured comparison of two MDSpecs.
#
# Returns a SpecDiff with three buckets: changed (a -> b), only_in_a, only_in_b.
# Designed for the option-3 fine-tune flywheel: when a user edits an
# LLM-emitted spec, diff_specs(llm_spec, user_spec) becomes a training signal
# for what the LLM got wrong.
#
# Render via `render(::MarkdownRenderer, ::SpecDiff)` for human consumption,
# or read the raw fields for programmatic use.

struct SpecDiff
    changed::Vector{Tuple{String,Any,Any}}     # (path, before, after)
    only_in_a::Vector{Tuple{String,Any}}       # (path, value)
    only_in_b::Vector{Tuple{String,Any}}       # (path, value)
end

SpecDiff() = SpecDiff(Tuple{String,Any,Any}[], Tuple{String,Any}[], Tuple{String,Any}[])

Base.isempty(d::SpecDiff) = isempty(d.changed) && isempty(d.only_in_a) && isempty(d.only_in_b)
Base.length(d::SpecDiff) = length(d.changed) + length(d.only_in_a) + length(d.only_in_b)

"""
    diff_specs(a::MDSpec, b::MDSpec) -> SpecDiff

Recursive structural diff. Walks system, force_field, protocol stages,
observables, and the top-level metadata fields.
"""
function diff_specs(a::MDSpec, b::MDSpec)::SpecDiff
    d = SpecDiff()
    _cmp_field!(d, "schema_version",      a.schema_version, b.schema_version)

    # System
    _cmp_field!(d, "system.source.type",  String(a.system.source.type),  String(b.system.source.type))
    _cmp_field!(d, "system.source.topology",    a.system.source.topology,    b.system.source.topology)
    _cmp_field!(d, "system.source.coordinates", a.system.source.coordinates, b.system.source.coordinates)
    _cmp_field!(d, "system.source.pdb_id",      a.system.source.pdb_id,      b.system.source.pdb_id)
    _cmp_field!(d, "system.n_atoms_estimate", a.system.n_atoms_estimate, b.system.n_atoms_estimate)
    _cmp_field!(d, "system.has_ligand",       a.system.has_ligand,       b.system.has_ligand)
    _cmp_field!(d, "system.solvent.model",     String(a.system.solvent.model), String(b.system.solvent.model))
    _cmp_field!(d, "system.solvent.ions_NaCl_mM", a.system.solvent.ions_NaCl_mM, b.system.solvent.ions_NaCl_mM)

    # Force field
    _cmp_field!(d, "force_field.protein", String(a.force_field.protein), String(b.force_field.protein))
    _cmp_field!(d, "force_field.water",   String(a.force_field.water),   String(b.force_field.water))
    _cmp_field!(d, "force_field.ligand",  String(a.force_field.ligand),  String(b.force_field.ligand))

    # Protocol
    n = max(length(a.protocol), length(b.protocol))
    for i in 1:n
        sa = i <= length(a.protocol) ? a.protocol[i] : nothing
        sb = i <= length(b.protocol) ? b.protocol[i] : nothing
        if sa === nothing
            push!(d.only_in_b, ("protocol[$i]", _stage_summary(sb)))
        elseif sb === nothing
            push!(d.only_in_a, ("protocol[$i]", _stage_summary(sa)))
        else
            _cmp_stage!(d, "protocol[$i]", sa, sb)
        end
    end

    # Observables (compared as a multiset by (type, selection))
    obs_a = Set((String(o.type), o.selection) for o in a.observables)
    obs_b = Set((String(o.type), o.selection) for o in b.observables)
    for (t, s) in setdiff(obs_a, obs_b)
        push!(d.only_in_a, ("observables[$t/$s]", "stride_ps"))
    end
    for (t, s) in setdiff(obs_b, obs_a)
        push!(d.only_in_b, ("observables[$t/$s]", "stride_ps"))
    end

    d
end

function _cmp_field!(d::SpecDiff, path::AbstractString, va, vb)
    if va != vb
        push!(d.changed, (String(path), va, vb))
    end
end

function _cmp_stage!(d::SpecDiff, base::AbstractString, sa::MinimizeStage, sb::MinimizeStage)
    _cmp_field!(d, "$base.kind", "minimize", "minimize")
    _cmp_field!(d, "$base.max_iterations",      sa.max_iterations, sb.max_iterations)
    _cmp_field!(d, "$base.tolerance_kj_mol_nm", sa.tolerance_kj_mol_nm, sb.tolerance_kj_mol_nm)
end

function _cmp_stage!(d::SpecDiff, base::AbstractString, sa::DynamicsStage, sb::DynamicsStage)
    for f in (:role, :ensemble, :duration_ns, :dt_fs, :temperature_K, :pressure_bar,
              :thermostat, :barostat, :friction_ps, :constraints)
        va = getfield(sa, f); vb = getfield(sb, f)
        va = va isa Symbol ? String(va) : va
        vb = vb isa Symbol ? String(vb) : vb
        _cmp_field!(d, "$base.$(f)", va, vb)
    end
    _cmp_field!(d, "$base.restraints.selection",    String(sa.restraints.selection),    String(sb.restraints.selection))
    _cmp_field!(d, "$base.restraints.kind",         String(sa.restraints.kind),         String(sb.restraints.kind))
    _cmp_field!(d, "$base.restraints.k_kj_mol_nm2", sa.restraints.k_kj_mol_nm2,         sb.restraints.k_kj_mol_nm2)
end

function _cmp_stage!(d::SpecDiff, base::AbstractString, sa::Stage, sb::Stage)
    # Mismatched stage types — record as a kind change
    push!(d.changed, ("$base.kind", string(typeof(sa).name.name), string(typeof(sb).name.name)))
end

_stage_summary(::MinimizeStage) = "minimize"
_stage_summary(s::DynamicsStage) = string(String(s.role), " ", String(s.ensemble), " ", s.duration_ns, "ns")
