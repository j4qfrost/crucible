# Replica-exchange MD for protein-folding sampling.
#
# Demonstrates the v1.5 REMDStage. Spawns 8 replicas across an
# exponentially-spaced T ladder; each replica runs short MD windows
# separated by Metropolis-Hastings exchange attempts. Output is a
# multistate netcdf (`remd.nc`) suitable for openmmtools' replica-state
# extractor + WHAM/MBAR.
#
# Run with:  julia --project examples/remd_protein_folding.jl

using Crucible

println("Crucible: REMD example")
println("=" ^ 60)

# Exponential T-ladder bracketing the simulation range; ratio ≈ 1.10
# gives ~30% acceptance for a small protein.
ladder = [300.0, 313.0, 327.0, 342.0, 358.0, 374.0, 391.0, 408.0]
println("T-ladder: ", join((string(round(t; digits=1)) for t in ladder), " → "), " K")

spec = MDSpec(
    system = SystemSpec(
        SystemSource(type=:user_supplied, topology="protein.parm7",
                     coordinates="protein.rst7"),
        12_000, false,
        SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
    ),
    force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                 ligand=:user_supplied),
    protocol = Stage[
        MinimizeStage(max_iterations=500),
        DynamicsStage(role=:equilibrate, ensemble=:NVT, duration_ns=0.5,
                      dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
        REMDStage(
            temperature_ladder_K=ladder,
            duration_per_replica_ns=2.0,
            exchange_attempt_period_ps=2.0,
            ensemble=:NVT,
            thermostat=:langevin,
            friction_ps=1.0,
            constraints=:h_bonds,
        ),
    ],
    observables = Observable[],
    provenance = Dict{String,Provenance}(
        "protocol[3].temperature_ladder_K" => Provenance(:assumed,
            cite="exponential ladder, ratio=1.10, ~30% acceptance heuristic",
            confidence=0.7),
    ),
    warnings = String["REMD requires openmmtools.multistate at script-runtime; install via pip install openmmtools"],
    notes = "REMD demo: 8 replicas, 2 ns each",
)

println("\n1. MDSpec built ($(length(spec.protocol)) stages)")
report = Crucible.run_validation(Crucible.spec_to_json(spec), spec, OpenMMBackend())
println("\n2. validation: ok=$(report.ok)")
for w in report.warnings; println("   warn:  $(w)"); end

println("\n3. required features: $(join(sort(collect(Crucible.required_features(spec))), ", "))")

rec = Crucible.advise(spec; budget_hours=12.0)
if rec.chosen !== nothing
    println("\n4. cloud sizing:")
    println("   chosen:  $(rec.chosen.gpu)")
    println("   runtime: $(round(rec.chosen.runtime_hours; digits=2)) h")
    println("   cost:    \$$(round(rec.chosen.on_demand_usd; digits=2))")
end
for w in rec.warnings; println("   warn:    $(w)"); end

script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/remd-demo")
println("\n5. rendered: $(length(script)) bytes — runs $(length(ladder)) replicas via ParallelTemperingSampler")

println("\n" * "=" ^ 60)
println("done.")
