# Membrane-embedded protein simulation.
#
# Demonstrates the v1.5 membrane support: LipidBilayer in SolventSpec,
# the lipid21 force field, and the renderer's automatic switch from
# isotropic MonteCarloBarostat to MonteCarloMembraneBarostat (semi-
# isotropic XY-coupled / Z-free, the physically correct choice for
# bilayer-equilibration NPT).
#
# Run with:  julia --project examples/membrane_protein.jl

using Crucible

println("Crucible: membrane-protein example")
println("=" ^ 60)

spec = MDSpec(
    system = SystemSpec(
        SystemSource(type=:user_supplied,
                     topology="gpcr_in_popc.parm7",
                     coordinates="gpcr_in_popc.rst7"),
        72_000, false,
        SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0,
                    membrane=LipidBilayer(composition=:POPC, n_lipids=200,
                                          chol_mol_fraction=0.0)),
    ),
    force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                 ligand=:user_supplied, lipid=:lipid21),
    protocol = Stage[
        MinimizeStage(max_iterations=2000),
        DynamicsStage(role=:equilibrate, ensemble=:NVT, duration_ns=0.5,
                      dt_fs=2.0, temperature_K=310.0,
                      thermostat=:langevin, friction_ps=1.0,
                      constraints=:h_bonds,
                      restraints=RestraintSpec(selection=:heavy_atoms,
                                               kind=:harmonic,
                                               k_kj_mol_nm2=2000.0)),
        DynamicsStage(role=:equilibrate, ensemble=:NPT, duration_ns=2.0,
                      dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                      thermostat=:langevin, barostat=:monte_carlo,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec(selection=:backbone,
                                               kind=:harmonic,
                                               k_kj_mol_nm2=500.0)),
        DynamicsStage(role=:production, ensemble=:NPT, duration_ns=10.0,
                      dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                      thermostat=:langevin, barostat=:monte_carlo,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
    ],
    observables = Observable[
        Observable(type=:trajectory, selection="all", stride_ps=20.0),
        Observable(type=:rmsd, selection="protein and name CA", stride_ps=20.0),
    ],
    provenance = Dict{String,Provenance}(
        "system.solvent.membrane.composition" => Provenance(:user, cite="example",
                                                            confidence=1.0),
        "force_field.lipid" => Provenance(:assumed,
            cite="lipid21 is the recommended Amber lipid FF for amber14sb proteins",
            confidence=0.9),
    ),
    warnings = String[],
    notes = "GPCR in POPC bilayer, 310 K physiological",
)

println("\n1. MDSpec built ($(length(spec.protocol)) stages, " *
        "$(spec.system.solvent.membrane.n_lipids) POPC + " *
        "$(spec.system.n_atoms_estimate) atoms total)")

report = Crucible.run_validation(Crucible.spec_to_json(spec), spec, OpenMMBackend())
println("\n2. validation: ok=$(report.ok)")
for w in report.warnings; println("   warn:  $(w)"); end
for e in report.errors;   println("   error: $(e)"); end

println("\n3. required features: $(join(sort(collect(Crucible.required_features(spec))), ", "))")

rec = Crucible.advise(spec; budget_hours=24.0)
if rec.chosen !== nothing
    println("\n4. cloud sizing:")
    println("   chosen:   $(rec.chosen.gpu)")
    println("   runtime:  $(round(rec.chosen.runtime_hours; digits=2)) h")
    println("   cost:     \$$(round(rec.chosen.on_demand_usd; digits=2))")
    println("   reason:   $(rec.chosen_reason)")
end

script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/membrane-demo")
println("\n5. rendered: $(length(script)) bytes — uses MonteCarloMembraneBarostat (XYIsotropic, ZFree)")

println("\n" * "=" ^ 60)
println("done.")
