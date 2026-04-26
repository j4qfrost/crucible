# Ligand parameterization — abstract interface for SMILES → topology.
#
# Stubbed at v1 (the README explicitly defers SMILES → params as the v1+
# multi-month moat). This file is the interface contract so when the real
# OpenFF integration lands, nothing else changes:
#
#   * LigandParameterizer is the abstract type
#   * parameterize(p, smiles, output_dir) -> ParameterizedLigand
#   * ParameterizedLigand carries paths to the topology + coords files
#   * The OpenMMBackend's _emit_system_load can then accept a
#     :user_supplied source whose topology was emitted by a parameterizer
#
# v1 ships a single stub; v1.5+ wires OpenFF Toolkit + Interchange via
# PythonCall behind the same interface.

abstract type LigandParameterizer end

struct ParameterizedLigand
    smiles::String
    topology_path::String
    coordinates_path::String
    forcefield_name::Symbol           # :gaff2, :openff_sage_2_2_0, etc.
    metadata::Dict{String,Any}
end

"""
    parameterize(p::LigandParameterizer, smiles, output_dir) -> ParameterizedLigand

Generate force-field parameters for a small molecule from its SMILES.
Returns paths to the prepared topology and coordinates files; the
`forcefield_name` matches one of `LIGAND_FF_ALLOWLIST`.
"""
function parameterize(p::LigandParameterizer, smiles::AbstractString,
                      output_dir::AbstractString)::ParameterizedLigand
    error("parameterize not implemented for $(typeof(p))")
end

# -----------------------------------------------------------------------------
# OpenFFParameterizer — v1 stub that throws on use.
#
# When this is implemented for real:
#   1. SMILES → RDKit conformer
#   2. OpenFF Sage 2.2 typing
#   3. AM1-BCC partial charges (via NAGL or Antechamber)
#   4. Interchange → OpenMM System
#   5. Write topology.parm7 / coordinates.rst7 (or equivalent) to output_dir
#
# Will require PythonCall + CondaPkg env (openff-toolkit + openff-interchange
# + RDKit). Keep it gated behind an optional dep so the package stays light.

struct OpenFFParameterizer <: LigandParameterizer
    sage_version::String      # "2.2.0", "2.1.0", etc.
end

OpenFFParameterizer() = OpenFFParameterizer("2.2.0")

function parameterize(::OpenFFParameterizer, ::AbstractString, ::AbstractString)::ParameterizedLigand
    error("""
    OpenFFParameterizer is a v1 stub.

    To unblock SMILES → ligand parameters, the next milestone needs:
      1. Add openff-toolkit + openff-interchange + rdkit to CondaPkg.toml
      2. Wire the SMILES → conformer → typing → charges → topology pipeline
         using PythonCall (subprocess won't cut it; the toolkit is stateful)
      3. Emit a .parm7 / .rst7 pair (or .top / .gro) into output_dir

    Until then, supply prepared topology directly via SystemSource(
        type=:user_supplied, topology=<path>, coordinates=<path>).
    """)
end
