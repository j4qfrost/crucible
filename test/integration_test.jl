using Test
using Crucible

# Integration smoke: the alanine-dipeptide fixture goes through ingest →
# spec → router → validator → renderer. Execution is opt-in (OpenMM is not
# in CI); set CRUCIBLE_RUN_OPENMM=1 to actually exec the rendered script.

function _alanine_spec()
    fixture_pdb = joinpath(@__DIR__, "fixtures", "alanine_dipeptide.pdb")
    @assert isfile(fixture_pdb)
    sys = Crucible.SystemSpec(
        Crucible.SystemSource(type=:user_supplied, coordinates=fixture_pdb),
        22, false,
        Crucible.SolventSpec(model=:vacuum, ions_NaCl_mM=0.0),
    )
    ff = Crucible.ForceFieldSpec(protein=:amber14sb, water=:vacuum, ligand=:user_supplied)
    proto = Crucible.Stage[
        Crucible.MinimizeStage(max_iterations=200, tolerance_kj_mol_nm=10.0),
        Crucible.DynamicsStage(
            role=:production, ensemble=:NVT, duration_ns=0.001,  # 500 steps @ 2 fs
            dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
            friction_ps=1.0, constraints=:h_bonds,
            restraints=Crucible.RestraintSpec(),
        ),
    ]
    MDSpec(
        system=sys, force_field=ff, protocol=proto,
        observables=[Crucible.Observable(type=:energy, selection="all", stride_ps=0.1)],
        provenance=Dict{String,Crucible.Provenance}(),
        warnings=String[], notes="alanine dipeptide vacuum smoke",
    )
end

@testset "alanine dipeptide pipeline (no execution)" begin
    spec = _alanine_spec()
    backends = [OpenMMBackend(), MollyBackend()]
    choice = Crucible.route_backend(spec; available=backends)
    # Vacuum / no ligand / NVT — Molly is the right pick here
    @test Crucible.backend_name(choice.backend) == :molly

    # Validate end-to-end (gates 1-3)
    spec_json = Crucible.spec_to_json(spec)
    report = Crucible.run_validation(spec_json, spec, choice.backend)
    @test report.ok

    # Render
    workdir = mktempdir(prefix="crucible-ala-")
    job = Crucible.prepare(choice.backend, spec, workdir)
    @test isfile(job.script_path)
    script = read(job.script_path, String)
    @test occursin("alanine_dipeptide.pdb", script)
end

@testset "alanine dipeptide live OpenMM smoke (opt-in)" begin
    if get(ENV, "CRUCIBLE_RUN_OPENMM", "0") != "1"
        @info "skipping live OpenMM smoke; set CRUCIBLE_RUN_OPENMM=1 to enable"
        @test true   # placeholder so the testset is not empty
        return
    end
    # Force OpenMM backend and run for 100 steps via Gate 4
    spec = _alanine_spec()
    omm = OpenMMBackend()
    workdir = mktempdir(prefix="crucible-ala-live-")
    job = Crucible.prepare(omm, spec, workdir)
    rep = Crucible.gate_preview(omm, job; n_steps=100)
    @test rep.ok
    @test isempty(rep.errors)
end
