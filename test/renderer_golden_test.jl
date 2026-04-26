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

@testset "renderer scripts written to disk" begin
    spec = _good_spec()
    workdir = mktempdir(prefix="crucible-test-")
    job = Crucible.prepare(OpenMMBackend(), spec, workdir)
    @test isfile(job.script_path)
    @test endswith(job.script_path, "run_openmm.py")
    @test job.metadata["script_size_bytes"] > 100
end
