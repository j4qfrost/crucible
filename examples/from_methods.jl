# examples/from_methods.jl
#
# Construct an MDSpec by hand (no LLM) for a typical Methods-section protocol.
# This is the same shape the AnthropicProvider would emit; useful for testing
# the renderer / validator pipeline end-to-end without an API call.
#
# Run from the repo root:
#   julia --project examples/from_methods.jl

using Pkg
Pkg.activate(@__DIR__ * "/..")

using Crucible

spec = MDSpec(
    system = Crucible.SystemSpec(
        Crucible.SystemSource(
            type = :user_supplied,
            topology = "kinase.prmtop",
            coordinates = "kinase.inpcrd",
        ),
        42_000,
        true,
        Crucible.SolventSpec(model = :TIP3P, ions_NaCl_mM = 150.0),
    ),
    force_field = Crucible.ForceFieldSpec(
        protein = :amber14sb,
        water   = :TIP3P,
        ligand  = :user_supplied,
    ),
    protocol = Crucible.Stage[
        Crucible.MinimizeStage(max_iterations = 5000, tolerance_kj_mol_nm = 10.0),
        Crucible.DynamicsStage(
            role = :equilibrate, ensemble = :NVT, duration_ns = 0.1,
            dt_fs = 2.0, temperature_K = 300.0,
            thermostat = :langevin, friction_ps = 1.0, constraints = :h_bonds,
            restraints = Crucible.RestraintSpec(
                selection = :heavy_atoms, kind = :harmonic, k_kj_mol_nm2 = 1000.0,
            ),
        ),
        Crucible.DynamicsStage(
            role = :equilibrate, ensemble = :NPT, duration_ns = 0.5,
            dt_fs = 2.0, temperature_K = 300.0, pressure_bar = 1.0,
            thermostat = :langevin, barostat = :monte_carlo,
            friction_ps = 1.0, constraints = :h_bonds,
        ),
        Crucible.DynamicsStage(
            role = :production, ensemble = :NPT, duration_ns = 10.0,
            dt_fs = 2.0, temperature_K = 300.0, pressure_bar = 1.0,
            thermostat = :langevin, barostat = :monte_carlo,
            friction_ps = 1.0, constraints = :h_bonds,
        ),
    ],
    observables = [
        Crucible.Observable(type = :rmsd, selection = "protein and name CA", stride_ps = 10.0),
        Crucible.Observable(type = :trajectory, selection = "all", stride_ps = 100.0),
    ],
    notes = "Hand-constructed example mirroring a typical kinase MD methods section.",
)

# Route to a backend.
backends = [OpenMMBackend(), MollyBackend()]
choice = route_backend(spec; available = backends)
println("Routed to: ", Crucible.backend_name(choice.backend))
println("Reason: ", choice.reason)

# Validate.
spec_json = Crucible.spec_to_json(spec)
report = Crucible.run_validation(spec_json, spec, choice.backend)
println("\nValidation: ", report.ok ? "OK" : "FAILED")
for w in report.warnings; println("  warning: ", w); end
for e in report.errors;   println("  error:   ", e); end

# Render to disk.
workdir = mktempdir(prefix = "crucible-example-")
job = Crucible.prepare(choice.backend, spec, workdir)
println("\nScript written to: ", job.script_path)
println("(", job.metadata["script_size_bytes"], " bytes)")

# Cloud sizing.
rec = Crucible.advise(spec; budget_hours = 6.0,
                            backend_name = Crucible.backend_name(choice.backend))
if rec.chosen !== nothing
    c = rec.chosen
    println("\nCloud recommendation: ", c.gpu, " — ",
            round(c.runtime_hours; digits = 2), " h, \$",
            round(c.on_demand_usd; digits = 2))
    println("  GCP: ", c.gcp_instance)
    println("  AWS: ", c.aws_instance)
end
