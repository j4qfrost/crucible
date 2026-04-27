# Protein + ligand alchemical free-energy pipeline.
#
# Demonstrates the v1 :protein_ligand source path (PDBFixer + OpenFF, all
# at script-runtime) and the v1 FEPStage (alchemical λ windowing for
# binding free-energy estimates via MBAR).
#
# Run with:  julia --project examples/protein_ligand_fep.jl
#
# Caveat: free-energy methods are an entire research area. This example
# scaffolds the pipeline; producing a publication-quality ΔG_bind requires
# soak-time, careful equilibration, and an MBAR/BAR analysis pass that
# Crucible currently leaves to the user (the script writes u_kln.csv).

using Crucible

println("Crucible: protein + ligand FEP example")
println("=" ^ 60)

pdb_id        = "1ubq"           # ubiquitin (small, fast — for demo only)
ligand_smiles = "Cc1ccc(cc1)O"   # p-cresol — tiny, well-behaved
println("protein PDB:    $(pdb_id)")
println("ligand SMILES:  $(ligand_smiles)")

spec = MDSpec(
    system = SystemSpec(
        SystemSource(type=:protein_ligand, pdb_id=pdb_id,
                     ligand_smiles=ligand_smiles),
        2500, true,
        SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
    ),
    force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                 ligand=:openff_sage_2_2_0),
    protocol = Stage[
        MinimizeStage(max_iterations=500),
        DynamicsStage(role=:equilibrate, ensemble=:NVT, duration_ns=0.1,
                      dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec(selection=:heavy_atoms,
                                               kind=:harmonic,
                                               k_kj_mol_nm2=1000.0)),
        DynamicsStage(role=:equilibrate, ensemble=:NPT, duration_ns=0.5,
                      dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                      thermostat=:langevin, barostat=:monte_carlo,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
        FEPStage(kind=:decouple,
                 target_selection="resname LIG",
                 lambda_windows=collect(0.0:0.1:1.0),
                 duration_per_window_ns=0.5,
                 ensemble=:NPT,
                 temperature_K=300.0,
                 pressure_bar=1.0,
                 thermostat=:langevin,
                 friction_ps=1.0,
                 constraints=:h_bonds),
    ],
    observables = Observable[
        Observable(type=:trajectory, selection="all", stride_ps=10.0),
    ],
    provenance = Dict{String,Provenance}(
        "system.source.pdb_id" => Provenance(:user, cite="example", confidence=1.0),
        "system.source.ligand_smiles" => Provenance(:user, cite="example", confidence=1.0),
        "protocol[4].lambda_windows" => Provenance(:assumed,
            cite="11 evenly-spaced windows is a reasonable default for a small ligand",
            confidence=0.6),
    ),
    warnings = String["FEP windows + duration_per_window are demo-scale; production needs ≥1 ns/window."],
    notes = "demo: 1ubq + p-cresol decoupling FEP",
)

println("\n1. MDSpec built ($(length(spec.protocol)) stages, " *
        "$(length(spec.protocol[end].lambda_windows)) λ windows)")

report = Crucible.run_validation(Crucible.spec_to_json(spec), spec, OpenMMBackend())
println("\n2. validation: ok=$(report.ok)")
for w in report.warnings; println("   warn:  $(w)"); end
for e in report.errors;   println("   error: $(e)"); end

println("\n3. required features: $(join(sort(collect(Crucible.required_features(spec))), ", "))")

script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/pl-fep")
println("\n4. rendered: $(length(script)) bytes — needs openmm + pdbfixer + openff-toolkit + " *
        "openmmforcefields + openmmtools at runtime")
println()
println("   To execute:")
println("     pip install openmm pdbfixer openff-toolkit openmmforcefields openmmtools mdtraj")
println("     mkdir -p /tmp/pl-fep && cat > /tmp/pl-fep/run_openmm.py <<'EOF'")
println("     ... (use Crucible.prepare() to write it)")
println("     EOF")
println("     python /tmp/pl-fep/run_openmm.py")
println()
println("   The script emits fep_4_u_kln.csv; analyze with pymbar:")
println("     from pymbar import MBAR")
println("     u_kln = ... # load CSV")
println("     mbar = MBAR(u_kln, [steps_per_window]*K)")
println("     dG = mbar.compute_free_energy_differences()")

println("\n" * "=" ^ 60)
println("done.")
