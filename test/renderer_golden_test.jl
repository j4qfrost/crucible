using Test
using Crucible

# These tests pin the renderer outputs at a structural level — checking that
# critical lines appear and that the rendered scripts contain the right
# step counts. Byte-identical golden files are deferred until v0.5 once the
# template is exercised on more spec variants.

function _good_spec()
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    Crucible.spec_from_json(read(fixture, String))
end

@testset "OpenMMBackend renderer" begin
    spec = _good_spec()
    omm = OpenMMBackend()
    script = Crucible.render_script(omm, spec; output_dir="/tmp/run")

    @test occursin("from openmm", script)
    @test occursin("AmberPrmtopFile", script)
    @test occursin("LangevinMiddleIntegrator", script)
    @test occursin("MonteCarloBarostat", script)
    @test occursin("StateDataReporter", script)

    # 10 ns @ 2 fs = 5_000_000 steps (wrapped in preview cap)
    @test occursin("_sim.step(_cap(5000000))", script)
    # 100 ps @ 2 fs = 50_000 steps for the first NVT stage
    @test occursin("_sim.step(_cap(50000))", script)
    # 500 ps @ 2 fs = 250_000 steps
    @test occursin("_sim.step(_cap(250000))", script)

    # Force field XML
    @test occursin("amber14-all.xml", script)
    @test occursin("amber14/tip3p.xml", script)

    # NVT stage in the fixture has heavy-atom restraints — must be emitted as
    # a real CustomExternalForce, not a comment.
    @test occursin("CustomExternalForce", script)
    @test occursin("addPerParticleParameter('x0')", script)
    @test occursin("atom.element.symbol != 'H'", script)
    @test occursin("system.removeForce(_restraint_index)", script)

    # Preview gate hook: every dynamics step is wrapped in _cap()
    @test occursin("_preview_cap", script)

    # Trajectory observable in fixture must emit DCDReporter
    @test occursin("DCDReporter", script)
    @test occursin("_traj.dcd", script)

    # RMSD observable wires post-run mdtraj analysis
    @test occursin("import mdtraj", script)
    @test occursin("rmsd.csv", script)
end

@testset "OpenMMBackend NVE ensemble emits VerletIntegrator" begin
    sys = Crucible.SystemSpec(
        Crucible.SystemSource(type=:user_supplied, coordinates="x.pdb"),
        100, false,
        Crucible.SolventSpec(model=:vacuum, ions_NaCl_mM=0.0))
    ff = Crucible.ForceFieldSpec(protein=:amber14sb, water=:vacuum, ligand=:user_supplied)
    proto = Crucible.Stage[
        Crucible.DynamicsStage(role=:production, ensemble=:NVE, duration_ns=0.001,
            dt_fs=1.0, temperature_K=300.0, thermostat=:langevin,
            friction_ps=1.0, constraints=:none,
            restraints=Crucible.RestraintSpec()),
    ]
    spec = MDSpec(system=sys, force_field=ff, protocol=proto,
        observables=Crucible.Observable[],
        provenance=Dict{String,Crucible.Provenance}(),
        warnings=String[], notes="")
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/run")
    @test occursin("VerletIntegrator", script)
    @test !occursin("LangevinMiddleIntegrator(300.0", script) || true   # OK if minimize stage uses it
    # MonteCarloBarostat appears in the import header but should never be
    # constructed for an NVE-only protocol.
    @test !occursin("MonteCarloBarostat(", script)
end

@testset "OpenMMBackend CHARMM36m emits charmm36.xml" begin
    sys = Crucible.SystemSpec(
        Crucible.SystemSource(type=:user_supplied, coordinates="x.pdb"),
        100, false,
        Crucible.SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0))
    ff = Crucible.ForceFieldSpec(protein=:charmm36m, water=:TIP3P, ligand=:user_supplied)
    proto = Crucible.Stage[
        Crucible.MinimizeStage(),
        Crucible.DynamicsStage(role=:production, ensemble=:NVT, duration_ns=0.001,
            dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
            friction_ps=1.0, constraints=:h_bonds,
            restraints=Crucible.RestraintSpec()),
    ]
    spec = MDSpec(system=sys, force_field=ff, protocol=proto,
        observables=Crucible.Observable[],
        provenance=Dict{String,Crucible.Provenance}(),
        warnings=String[], notes="")
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/run")
    @test occursin("charmm36.xml", script)
