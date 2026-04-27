using Test
using Crucible

# v0.3.0 schema: new observable types (:sasa, :distance, :hbonds).

function _spec_with_obs(types::Vector{Symbol})
    obs = Observable[
        Observable(type=:trajectory, selection="all", stride_ps=10.0),
    ]
    for t in types
        sel = t == :distance ? "name CA and resid 1, name CA and resid 10" : "all"
        push!(obs, Observable(type=t, selection=sel, stride_ps=10.0))
    end
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:user_supplied, coordinates="x.pdb"),
            500, false,
            SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0)),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                     ligand=:user_supplied),
        protocol = Stage[
            MinimizeStage(),
            DynamicsStage(role=:production, ensemble=:NVT, duration_ns=1.0,
                          dt_fs=2.0, temperature_K=300.0,
                          thermostat=:langevin, friction_ps=1.0,
                          constraints=:h_bonds, restraints=RestraintSpec()),
        ],
        observables=obs, provenance=Dict{String,Provenance}(),
        warnings=String[], notes="obs v3 demo")
end

@testset "schema accepts :sasa / :distance / :hbonds" begin
    for t in (:sasa, :distance, :hbonds)
        spec = _spec_with_obs([t])
        json = Crucible.spec_to_json(spec)
        r = Crucible.gate_schema(json)
        @test r.ok
    end
end

@testset "schema rejects unknown observable type" begin
    bad = _spec_with_obs([:fake_observable])
    json = Crucible.spec_to_json(bad)
    r = Crucible.gate_schema(json)
    @test !r.ok
end

@testset "renderer emits sasa block" begin
    spec = _spec_with_obs([:sasa])
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/sasa-test")
    @test occursin("shrake_rupley", script)
    @test occursin("sasa.csv", script)
end

@testset "renderer emits distance block" begin
    spec = _spec_with_obs([:distance])
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/dist-test")
    @test occursin("compute_distances", script)
    @test occursin("distance.csv", script)
end

@testset "renderer emits hbonds block" begin
    spec = _spec_with_obs([:hbonds])
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/hb-test")
    @test occursin("baker_hubbard", script)
    @test occursin("hbonds.csv", script)
end

@testset "renderer omits mdtraj block when only :trajectory + :energy requested" begin
    spec = MDSpec(
        system = SystemSpec(SystemSource(type=:user_supplied, coordinates="x.pdb"),
                            500, false, SolventSpec(model=:vacuum, ions_NaCl_mM=0.0)),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:user_supplied),
        protocol = Stage[MinimizeStage(),
                         DynamicsStage(role=:production, ensemble=:NVT,
                             duration_ns=0.001, dt_fs=2.0, temperature_K=300.0,
                             thermostat=:langevin, friction_ps=1.0,
                             constraints=:h_bonds, restraints=RestraintSpec())],
        observables = Observable[Observable(type=:energy, selection="all", stride_ps=1.0)],
        provenance = Dict{String,Provenance}(),
        warnings = String[], notes = "")
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/no-mdt-test")
    @test occursin("no post-run mdtraj", script)
end
