using Test
using Crucible

function _good_spec()
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    Crucible.spec_from_json(read(fixture, String))
end

@testset "router policy" begin
    spec = _good_spec()
    backends = [OpenMMBackend(), MollyBackend()]

    # Ligand + explicit solvent → OpenMM
    c = Crucible.route_backend(spec; available=backends)
    @test Crucible.backend_name(c.backend) == :openmm
    @test occursin("explicit solvent", c.reason) || occursin("ligand", c.reason)

    # User-forced Molly on this spec should error (ligand not supported)
    @test_throws Exception Crucible.route_backend(spec; available=backends, prefer=:molly)
end

@testset "molly path for implicit solvent" begin
    spec = _good_spec()
    sys = Crucible.SystemSpec(
        Crucible.SystemSource(type=:user_supplied, coordinates="apo.pdb"),
        2000, false,
        Crucible.SolventSpec(model=:implicit_GBSA, ions_NaCl_mM=0.0),
    )
    ff = Crucible.ForceFieldSpec(protein=:amber14sb, water=:implicit_GBSA, ligand=:user_supplied)
    proto = Crucible.Stage[
        Crucible.MinimizeStage(),
        Crucible.DynamicsStage(role=:production, ensemble=:NVT, duration_ns=1.0,
                               dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                               friction_ps=1.0, constraints=:h_bonds,
                               restraints=Crucible.RestraintSpec()),
    ]
    small = MDSpec(system=sys, force_field=ff, protocol=proto,
                   observables=Crucible.Observable[],
                   provenance=Dict{String,Crucible.Provenance}(),
                   warnings=String[], notes="")
    backends = [OpenMMBackend(), MollyBackend()]
    c = Crucible.route_backend(small; available=backends)
    @test Crucible.backend_name(c.backend) == :molly
end