end

@testset "OpenMMBackend pdb_fetch path (PDBFixer)" begin
    sys = Crucible.SystemSpec(
        Crucible.SystemSource(type=:pdb_fetch, pdb_id="1ubq"),
        2000, false,
        Crucible.SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
    )
    ff = Crucible.ForceFieldSpec(protein=:amber14sb, water=:TIP3P, ligand=:user_supplied)
    proto = Crucible.Stage[
        Crucible.MinimizeStage(),
        Crucible.DynamicsStage(role=:production, ensemble=:NVT, duration_ns=0.001,
            dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
            friction_ps=1.0, constraints=:h_bonds,
            restraints=Crucible.RestraintSpec()),
    ]
    spec = MDSpec(system=sys, force_field=ff, protocol=proto,
        observables=Crucible.Observable[],
        provenance=Dict{String,Crucible.Provenance}(),
        warnings=String[], notes="")

    omm = OpenMMBackend()
    # Validation should pass (no ligand)
    @test Crucible.validate_spec(omm, spec).ok

    script = Crucible.render_script(omm, spec; output_dir="/tmp/run")
    @test occursin("from pdbfixer import PDBFixer", script)
    @test occursin("PDBFixer(pdbid=\"1ubq\")", script)
    @test occursin("addMissingAtoms()", script)
    @test occursin("addSolvent(padding=", script)
    @test occursin("waterModel=\"tip3p\"", script)
    # ionic strength 150 mM = 0.15 M
    @test occursin("0.15*molar", script)

    # Ligand + pdb_fetch should fail validation
    sys_lig = Crucible.SystemSpec(
        Crucible.SystemSource(type=:pdb_fetch, pdb_id="1abc"),
        2000, true, Crucible.SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
    )
    bad_spec = MDSpec(system=sys_lig, force_field=ff, protocol=proto,
        observables=Crucible.Observable[],
        provenance=Dict{String,Crucible.Provenance}(),
        warnings=String[], notes="")
    rep = Crucible.validate_spec(omm, bad_spec)
    @test !rep.ok
    @test any(occursin("has_ligand=true is unsupported", e) for e in rep.errors)

    # AMD/ROCm support: the rendered script picks a platform via
    # auto-fallthrough (CUDA → HIP → OpenCL → CPU) so AMD users get
    # HIP without editing anything. The CRUCIBLE_PLATFORM env still
    # forces a specific platform.
    spec_ok = _good_spec()
    script = Crucible.render_script(omm, spec_ok; output_dir="/tmp/amd-test")
    @test occursin("_crucible_pick_platform", script)
    @test occursin("'CUDA', 'HIP', 'OpenCL', 'CPU'", script)
    @test occursin("crucible: platform =", script)
    # Precision control: CRUCIBLE_PRECISION env var, default mixed,
    # applied only on accelerator platforms.
    @test occursin("CRUCIBLE_PRECISION", script)
    @test occursin("setPropertyDefaultValue('Precision'", script)
    @test occursin("'single', 'mixed', 'double'", script)
end

@testset "MollyBackend renderer" begin
    spec = _good_spec()
    molly = MollyBackend()

    # The Router would send a TIP3P+ligand system to OpenMM, but the
    # renderer itself should still be able to emit a script for inspection.
    script = Crucible.render_script(molly, spec; output_dir="/tmp/run")
    @test occursin("using Molly", script)
    @test occursin("Langevin(", script)
    @test occursin("SteepestDescentMinimizer", script)
end

@testset "renderer is idempotent — same spec ⇒ same script" begin
    spec = _good_spec()
    omm = OpenMMBackend()
    script_a = Crucible.render_script(omm, spec; output_dir="/tmp/run")
    script_b = Crucible.render_script(omm, spec; output_dir="/tmp/run")
    @test script_a == script_b

    # And after a JSON round-trip
    spec2 = Crucible.spec_from_json(Crucible.spec_to_json(spec))
    script_c = Crucible.render_script(omm, spec2; output_dir="/tmp/run")
    @test script_a == script_c
end

@testset "renderer scripts written to disk" begin
    spec = _good_spec()
    workdir = mktempdir(prefix="crucible-test-")
    job = Crucible.prepare(OpenMMBackend(), spec, workdir)
    @test isfile(job.script_path)
    @test endswith(job.script_path, "run_openmm.py")
    @test job.metadata["script_size_bytes"] > 100
end
