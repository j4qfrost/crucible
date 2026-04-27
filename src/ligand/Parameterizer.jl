# Ligand parameterization — abstract interface for SMILES → topology.
#
# Real implementation as of v1.0: subprocess-based OpenFF Toolkit + Interchange
# (matches the OpenMMBackend pattern of "render-and-shell-out", which keeps
# PythonCall + CondaPkg out of the default deps so the IR-only / LLM-only
# users don't pay a fat install cost).
#
#   * LigandParameterizer            — abstract type
#   * parameterize(p, smiles, dir)   — returns ParameterizedLigand
#   * ParameterizedLigand            — paths to AMBER prmtop / inpcrd + metadata
#
# The OpenMMBackend's _emit_system_load consumes the AMBER files via the
# existing `:user_supplied` / `:smiles` / `:protein_ligand` source paths.
#
# Hard rule (per Crucible's design): the LLM never invents force-field
# parameters. The OpenFF Sage release supplies typing + AM1-BCC charges.
# This file enforces that contract — `forcefield_name` is whatever Sage
# version the helper actually loaded; we don't paper over typing failures.

abstract type LigandParameterizer end

struct ParameterizedLigand
    smiles::String
    topology_path::String
    coordinates_path::String
    forcefield_name::Symbol           # :openff_sage_2_2_0, :gaff2, ...
    metadata::Dict{String,Any}
end

"""
    parameterize(p::LigandParameterizer, smiles, output_dir) -> ParameterizedLigand

Generate force-field parameters for a small molecule from its SMILES.
Returns paths to the prepared topology and coordinates files. Raises on
failure with a message describing the unblock path (typically `pip install
openff-toolkit openff-interchange rdkit`).
"""
function parameterize(p::LigandParameterizer, smiles::AbstractString,
                      output_dir::AbstractString)::ParameterizedLigand
    error("parameterize not implemented for $(typeof(p))")
end

# -----------------------------------------------------------------------------
# OpenFFParameterizer — real subprocess implementation.

struct OpenFFParameterizer <: LigandParameterizer
    sage_version::String      # "2.2.0", "2.1.0", etc.
    python::String            # path to a python with openff-toolkit installed
    helper_script::String     # absolute path to parameterize_openff.py
    ligand_name::String       # 3-char residue name, default "LIG"
end

function OpenFFParameterizer(; sage_version::AbstractString="2.2.0",
                              python::AbstractString="python",
                              ligand_name::AbstractString="LIG")
    helper = joinpath(@__DIR__, "parameterize_openff.py")
    OpenFFParameterizer(String(sage_version), String(python), helper, String(ligand_name))
end

# Backward-compat constructor — older callsites still pass a positional version.
OpenFFParameterizer(sage_version::AbstractString) =
    OpenFFParameterizer(sage_version=sage_version)

function parameterize(p::OpenFFParameterizer, smiles::AbstractString,
                      output_dir::AbstractString)::ParameterizedLigand
    isfile(p.helper_script) ||
        error("OpenFFParameterizer: helper script missing at $(p.helper_script)")
    isdir(output_dir) || mkpath(output_dir)

    env = copy(ENV)
    env["CRUCIBLE_LIGAND_NAME"] = p.ligand_name

    cmd = setenv(`$(p.python) $(p.helper_script) $(smiles) $(output_dir) $(p.sage_version)`, env)
    out_buf = IOBuffer()
    err_buf = IOBuffer()
    ok = try
        run(pipeline(cmd; stdout=out_buf, stderr=err_buf); wait=true)
        true
    catch err
        false
    end

    out = String(take!(out_buf))
    err_text = String(take!(err_buf))

    payload = nothing
    for line in eachline(IOBuffer(out))
        s = strip(line)
        startswith(s, "{") || continue
        try
            payload = JSON3.read(s)
        catch
            payload = nothing
        end
    end

    if payload === nothing
        msg = isempty(err_text) ? out : err_text
        error("OpenFFParameterizer: subprocess produced no JSON status. " *
              "Is $(p.python) on PATH and does it have openff-toolkit? Output:\n$(msg)")
    end

    if String(payload.status) != "ok"
        error("OpenFFParameterizer: $(payload.error)")
    end

    ParameterizedLigand(
        String(payload.smiles),
        String(payload.topology_path),
        String(payload.coordinates_path),
        Symbol(payload.forcefield),
        Dict{String,Any}(
            "ligand_name"  => String(get(payload, :ligand_name, p.ligand_name)),
            "n_atoms"      => Int(get(payload, :n_atoms, 0)),
            "total_charge" => Float64(get(payload, :total_charge, 0.0)),
            "pdb_path"     => String(get(payload, :pdb_path, "")),
            "sage_version" => p.sage_version,
        ),
    )
end

# -----------------------------------------------------------------------------
# Convenience: is the parameterizer wired up in this environment?

"""
    parameterizer_available(p::OpenFFParameterizer) -> Bool

Probe — true iff the configured python can `import openff.toolkit`.
Used by tests + the CLI to skip cleanly when the optional dep isn't
installed, rather than blowing up on the user.
"""
function parameterizer_available(p::OpenFFParameterizer)::Bool
    Sys.which(p.python) === nothing && return false
    cmd = `$(p.python) -c "import openff.toolkit"`
    try
        run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=true)
        return true
    catch
        return false
    end
end

parameterizer_available() = parameterizer_available(OpenFFParameterizer())
