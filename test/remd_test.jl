using Test
using Crucible

# Heavy-lift v1.5: REMD (replica exchange MD) stage scaffolding.

function _remd_spec(ladder=[300.0, 320.0, 342.0, 365.0])
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:user_supplied, coordinates="x.pdb"),
            500, false,
            SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                     ligand=:user_supplied),
        protocol = Stage[
            MinimizeStage(max_iterations=100),
            REMDStage(temperature_ladder_K=ladder,
                      duration_per_replica_ns=0.1,
                      exchange_attempt_period_ps=1.0,
                      ensemble=:NVT),
        ],
        observables = Observable[],
        provenance = Dict{String,Provenance}(),
        warnings = String[], notes = "REMD demo")
end

@testset "REMDStage construction" begin
    s = REMDStage(temperature_ladder_K=[300.0, 350.0])
    @test length(s.temperature_ladder_K) == 2
    @test s.duration_per_replica_ns == 0.5
    @test s.exchange_attempt_period_ps == 1.0
    @test s.ensemble == :NVT
end

@testset "REMD round-trip through JSON" begin
    spec = _remd_spec()
    json_str = Crucible.spec_to_json(spec)
    @test occursin("remd", json_str)
    @test occursin("temperature_ladder_K", json_str)
    spec2 = Crucible.spec_from_json(json_str)
    s = spec2.protocol[2]
    @test s isa REMDStage
    @test length(s.temperature_ladder_K) == 4
    @test s.temperature_ladder_K[1] == 300.0
end

@testset "schema accepts REMD stage" begin
    json_str = Crucible.spec_to_json(_remd_spec())
    r = Crucible.gate_schema(json_str)
    @test r.ok
end

@testset "semantic gate rejects non-monotonic ladder" begin
    bad = _remd_spec([300.0, 320.0, 310.0, 350.0])
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("strictly increasing", e) for e in r.errors)
end

@testset "semantic gate rejects REMD NPT without pressure" begin
    spec = _remd_spec()
    bad_remd = REMDStage(temperature_ladder_K=[300.0, 350.0],
                         duration_per_replica_ns=0.1, ensemble=:NPT,
                         pressure_bar=nothing)
    bad = MDSpec(system=spec.system, force_field=spec.force_field,
                 protocol=Stage[bad_remd], observables=spec.observables,
                 provenance=spec.provenance, warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
end

@testset "semantic gate warns on aggressive T-ratio" begin
    bad = _remd_spec([300.0, 500.0])  # 1.67x ratio
    r = Crucible.gate_semantic(bad)
    @test r.ok
    @test any(occursin("acceptance likely low", w) for w in r.warnings)
end

@testset "REMD features expose multi_replica + remd" begin
    feats = Crucible.required_features(_remd_spec())
    @test :remd in feats
    @test :multi_replica in feats
    @test :multi_gpu_eligible in feats   # ladder length=4
end

@testset "OpenMM renders REMD stage with openmmtools" begin
    script = Crucible.render_script(OpenMMBackend(), _remd_spec();
                                     output_dir="/tmp/remd-test")
    @test occursin("ParallelTemperingSampler", script)
    @test occursin("MultiStateReporter", script)
    @test occursin("LangevinSplittingDynamicsMove", script)
    @test occursin("remd_2.nc", script)
end
