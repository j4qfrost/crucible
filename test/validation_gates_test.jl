using Test
using Crucible

function _good_spec()
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    Crucible.spec_from_json(read(fixture, String))
end

@testset "semantic gate (Gate 2)" begin
    spec = _good_spec()
    r = Crucible.gate_semantic(spec)
    @test r.ok

    # NPT without barostat
    bad = deepcopy(spec)
    bad.protocol[3] = Crucible.DynamicsStage(
        role=:equilibrate, ensemble=:NPT, duration_ns=0.5, dt_fs=2.0,
        temperature_K=300.0, pressure_bar=1.0, thermostat=:langevin,
        barostat=nothing, friction_ps=1.0, constraints=:h_bonds,
        restraints=Crucible.RestraintSpec(),
    )
    r2 = Crucible.gate_semantic(bad)
    @test !r2.ok
    @test any(occursin("requires a barostat", e) for e in r2.errors)

    # Implicit solvent + NPT
    bad2 = deepcopy(spec)
    bad2.system.solvent.model isa Symbol
    # Can't easily mutate immutable struct field; build a fresh spec
    sys = Crucible.SystemSpec(spec.system.source, spec.system.n_atoms_estimate,
                              false,
                              Crucible.SolventSpec(model=:implicit_GBSA, ions_NaCl_mM=0.0))
    spec3 = MDSpec(system=sys, force_field=spec.force_field, protocol=spec.protocol,
                   observables=spec.observables, provenance=spec.provenance,
                   warnings=spec.warnings, notes=spec.notes)
    r3 = Crucible.gate_semantic(spec3)
    @test !r3.ok
    @test any(occursin("incoherent with implicit solvent", e) for e in r3.errors)

    # Big timestep without constraints — warning, not error
    bad4 = MDSpec(system=spec.system, force_field=spec.force_field,
                  protocol=Crucible.Stage[
                      Crucible.MinimizeStage(),
                      Crucible.DynamicsStage(
                          role=:equilibrate, ensemble=:NVT, duration_ns=0.1,
                          dt_fs=2.5, temperature_K=300.0, thermostat=:langevin,
                          friction_ps=1.0, constraints=:none,
                          restraints=Crucible.RestraintSpec(),
                      ),
                  ],
                  observables=Crucible.Observable[],
                  provenance=Dict{String,Crucible.Provenance}(),
                  warnings=String[], notes="")
    r4 = Crucible.gate_semantic(bad4)
    @test r4.ok      # warnings only
    @test !isempty(r4.warnings)
end

@testset "loadability gate (Gate 3)" begin
    spec = _good_spec()
    omm = OpenMMBackend()
    r = Crucible.gate_loadability(omm, spec)
    @test r.ok

    # Strip topology — ligand requires it
    no_top = Crucible.SystemSource(type=:user_supplied, topology=nothing,
                                   coordinates=spec.system.source.coordinates)
    bad_sys = Crucible.SystemSpec(no_top, spec.system.n_atoms_estimate,
                                  spec.system.has_ligand, spec.system.solvent)
    bad = MDSpec(system=bad_sys, force_field=spec.force_field,
                 protocol=spec.protocol, observables=spec.observables,
                 provenance=spec.provenance, warnings=spec.warnings, notes=spec.notes)
    r2 = Crucible.gate_loadability(omm, bad)
    @test !r2.ok
end

@testset "composed pipeline" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    json_str = read(fixture, String)
    spec = Crucible.spec_from_json(json_str)
    omm = OpenMMBackend()
    r = Crucible.run_validation(json_str, spec, omm)
    @test r.ok
end
