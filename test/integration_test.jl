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

@testset "PDBFixer auto-build live smoke (opt-in, ubiquitin 1UBQ)" begin
    if get(ENV, "CRUCIBLE_RUN_OPENMM", "0") != "1"
        @info "skipping PDBFixer live smoke; set CRUCIBLE_RUN_OPENMM=1 to enable"
        @test true
        return
    end

    # Vacuum (no solvation) keeps the test under 30s on CPU. Ubiquitin is a
    # small, well-behaved protein with no ligands or non-canonical residues.
    sys = Crucible.SystemSpec(
        Crucible.SystemSource(type=:pdb_fetch, pdb_id="1UBQ"),
        1500, false,
        Crucible.SolventSpec(model=:vacuum, ions_NaCl_mM=0.0),
    )
    ff = Crucible.ForceFieldSpec(protein=:amber14sb, water=:vacuum, ligand=:user_supplied)
    proto = Crucible.Stage[
        Crucible.MinimizeStage(max_iterations=500, tolerance_kj_mol_nm=10.0),
        Crucible.DynamicsStage(
            role=:production, ensemble=:NVT, duration_ns=0.001,
            dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
            friction_ps=1.0, constraints=:h_bonds,
            restraints=Crucible.RestraintSpec(),
        ),
    ]
    spec = MDSpec(
        system=sys, force_field=ff, protocol=proto,
        observables=Crucible.Observable[],
        provenance=Dict{String,Crucible.Provenance}(),
        warnings=String[], notes="PDBFixer auto-build smoke",
    )

    omm = OpenMMBackend()
    @test Crucible.validate_spec(omm, spec).ok

    workdir = mktempdir(prefix="crucible-pdbfix-live-")
    job = Crucible.prepare(omm, spec, workdir)
    @test isfile(job.script_path)

    # Use Gate 4 to clamp at 50 steps — PDBFixer download + setup is the slow
    # part; we just need a tiny preview to confirm everything wires together.
    rep = Crucible.gate_preview(omm, job; n_steps=50)
    @test rep.ok
    @test isempty(rep.errors)

    # Prepared PDB should land in the workdir
    prepared = filter(f -> endswith(f, "_prepared.pdb"), readdir(job.workdir))
    @test !isempty(prepared)
end
