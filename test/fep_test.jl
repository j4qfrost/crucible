using Test
using Crucible

# Heavy-lift v1: Free-energy stage scaffolding (alchemical FEP).

function _fep_spec()
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:user_supplied, topology="lig.parm7", coordinates="lig.rst7"),
            500, true,
            SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                     ligand=:openff_sage_2_2_0),
        protocol = Stage[
            MinimizeStage(max_iterations=100),
            DynamicsStage(role=:equilibrate, ensemble=:NPT, duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          thermostat=:langevin, barostat=:monte_carlo,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
            FEPStage(kind=:decouple, target_selection="resname LIG",
                     lambda_windows=[0.0, 0.25, 0.5, 0.75, 1.0],
                     duration_per_window_ns=0.1, ensemble=:NPT,
                     temperature_K=300.0, pressure_bar=1.0),
        ],
        observables=Observable[],
        provenance=Dict{String,Provenance}(),
        warnings=String[], notes="ligand decoupling FEP")
end

@testset "FEPStage construction defaults" begin
    s = FEPStage(target_selection="resname LIG")
    @test s.kind == :decouple
    @test length(s.lambda_windows) == 11
    @test s.lambda_windows[1] == 0.0
    @test s.lambda_windows[end] == 1.0
    @test s.ensemble == :NPT
    @test s.temperature_K == 300.0
    @test s.pressure_bar == 1.0
end

@testset "FEP stage round-trip through JSON" begin
    spec = _fep_spec()
    json_str = Crucible.spec_to_json(spec)
    @test occursin("free_energy", json_str)
    @test occursin("decouple", json_str)
    @test occursin("resname LIG", json_str)
    spec2 = Crucible.spec_from_json(json_str)
    fep = spec2.protocol[3]
    @test fep isa FEPStage
    @test fep.kind == :decouple
    @test fep.target_selection == "resname LIG"
    @test length(fep.lambda_windows) == 5
    @test fep.duration_per_window_ns == 0.1
end

@testset "schema accepts free_energy stage" begin
    json_str = Crucible.spec_to_json(_fep_spec())
    r = Crucible.gate_schema(json_str)
    @test r.ok
end

@testset "schema rejects FEP with non-monotonic lambda windows" begin
    spec = _fep_spec()
    bad_fep = FEPStage(kind=:decouple, target_selection="resname LIG",
                       lambda_windows=[0.0, 0.5, 0.3, 1.0],  # drops!
                       duration_per_window_ns=0.1, ensemble=:NVT,
                       temperature_K=300.0, pressure_bar=nothing)
    bad = MDSpec(system=spec.system, force_field=spec.force_field,
                 protocol=Stage[bad_fep],
                 observables=spec.observables, provenance=spec.provenance,
                 warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("monotonic", e) for e in r.errors)
end

@testset "schema rejects FEP NPT without pressure" begin
    spec = _fep_spec()
    bad_fep = FEPStage(kind=:decouple, target_selection="resname LIG",
                       lambda_windows=[0.0, 0.5, 1.0],
                       duration_per_window_ns=0.1, ensemble=:NPT,
                       temperature_K=300.0, pressure_bar=nothing)
    bad = MDSpec(system=spec.system, force_field=spec.force_field,
                 protocol=Stage[bad_fep],
                 observables=spec.observables, provenance=spec.provenance,
                 warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
end

@testset "FEP feature is required from spec" begin
    feats = Crucible.required_features(_fep_spec())
    @test :alchemy in feats
end

@testset "OpenMM backend supports :alchemy and renders FEP block" begin
    omm = OpenMMBackend()
    @test :alchemy in Crucible.supported_features(omm)
    script = Crucible.render_script(omm, _fep_spec(); output_dir="/tmp/fep-test")
    @test occursin("AlchemicalRegion", script)
    @test occursin("AbsoluteAlchemicalFactory", script)
    @test occursin("u_kln", script)
    @test occursin("fep_3_u_kln.csv", script)
end

@testset "FEP annihilate vs decouple flips alchemy flags" begin
    spec = _fep_spec()
    decouple_script = Crucible.render_script(OpenMMBackend(), spec;
                                              output_dir="/tmp/fep-d")
    @test occursin("annihilate_electrostatics=False", decouple_script)
    annihilate = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=Stage[
            spec.protocol[1], spec.protocol[2],
            FEPStage(kind=:annihilate, target_selection="resname LIG",
                     lambda_windows=[0.0, 0.5, 1.0],
                     duration_per_window_ns=0.1, ensemble=:NPT,
                     temperature_K=300.0, pressure_bar=1.0),
        ],
        observables=spec.observables, provenance=spec.provenance,
        warnings=String[], notes="")
    a_script = Crucible.render_script(OpenMMBackend(), annihilate;
                                       output_dir="/tmp/fep-a")
    @test occursin("annihilate_electrostatics=True", a_script)
end
