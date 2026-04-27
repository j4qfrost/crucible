using Test
using Crucible

# v1.5.1 polish: MollyBackend rejects v1+ stage types + membrane systems
# with clear error messages directing the user to OpenMMBackend.

function _base_proto()
    Stage[
        MinimizeStage(),
        DynamicsStage(role=:equilibrate, ensemble=:NVT, duration_ns=0.5,
                      dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
    ]
end

function _base_spec(; protocol=_base_proto(), system_kwargs=(;), ff_kwargs=(;))
    sys = SystemSpec(
        SystemSource(type=:user_supplied, coordinates="x.pdb"),
        500, false,
        SolventSpec(model=:implicit_GBSA, ions_NaCl_mM=0.0; system_kwargs...),
    )
    ff = ForceFieldSpec(protein=:amber14sb, water=:implicit_GBSA,
                        ligand=:user_supplied; ff_kwargs...)
    MDSpec(system=sys, force_field=ff, protocol=protocol,
           observables=Observable[],
           provenance=Dict{String,Provenance}(),
           warnings=String[], notes="")
end

@testset "Molly accepts a vanilla NVT/implicit spec" begin
    r = Crucible.validate_spec(MollyBackend(), _base_spec())
    @test r.ok
end

@testset "Molly rejects FEPStage with a route-to-OpenMM message" begin
    fep = FEPStage(target_selection="resname LIG",
                   lambda_windows=[0.0, 0.5, 1.0],
                   duration_per_window_ns=0.1,
                   ensemble=:NVT, pressure_bar=nothing)
    r = Crucible.validate_spec(MollyBackend(),
        _base_spec(protocol=Stage[MinimizeStage(), fep]))
    @test !r.ok
    @test any(occursin("FEPStage", e) && occursin("OpenMM", e) for e in r.errors)
end

@testset "Molly rejects REMDStage" begin
    remd = REMDStage(temperature_ladder_K=[300.0, 320.0],
                     duration_per_replica_ns=0.1, ensemble=:NVT)
    r = Crucible.validate_spec(MollyBackend(),
        _base_spec(protocol=Stage[MinimizeStage(), remd]))
    @test !r.ok
    @test any(occursin("REMDStage", e) && occursin("OpenMM", e) for e in r.errors)
end

@testset "Molly rejects MetadynamicsStage" begin
    cvs = CollectiveVariable[
        CollectiveVariable(kind=:distance, name="d", selection="1,2"),
    ]
    metad = MetadynamicsStage(cvs=cvs, ensemble=:NVT, temperature_K=300.0)
    r = Crucible.validate_spec(MollyBackend(),
        _base_spec(protocol=Stage[MinimizeStage(), metad]))
    @test !r.ok
    @test any(occursin("MetadynamicsStage", e) && occursin("OpenMM", e) for e in r.errors)
end

@testset "Molly rejects membrane systems" begin
    sys = SystemSpec(
        SystemSource(type=:user_supplied, coordinates="x.pdb"),
        45000, false,
        SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0,
                    membrane=LipidBilayer(composition=:POPC, n_lipids=128)),
    )
    ff = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                        ligand=:user_supplied, lipid=:lipid21)
    spec = MDSpec(system=sys, force_field=ff, protocol=_base_proto(),
                  observables=Observable[],
                  provenance=Dict{String,Provenance}(),
                  warnings=String[], notes="")
    r = Crucible.validate_spec(MollyBackend(), spec)
    @test !r.ok
    @test any(occursin("lipid bilayer", e) && occursin("OpenMM", e) for e in r.errors)
end

@testset "Router prefers OpenMM for v1+ features" begin
    fep = FEPStage(target_selection="resname LIG",
                   lambda_windows=[0.0, 0.5, 1.0],
                   duration_per_window_ns=0.1,
                   ensemble=:NVT, pressure_bar=nothing)
    spec = _base_spec(protocol=Stage[MinimizeStage(), fep])
    choice = Crucible.route_backend(spec;
        available=[OpenMMBackend(), MollyBackend()])
    @test Crucible.backend_name(choice.backend) == :openmm
    @test occursin("v1+", choice.reason) || occursin("OpenMM", choice.reason)
end
