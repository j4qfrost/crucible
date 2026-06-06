# Repurpose-score: a one-call binding-affinity plan for a (target PDB, ligand SMILES) pair.
#
# This is the integration point the sibling `asklepius` repurposing engine calls (and the
# `apotheca` platform UI surfaces): given a repurposing candidate's structure + molecule,
# build the canonical protein-ligand decoupling-FEP MDSpec, validate it (gates 1-2, fast and
# GPU-free), and size the run. It deliberately does NOT fabricate a ΔG — a real free energy
# is GPU-hours of FEP. With `run=true` it persists the spec and hands back the exact `run`
# command, so the binding number, when it exists, comes from a real simulation, not a guess.
#
# The spec is cloned from the `:kinase_inhibitor_fep` template (Abl + Imatinib, PDB 2HYY),
# swapping in the caller's target + ligand — so it inherits the template's vetted protocol.

"""
    repurpose_score(pdb_id, smiles; budget_hours=24.0, run=false) -> Dict

Build (and optionally prepare a run for) a protein-ligand decoupling-FEP binding estimate.

Returns a JSON-ready `Dict` with the built `spec_json`, gate 1-2 `validation`, cloud
`advise` sizing, and `delta_g_kcal_mol => nothing` (`method => "spec_only"`). When `run` is
true it writes the spec to a fresh workdir and returns `method => "run_prepared"` plus the
`run_command` to execute on a GPU — never a fabricated ΔG.
"""
function repurpose_score(pdb_id::AbstractString, smiles::AbstractString;
                         budget_hours::Real=24.0, run::Bool=false)::Dict{String,Any}
    isempty(strip(smiles)) && error("repurpose_score: smiles is required")
    length(strip(pdb_id)) < 4 && error("repurpose_score: pdb_id must be a 4-character PDB code")

    # Clone the kinase-inhibitor FEP template and swap in the caller's target + ligand.
    base = get_template(:kinase_inhibitor_fep)
    source = SystemSource(type=:protein_ligand, pdb_id=String(strip(pdb_id)),
                          ligand_smiles=String(strip(smiles)))
    system = SystemSpec(source, base.system.n_atoms_estimate, true, base.system.solvent)
    spec = MDSpec(system=system, force_field=base.force_field, protocol=base.protocol,
                  observables=base.observables, provenance=base.provenance,
                  warnings=base.warnings,
                  notes="repurpose-score: protein-ligand decoupling FEP for $(pdb_id) " *
                        "+ supplied ligand (cloned from kinase_inhibitor_fep template).")
    spec_json = spec_to_json(spec)

    # Gates 1-2: schema + semantic. Fast, deterministic, no GPU / OpenFF. Loadability (gate 3)
    # and preview (gate 4) run at FEP time when the topology is actually built.
    r1 = gate_schema(spec_json)
    report = r1.ok ? _merge(r1, gate_semantic(spec)) : r1

    rec = advise(spec; budget_hours=Float64(budget_hours))
    advise_obj = rec.chosen === nothing ? nothing : Dict{String,Any}(
        "gpu"            => rec.chosen.gpu,
        "runtime_hours"  => rec.chosen.runtime_hours,
        "on_demand_usd"  => rec.chosen.on_demand_usd,
        "vram_gb"        => rec.chosen.vram_gb,
        "fits_system"    => rec.chosen.fits_system,
    )

    out = Dict{String,Any}(
        "spec_json"        => spec_json,
        "validation"       => Dict{String,Any}("ok" => report.ok,
                                               "errors" => report.errors,
                                               "warnings" => report.warnings),
        "advise"           => advise_obj,
        "delta_g_kcal_mol" => nothing,
        "method"           => "spec_only",
        "run_id"           => nothing,
    )

    if run
        # Prepare a real run; do not fabricate a ΔG. The number comes from executing this.
        workdir = mktempdir(prefix="crucible-repurpose-")
        spec_path = joinpath(workdir, "spec.json")
        write(spec_path, spec_json)
        out["method"]      = "run_prepared"
        out["workdir"]     = workdir
        out["run_command"] = "crucible run $(spec_path) --backend openmm --platform HIP"
    end

    out
end
