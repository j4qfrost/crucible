# SMILES → MD pipeline.
#
# Demonstrates the v1 OpenFFParameterizer + :smiles SystemSource path.
# Builds an MDSpec for ethanol-in-vacuum from scratch — no LLM, no PDB,
# no user-supplied topology — and emits a runnable OpenMM script.
#
# Run with:  julia --project examples/from_smiles.jl

using Crucible

println("Crucible: SMILES → MD example")
println("=" ^ 50)

smiles = "CCO"  # ethanol
println("ligand SMILES: $(smiles)")

# 1. Hand-build the MDSpec. In a real session this would come out of
#    `transpile(provider, paper_text)` — here we skip the LLM round-trip.
spec = MDSpec(
    system = SystemSpec(
        SystemSource(type=:smiles, ligand_smiles=smiles),
        9, true,
        SolventSpec(model=:vacuum, ions_NaCl_mM=0.0),
    ),
    force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                 ligand=:openff_sage_2_2_0),
    protocol = Stage[
        MinimizeStage(max_iterations=200),
        DynamicsStage(role=:equilibrate, ensemble=:NVT, duration_ns=0.01,
                      dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
        DynamicsStage(role=:production, ensemble=:NVT, duration_ns=0.1,
                      dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
    ],
    observables = Observable[
        Observable(type=:trajectory, selection="all", stride_ps=1.0),
    ],
    provenance = Dict{String,Provenance}(),
    warnings = String[],
    notes = "ethanol-in-vacuum demo, parameterized via OpenFF Sage 2.2.0",
)

println("\n1. MDSpec built ($(length(spec.protocol)) stages)")

# 2. Validate.
report = Crucible.run_validation(Crucible.spec_to_json(spec), spec, OpenMMBackend())
println("\n2. validation: ok=$(report.ok)")
for w in report.warnings; println("   warn:  $(w)"); end
for e in report.errors;   println("   error: $(e)"); end

# 3. Probe parameterizer availability.
p = OpenFFParameterizer()
avail = parameterizer_available(p)
println("\n3. OpenFF parameterizer ($(p.python)): $(avail ? "available" : "not installed")")

if !avail
    println("   To enable: pip install openff-toolkit openff-interchange rdkit")
    println("   The MDSpec is fully formed and the renderer is exercised below;")
    println("   only prepare()/run! need OpenFF to materialize the topology.")
end

# 4. Render — works without OpenFF; the script just references ligand.parm7
#    which prepare() would have placed in the workdir.
script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/from_smiles")
println("\n4. rendered: $(length(script)) bytes")
println("   first 240 chars:")
println("   ", first(script, 240), "...")

# 5. If OpenFF is wired up, run the prepare() round-trip end-to-end.
if avail
    workdir = mktempdir(prefix="crucible-from-smiles-")
    println("\n5. prepare() — invoking OpenFFParameterizer for $(smiles)")
    job = Crucible.prepare(OpenMMBackend(), spec, workdir; parameterizer=p)
    println("   workdir:        $(workdir)")
    println("   ligand parm7:   $(get(job.metadata, "ligand_topology", "—"))")
    println("   ligand rst7:    $(get(job.metadata, "ligand_coordinates", "—"))")
    println("   script size:    $(get(job.metadata, "script_size_bytes", 0)) bytes")
    println("\n   Next: cd $(workdir) && python run_openmm.py")
end

println("\n" * "=" ^ 50)
println("done.")
